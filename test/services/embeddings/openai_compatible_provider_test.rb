require "test_helper"

class Embeddings::OpenAICompatibleProviderTest < ActiveSupport::TestCase
  test "requires provider implementations to define embed" do
    assert_raises(NotImplementedError) { Embeddings::Provider.new.embed([ "text" ]) }
  end

  setup do
    @configuration = Embeddings::Configuration.new(
      "EMBEDDING_API_BASE_URL" => "https://embeddings.example/v1",
      "EMBEDDING_API_KEY" => "test-key",
      "EMBEDDING_MODEL" => "multilingual-test",
      "EMBEDDING_DIMENSIONS" => "3",
      "EMBEDDING_RETRY_COUNT" => "1"
    )
  end

  test "sends batches to the configured OpenAI-compatible endpoint and orders by index" do
    stub_request(:post, "https://embeddings.example/v1/embeddings")
      .with(
        headers: { "Authorization" => "Bearer test-key" },
        body: {
          input: [ "first text", "second text" ],
          model: "multilingual-test",
          dimensions: 3
        }
      )
      .to_return(
        status: 200,
        body: {
          data: [
            { index: 1, embedding: [ 4, 5, 6 ] },
            { index: 0, embedding: [ 1, 2, 3 ] }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: @configuration,
      sleeper: ->(_seconds) { nil }
    )

    assert_equal [ [ 1.0, 2.0, 3.0 ], [ 4.0, 5.0, 6.0 ] ],
      provider.embed([ "first text", "second text" ])
  end

  test "retries rate limits and temporary server failures" do
    request = stub_request(:post, "https://embeddings.example/v1/embeddings")
      .to_return(
        { status: 429, headers: { "Retry-After" => "0" }, body: "{}" },
        {
          status: 200,
          body: { data: [ { index: 0, embedding: [ 1, 2, 3 ] } ] }.to_json,
          headers: { "Content-Type" => "application/json" }
        }
      )
    delays = []
    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: @configuration,
      sleeper: ->(delay) { delays << delay }
    )

    assert_equal [ [ 1.0, 2.0, 3.0 ] ], provider.embed([ "text" ])
    assert_equal [ 0.0 ], delays
    assert_requested request, times: 2
  end

  test "rejects malformed, missing, and non-finite vectors" do
    malformed_bodies = [
      "{",
      { data: [ { index: 0, embedding: "not-an-array" } ] }.to_json,
      { data: [ { index: 1, embedding: [ 1, 2, 3 ] } ] }.to_json,
      { data: [ { index: 0, embedding: [ 1, "NaN", 3 ] } ] }.to_json
    ]

    malformed_bodies.each do |body|
      stub_request(:post, "https://embeddings.example/v1/embeddings")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
      provider = Embeddings::OpenAICompatibleProvider.new(
        configuration: @configuration,
        sleeper: ->(_seconds) { nil }
      )

      assert_raises(Embeddings::Provider::Error) { provider.embed([ "text" ]) }
    end
  end

  test "fails explicitly when the API key is missing" do
    configuration = Embeddings::Configuration.new({})
    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: configuration,
      sleeper: ->(_seconds) { nil }
    )

    assert_raises(Embeddings::Configuration::ConfigurationError) { provider.embed([ "text" ]) }
  end

  test "does not send dimensions when the configured API does not support them" do
    configuration = Embeddings::Configuration.new(
      "EMBEDDING_API_BASE_URL" => "https://embeddings.example/v1",
      "EMBEDDING_API_KEY" => "test-key",
      "EMBEDDING_MODEL" => "custom-model",
      "EMBEDDING_DIMENSIONS" => "3",
      "EMBEDDING_SEND_DIMENSIONS" => "false"
    )
    stub_request(:post, "https://embeddings.example/v1/embeddings")
      .with(body: { input: [ "text" ], model: "custom-model" })
      .to_return(
        status: 200,
        body: { data: [ { index: 0, embedding: [ 1, 2, 3 ] } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: configuration,
      sleeper: ->(_seconds) { nil }
    )

    assert_equal [ [ 1.0, 2.0, 3.0 ] ], provider.embed([ "text" ])
  end

  test "does not retry client errors and includes a safe provider message" do
    request = stub_request(:post, "https://embeddings.example/v1/embeddings")
      .to_return(status: 400, body: { error: { message: "Invalid model" } }.to_json)
    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: @configuration,
      sleeper: ->(_seconds) { flunk "Client errors must not be retried" }
    )

    error = assert_raises(Embeddings::Provider::Error) { provider.embed([ "text" ]) }

    assert_match "HTTP 400: Invalid model", error.message
    assert_requested request, times: 1
  end

  test "rejects empty requests without making an API call" do
    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: @configuration,
      sleeper: ->(_seconds) { nil }
    )

    assert_raises(Embeddings::Provider::Error) { provider.embed([]) }
    assert_not_requested :post, "https://embeddings.example/v1/embeddings"
  end

  test "retries timeouts and reports the final failure without exposing credentials" do
    request = stub_request(:post, "https://embeddings.example/v1/embeddings").to_timeout.then.to_timeout
    delays = []
    provider = Embeddings::OpenAICompatibleProvider.new(
      configuration: @configuration,
      sleeper: ->(delay) { delays << delay }
    )

    error = assert_raises(Embeddings::Provider::Error) { provider.embed([ "text" ]) }

    assert_match "Embedding API request failed", error.message
    assert_not_includes error.message, "test-key"
    assert_equal [ 0.5 ], delays
    assert_requested request, times: 2
  end
end
