require "test_helper"

class Retrieval::SearchConfigurationTest < ActiveSupport::TestCase
  test "uses sensible retrieval defaults and the current embedding identity" do
    embedding_configuration = Embeddings::Configuration.new(
      "EMBEDDING_MODEL" => "test-model",
      "EMBEDDING_DIMENSIONS" => "2",
      "EMBEDDING_CONFIGURATION_VERSION" => "test-v1"
    )
    configuration = Retrieval::SearchConfiguration.new(embedding_configuration: embedding_configuration)

    assert_equal 5, configuration.top_k
    assert_nil configuration.threshold
    assert_equal "cosine", configuration.metric
    assert_equal embedding_configuration.identity, configuration.embedding_identity
  end

  test "converts cosine similarity thresholds to pgvector distances" do
    configuration = Retrieval::SearchConfiguration.new(threshold: 0.7)

    assert_in_delta 0.3, configuration.neighbor_threshold
  end

  test "selects an exact stored embedding identity for query generation" do
    configuration = Retrieval::SearchConfiguration.new(
      embedding_configuration: Embeddings::Configuration.new(
        "EMBEDDING_API_BASE_URL" => "http://localhost:9000/v1",
        "EMBEDDING_API_KEY" => "test-key",
        "EMBEDDING_MODEL" => "configured-model",
        "EMBEDDING_DIMENSIONS" => "2"
      ),
      embedding_identity: {
        provider: "openai_compatible",
        model: "stored-model",
        dimensions: 3,
        configuration_version: "stored-v2"
      },
      metric: "inner_product",
      threshold: 0.4
    )

    assert_equal(
      {
        provider: "openai_compatible",
        model: "stored-model",
        dimensions: 3,
        configuration_version: "stored-v2"
      },
      configuration.embedding_identity
    )
    assert_equal "stored-model", configuration.embedding_configuration.model
    assert_equal 3, configuration.embedding_configuration.dimensions
    assert_equal "http://localhost:9000/v1", configuration.embedding_configuration.api_base_url
    assert_equal "test-key", configuration.embedding_configuration.api_key
    assert_equal 0.4, configuration.neighbor_threshold
  end

  test "validates top-k, metric, and metric-specific thresholds" do
    [
      { top_k: 0 },
      { top_k: 101 },
      { metric: "unsupported" },
      { threshold: 1.1 },
      { metric: "euclidean", threshold: -0.1 },
      { threshold: Float::INFINITY }
    ].each do |options|
      assert_raises(Retrieval::SearchConfiguration::ConfigurationError) do
        Retrieval::SearchConfiguration.new(**options)
      end
    end
  end
end
