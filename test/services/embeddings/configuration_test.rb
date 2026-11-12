require "test_helper"

class Embeddings::ConfigurationTest < ActiveSupport::TestCase
  test "uses an independent multilingual embedding configuration" do
    configuration = Embeddings::Configuration.new({})

    assert_equal "openai_compatible", configuration.provider
    assert_equal "text-embedding-3-small", configuration.model
    assert_equal 1_536, configuration.dimensions
    assert_equal "1", configuration.configuration_version
    assert_equal 100, configuration.batch_size
  end

  test "reads embedding settings without relying on the LLM provider" do
    configuration = Embeddings::Configuration.new(
      "LLM_PROVIDER" => "ollama",
      "EMBEDDING_PROVIDER" => "openai_compatible",
      "EMBEDDING_API_BASE_URL" => "http://localhost:9000/v1",
      "EMBEDDING_API_KEY" => "embedding-secret",
      "EMBEDDING_MODEL" => "custom-model",
      "EMBEDDING_DIMENSIONS" => "384",
      "EMBEDDING_SEND_DIMENSIONS" => "false",
      "EMBEDDING_CONFIGURATION_VERSION" => "2",
      "EMBEDDING_BATCH_SIZE" => "16"
    )

    assert_equal "openai_compatible", configuration.provider
    assert_equal "http://localhost:9000/v1", configuration.api_base_url
    assert_equal "embedding-secret", configuration.api_key
    assert_equal "custom-model", configuration.model
    assert_equal 384, configuration.dimensions
    assert_not configuration.send_dimensions
    assert_equal "2", configuration.configuration_version
    assert_equal 16, configuration.batch_size
  end

  test "rejects invalid dimensions" do
    error = assert_raises(Embeddings::Configuration::ConfigurationError) do
      Embeddings::Configuration.new("EMBEDDING_DIMENSIONS" => "zero")
    end

    assert_equal "EMBEDDING_DIMENSIONS must be an integer", error.message
  end

  test "requires a key before contacting the provider" do
    configuration = Embeddings::Configuration.new({})

    error = assert_raises(Embeddings::Configuration::ConfigurationError) do
      configuration.validate_provider!
    end

    assert_equal "EMBEDDING_API_KEY must be configured", error.message
  end

  test "rejects invalid provider, URL, and model metadata" do
    invalid_settings = [
      [ "EMBEDDING_PROVIDER", "openai" ],
      [ "EMBEDDING_API_BASE_URL", "not a URL" ],
      [ "EMBEDDING_API_BASE_URL", "http://user:password@localhost/v1" ],
      [ "EMBEDDING_API_BASE_URL", "http://[" ],
      [ "EMBEDDING_MODEL", " " ],
      [ "EMBEDDING_CONFIGURATION_VERSION", "" ]
    ]

    invalid_settings.each do |key, value|
      assert_raises(Embeddings::Configuration::ConfigurationError) do
        Embeddings::Configuration.new(key => value)
      end
    end
  end

  test "validates limits, timeouts, retries, and optional dimensions parameter" do
    invalid_settings = [
      [ "EMBEDDING_DIMENSIONS", "16001" ],
      [ "EMBEDDING_BATCH_SIZE", "0" ],
      [ "EMBEDDING_MAX_INPUT_CHARACTERS", "0" ],
      [ "EMBEDDING_OPEN_TIMEOUT", "0" ],
      [ "EMBEDDING_READ_TIMEOUT", "0" ],
      [ "EMBEDDING_WRITE_TIMEOUT", "0" ],
      [ "EMBEDDING_RETRY_COUNT", "-1" ],
      [ "EMBEDDING_SEND_DIMENSIONS", "sometimes" ]
    ]

    invalid_settings.each do |key, value|
      assert_raises(Embeddings::Configuration::ConfigurationError) do
        Embeddings::Configuration.new(key => value)
      end
    end

    assert_not Embeddings::Configuration.new("EMBEDDING_SEND_DIMENSIONS" => "false").send_dimensions
  end
end
