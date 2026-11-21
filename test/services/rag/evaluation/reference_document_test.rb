require "test_helper"

class RagEvaluationReferenceDocumentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "imports, processes, and embeds the reference once per user without enqueuing duplicate jobs" do
    user = users(:one)
    provider = FakeProvider.new
    configuration = embedding_configuration
    service = reference_document(user, configuration, provider)

    assert_no_enqueued_jobs do
      @document = service.call
    end

    assert_equal user, @document.user
    assert_equal "rag_evaluation_wildlife_reference.pdf", @document.filename
    assert_equal "completed", @document.status
    assert_operator @document.document_chunks.count, :>, 0
    assert_equal @document.document_chunks.count,
      @document.document_chunk_embeddings.where(configuration.identity.merge(status: "completed")).count
    assert_equal 1, provider.calls.length

    existing = service.call

    assert_equal @document.id, existing.id
    assert_equal 1, provider.calls.length
  end

  test "does not reuse another user's reference document" do
    configuration = embedding_configuration
    first_document = reference_document(users(:one), configuration, FakeProvider.new).call
    second_document = reference_document(users(:two), configuration, FakeProvider.new).call

    assert_not_equal first_document.id, second_document.id
    assert_equal users(:one), first_document.user
    assert_equal users(:two), second_document.user
  end

  test "fails explicitly when the reference PDF is absent" do
    service = Rag::Evaluation::ReferenceDocument.new(
      user: users(:one),
      path: Rails.root.join("tmp/missing-rag-evaluation-reference.pdf"),
      embedding_configuration: embedding_configuration,
      embedding_generator: FakeGenerator.new
    )

    error = assert_raises(ArgumentError) { service.call }

    assert_includes error.message, "Evaluation reference PDF not found"
  end

  private

  def reference_document(user, configuration, provider)
    Rag::Evaluation::ReferenceDocument.new(
      user: user,
      embedding_configuration: configuration,
      embedding_generator: Embeddings::Generator.new(configuration: configuration, provider: provider)
    )
  end

  def embedding_configuration
    Embeddings::Configuration.new(
      "EMBEDDING_MODEL" => "evaluation-test-model",
      "EMBEDDING_DIMENSIONS" => "2",
      "EMBEDDING_CONFIGURATION_VERSION" => "evaluation-test-v1",
      "EMBEDDING_BATCH_SIZE" => "100"
    )
  end

  class FakeGenerator
    def call(_chunks)
    end
  end

  class FakeProvider
    attr_reader :calls

    def initialize
      @calls = []
    end

    def embed(texts, prefix: nil)
      @calls << texts
      texts.map { [ 0.1, 0.2 ] }
    end
  end
end
