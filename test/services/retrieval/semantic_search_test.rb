require "test_helper"

class Retrieval::SemanticSearchTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @other_user = users(:two)
    @configuration = Retrieval::SearchConfiguration.new(
      embedding_configuration: Embeddings::Configuration.new(
        "EMBEDDING_MODEL" => "multilingual-test-model",
        "EMBEDDING_DIMENSIONS" => "2",
        "EMBEDDING_CONFIGURATION_VERSION" => "test-v1"
      ),
      top_k: 2,
      threshold: 0.5
    )
    @query_embedder = FakeQueryEmbedder.new([ 1.0, 0.0 ])
    @document = create_document(@user, "english.txt")
    @closest_chunk = create_chunk(@document, "English source chunk", 1, [ 0.99, 0.01 ], page_start: 2)
    @next_chunk = create_chunk(@document, "Ukrainian source chunk", 2, [ 0.8, 0.2 ], page_start: 3)
    @distant_chunk = create_chunk(@document, "Distant chunk", 3, [ 0.0, 1.0 ])
  end

  test "retrieves English and Ukrainian chunks for a Ukrainian query in relevance order" do
    results = search.call("запит українською", user: @user)

    assert_equal [ @closest_chunk.id, @next_chunk.id ],
      results.map { |result| DocumentChunk.find_by!(content: result.content).id }
    assert results.first.score > results.second.score
    assert_equal @document.id, results.first.document_id
    assert_equal "english.txt", results.first.filename
    assert_equal 2, results.first.page_start
    assert_equal 1, results.first.position
    assert_equal "cosine", results.first.metric
    assert_equal "multilingual-test-model", results.first.model
    assert_equal 2, results.first.dimensions
  end

  test "retrieves Ukrainian chunks for a Russian query" do
    results = search.call("Что такое семантический поиск?", user: @user)

    assert_equal "Ukrainian source chunk", results.first.content
    assert_equal "English source chunk", results.second.content
  end

  test "applies similarity thresholds, document filters, and chunk metadata filters" do
    @next_chunk.update!(metadata: { "category" => "guide", "language" => "uk" })
    configuration = Retrieval::SearchConfiguration.new(
      embedding_configuration: @configuration.embedding_configuration,
      top_k: 10,
      threshold: 0.95
    )
    filtered_search = Retrieval::SemanticSearch.new(configuration: configuration, query_embedder: @query_embedder)

    results = filtered_search.call(
      "question",
      user: @user,
      document_id: @document.id,
      metadata: { "category" => "guide" }
    )

    assert_equal [ "Ukrainian source chunk" ], results.map(&:content)
    assert_empty filtered_search.call("question", user: @user, document_id: -1)
  end

  test "does not retrieve another user's chunks or mix embedding identities" do
    other_document = create_document(@other_user, "private.txt")
    create_chunk(other_document, "Private content", 1, [ 1.0, 0.0 ])
    alternate_configuration = Embeddings::Configuration.new(
      "EMBEDDING_MODEL" => "other-model",
      "EMBEDDING_DIMENSIONS" => "2",
      "EMBEDDING_CONFIGURATION_VERSION" => "test-v2"
    )
    alternate_chunk = @document.document_chunks.create!(content: "Other model content", position: 4)
    create_embedding(alternate_chunk, alternate_configuration, [ 1.0, 0.0 ])

    results = search.call("query", user: @user)

    assert results.all? { |result| result.document_id == @document.id }
    assert_not_includes results.map(&:content), "Other model content"
    assert_empty search.call("query", user: @user, document_id: other_document.id)
  end

  test "ignores incomplete and dimension-invalid embeddings" do
    pending_chunk = @document.document_chunks.create!(content: "Pending", position: 5)
    pending_chunk.document_chunk_embeddings.create!(
      provider: @configuration.embedding_identity[:provider],
      model: @configuration.embedding_identity[:model],
      dimensions: 2,
      configuration_version: @configuration.embedding_identity[:configuration_version],
      input_checksum: "pending",
      status: "pending"
    )

    results = search.call("query", user: @user)

    assert_not_includes results.map(&:content), "Pending"
    assert_not_includes results.map(&:content), "Distant chunk"
  end

  test "supports inner product and Euclidean distance thresholds" do
    inner_product = Retrieval::SemanticSearch.new(
      configuration: Retrieval::SearchConfiguration.new(
        embedding_configuration: @configuration.embedding_configuration,
        metric: "inner_product",
        threshold: 0.9
      ),
      query_embedder: @query_embedder
    ).call("query", user: @user)
    euclidean = Retrieval::SemanticSearch.new(
      configuration: Retrieval::SearchConfiguration.new(
        embedding_configuration: @configuration.embedding_configuration,
        metric: "euclidean",
        threshold: 0.2
      ),
      query_embedder: @query_embedder
    ).call("query", user: @user)

    assert_equal [ "English source chunk" ], inner_product.map(&:content)
    assert_equal [ "English source chunk" ], euclidean.map(&:content)
    assert_operator inner_product.first.score, :>, 0.9
    assert_operator euclidean.first.distance, :<, 0.2
  end

  test "requires a user and hash-shaped metadata filters" do
    assert_raises(ArgumentError) { search.call("query", user: nil) }
    assert_raises(ArgumentError) { search.call("query", user: @user, metadata: "invalid") }
  end

  private

  def search
    @search ||= Retrieval::SemanticSearch.new(
      configuration: @configuration,
      query_embedder: @query_embedder
    )
  end

  def create_document(user, filename)
    document = Document.new(user: user)
    document.file.attach(
      io: StringIO.new("Source document."),
      filename: filename,
      content_type: "text/plain"
    )
    document.save!
    document
  end

  def create_chunk(document, content, position, vector, page_start: nil)
    chunk = document.document_chunks.create!(
      content: content,
      position: position,
      page_start: page_start,
      metadata: { "language" => "en" }
    )
    create_embedding(chunk, @configuration.embedding_configuration, vector)
    chunk
  end

  def create_embedding(chunk, configuration, vector)
    chunk.document_chunk_embeddings.create!(
      provider: configuration.provider,
      model: configuration.model,
      dimensions: configuration.dimensions,
      configuration_version: configuration.configuration_version,
      input_checksum: Digest::SHA256.hexdigest(chunk.content),
      status: "completed",
      embedding: vector
    )
  end

  class FakeQueryEmbedder
    def initialize(vector)
      @vector = vector
    end

    def call(query)
      query.include?("Что") ? [ 0.8, 0.2 ] : @vector
    end
  end
end
