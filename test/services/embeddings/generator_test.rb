require "test_helper"

class Embeddings::GeneratorTest < ActiveSupport::TestCase
  setup do
    @configuration = configuration
    @provider = FakeProvider.new
    @document = create_document
    @chunk = @document.document_chunks.create!(content: "A multilingual chunk.", position: 1)
  end

  test "stores a pgvector embedding with model metadata and skips valid existing vectors" do
    generator.call(DocumentChunk.where(id: @chunk.id))

    record = @chunk.document_chunk_embeddings.sole
    assert_equal [ 1.0, 2.0 ], record.embedding
    assert_equal "openai_compatible", record.provider
    assert_equal "test-model", record.model
    assert_equal 2, record.dimensions
    assert_equal "test-v1", record.configuration_version
    assert_equal "completed", record.status
    assert record.current_for?(@chunk.content)

    generator.call(DocumentChunk.where(id: @chunk.id))

    assert_equal 1, @provider.calls.length
  end

  test "invalidates and regenerates when chunk content changes" do
    generator.call(DocumentChunk.where(id: @chunk.id))
    @chunk.update!(content: "Updated multilingual content.")
    record = @chunk.document_chunk_embeddings.sole

    assert_equal "pending", record.status
    assert_nil record.embedding

    generator.call(DocumentChunk.where(id: @chunk.id))

    record.reload
    assert_equal 2, @provider.calls.length
    assert_equal Digest::SHA256.hexdigest(@chunk.content), record.input_checksum
    assert record.current_for?(@chunk.content)
  end

  test "stores multiple dimensions and models for the same chunk independently" do
    generator.call(DocumentChunk.where(id: @chunk.id))
    other_configuration = configuration(
      "EMBEDDING_MODEL" => "other-model",
      "EMBEDDING_DIMENSIONS" => "3",
      "EMBEDDING_CONFIGURATION_VERSION" => "test-v2"
    )
    other_provider = FakeProvider.new([ 3.0, 4.0, 5.0 ])

    Embeddings::Generator.new(configuration: other_configuration, provider: other_provider)
      .call(DocumentChunk.where(id: @chunk.id))

    assert_equal 2, @chunk.document_chunk_embeddings.count
    assert_equal [ 2, 3 ], @chunk.document_chunk_embeddings.order(:dimensions).pluck(:dimensions)
  end

  test "records provider failures and retries failed chunks safely" do
    @provider.failures_remaining = 1
    generator.call(DocumentChunk.where(id: @chunk.id))

    record = @chunk.document_chunk_embeddings.sole
    assert_equal "failed", record.status
    assert_match "provider unavailable", record.error_message
    assert_nil record.embedding

    generator.call(DocumentChunk.where(id: @chunk.id))

    assert_equal "completed", record.reload.status
    assert_equal 2, @provider.calls.length
  end

  test "rejects unexpected dimensions and chunks exceeding the configured input limit" do
    @provider.vector = [ 1.0 ]
    generator.call(DocumentChunk.where(id: @chunk.id))
    assert_equal "failed", @chunk.document_chunk_embeddings.sole.status

    @chunk.update!(content: "x" * 11)
    limited_config = configuration("EMBEDDING_MAX_INPUT_CHARACTERS" => "10")
    limited_provider = FakeProvider.new
    Embeddings::Generator.new(configuration: limited_config, provider: limited_provider)
      .call(DocumentChunk.where(id: @chunk.id))

    record = @chunk.document_chunk_embeddings.sole
    assert_equal "failed", record.status
    assert_match "exceeds", record.error_message
    assert_empty limited_provider.calls
  end

  test "marks empty chunks as failed without making a provider request" do
    @chunk.update_column(:content, " ")

    generator.call(DocumentChunk.where(id: @chunk.id))

    record = @chunk.document_chunk_embeddings.sole
    assert_equal "failed", record.status
    assert_match "empty", record.error_message
    assert_empty @provider.calls
  end

  test "does not duplicate a recent in-progress generation but reclaims stale work" do
    record = @chunk.document_chunk_embeddings.create!(
      provider: @configuration.provider,
      model: @configuration.model,
      dimensions: @configuration.dimensions,
      configuration_version: @configuration.configuration_version,
      input_checksum: Digest::SHA256.hexdigest(@chunk.content),
      status: "processing"
    )

    generator.call(DocumentChunk.where(id: @chunk.id))
    assert_empty @provider.calls

    record.update_column(:updated_at, 31.minutes.ago)
    generator.call(DocumentChunk.where(id: @chunk.id))

    assert_equal 1, @provider.calls.length
    assert_equal "completed", record.reload.status
  end

  test "does not persist vectors when chunk content changes during a provider request" do
    @provider.on_embed = -> { @chunk.update!(content: "Changed during request.") }

    generator.call(DocumentChunk.where(id: @chunk.id))

    record = @chunk.document_chunk_embeddings.sole
    assert_equal "pending", record.status
    assert_nil record.embedding
    assert_not record.current_for?(@chunk.content)
  end

  test "an older request cannot overwrite a newer embedding after a content update" do
    newer_provider = FakeProvider.new([ 3.0, 4.0 ])
    @provider.on_embed = lambda do
      @chunk.update!(content: "Updated during request.")
      Embeddings::Generator.new(configuration: @configuration, provider: newer_provider)
        .call(DocumentChunk.where(id: @chunk.id))
    end

    generator.call(DocumentChunk.where(id: @chunk.id))

    record = @chunk.document_chunk_embeddings.sole
    assert_equal [ 3.0, 4.0 ], record.embedding
    assert_equal Digest::SHA256.hexdigest(@chunk.content), record.input_checksum
    assert record.current_for?(@chunk.content)
  end

  test "sends chunks to the provider in configured batch sizes" do
    second_chunk = @document.document_chunks.create!(content: "Another chunk.", position: 2)
    third_chunk = @document.document_chunks.create!(content: "A third chunk.", position: 3)

    generator.call(@document.document_chunks)

    assert_equal [ 2, 1 ], @provider.calls.map(&:length)
    assert_equal 3, @document.document_chunk_embeddings.where(status: "completed").count
    assert_equal [ @chunk.id, second_chunk.id, third_chunk.id ].sort,
      @document.document_chunk_embeddings.pluck(:document_chunk_id).sort
  end

  private

  def generator
    Embeddings::Generator.new(configuration: @configuration, provider: @provider)
  end

  def configuration(overrides = {})
    Embeddings::Configuration.new(
      {
        "EMBEDDING_MODEL" => "test-model",
        "EMBEDDING_DIMENSIONS" => "2",
        "EMBEDDING_CONFIGURATION_VERSION" => "test-v1",
        "EMBEDDING_BATCH_SIZE" => "2"
      }.merge(overrides)
    )
  end

  def create_document
    document = Document.new(user: users(:one))
    document.file.attach(
      io: StringIO.new("A test document."),
      filename: "embedding-test.txt",
      content_type: "text/plain"
    )
    document.save!
    document
  end

  class FakeProvider
    attr_accessor :vector, :failures_remaining, :on_embed
    attr_reader :calls

    def initialize(vector = [ 1.0, 2.0 ])
      @vector = vector
      @failures_remaining = 0
      @calls = []
    end

    def embed(texts)
      @calls << texts
      on_embed&.call
      if failures_remaining.positive?
        self.failures_remaining -= 1
        raise Embeddings::Provider::Error, "provider unavailable"
      end

      texts.map { @vector }
    end
  end
end
