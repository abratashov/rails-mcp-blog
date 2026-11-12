require "test_helper"

class Retrieval::QueryEmbedderTest < ActiveSupport::TestCase
  setup do
    @configuration = Embeddings::Configuration.new(
      "EMBEDDING_MODEL" => "multilingual-test-model",
      "EMBEDDING_DIMENSIONS" => "3"
    )
    @provider = FakeProvider.new([ [ 0.1, 0.2, 0.3 ] ])
  end

  test "embeds trimmed multilingual query text with the configured model" do
    vector = Retrieval::QueryEmbedder.new(configuration: @configuration, provider: @provider)
      .call("  Що таке семантичний пошук?  ")

    assert_equal [ 0.1, 0.2, 0.3 ], vector
    assert_equal [ [ "Що таке семантичний пошук?" ] ], @provider.calls
  end

  test "rejects empty and overlong queries without calling the provider" do
    embedder = Retrieval::QueryEmbedder.new(configuration: @configuration, provider: @provider)

    assert_raises(ArgumentError) { embedder.call(" \n") }

    limited_configuration = Embeddings::Configuration.new(
      "EMBEDDING_DIMENSIONS" => "3",
      "EMBEDDING_MAX_INPUT_CHARACTERS" => "4"
    )
    limited_embedder = Retrieval::QueryEmbedder.new(
      configuration: limited_configuration,
      provider: @provider
    )
    assert_raises(ArgumentError) { limited_embedder.call("a query") }
    assert_empty @provider.calls
  end

  test "rejects malformed or wrong-dimension query vectors" do
    [ [], [ [ 1.0 ] ], [ [ 1.0, Float::INFINITY, 3.0 ] ], [ "invalid" ] ].each do |response|
      provider = FakeProvider.new(response)
      embedder = Retrieval::QueryEmbedder.new(configuration: @configuration, provider: provider)

      assert_raises(Embeddings::Provider::Error) { embedder.call("query") }
    end
  end

  test "propagates embedding provider errors" do
    provider = FakeProvider.new([])
    provider.error = Embeddings::Provider::Error.new("provider unavailable")

    error = assert_raises(Embeddings::Provider::Error) do
      Retrieval::QueryEmbedder.new(configuration: @configuration, provider: provider).call("query")
    end

    assert_equal "provider unavailable", error.message
  end

  class FakeProvider
    attr_reader :calls
    attr_accessor :error

    def initialize(response)
      @response = response
      @calls = []
    end

    def embed(texts)
      @calls << texts
      raise error if error

      @response
    end
  end
end
