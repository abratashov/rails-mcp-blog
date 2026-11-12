require "uri"

module Embeddings
  class Configuration
    DEFAULTS = {
      provider: "openai_compatible",
      api_base_url: "https://api.openai.com/v1",
      model: "text-embedding-3-small",
      dimensions: 1_536,
      configuration_version: "1",
      batch_size: 100,
      max_input_characters: 12_000,
      open_timeout: 5,
      read_timeout: 30,
      write_timeout: 30,
      retry_count: 3
    }.freeze

    attr_reader(*DEFAULTS.keys, :api_key, :send_dimensions)

    def initialize(values = ENV)
      @provider = values.fetch("EMBEDDING_PROVIDER", DEFAULTS[:provider]).to_s
      @api_base_url = values.fetch("EMBEDDING_API_BASE_URL", DEFAULTS[:api_base_url]).to_s
      @api_key = values["EMBEDDING_API_KEY"].presence
      @model = values.fetch("EMBEDDING_MODEL", DEFAULTS[:model]).to_s
      @dimensions = integer_value(values, "EMBEDDING_DIMENSIONS", DEFAULTS[:dimensions])
      @configuration_version = values.fetch(
        "EMBEDDING_CONFIGURATION_VERSION", DEFAULTS[:configuration_version]
      ).to_s
      @batch_size = integer_value(values, "EMBEDDING_BATCH_SIZE", DEFAULTS[:batch_size])
      @max_input_characters = integer_value(
        values, "EMBEDDING_MAX_INPUT_CHARACTERS", DEFAULTS[:max_input_characters]
      )
      @open_timeout = integer_value(values, "EMBEDDING_OPEN_TIMEOUT", DEFAULTS[:open_timeout])
      @read_timeout = integer_value(values, "EMBEDDING_READ_TIMEOUT", DEFAULTS[:read_timeout])
      @write_timeout = integer_value(values, "EMBEDDING_WRITE_TIMEOUT", DEFAULTS[:write_timeout])
      @retry_count = integer_value(values, "EMBEDDING_RETRY_COUNT", DEFAULTS[:retry_count])
      @send_dimensions = boolean_value(values, "EMBEDDING_SEND_DIMENSIONS", true)

      validate!
    end

    def validate_provider!
      raise ConfigurationError, "EMBEDDING_API_KEY must be configured" if api_key.blank?
    end

    def identity
      {
        provider: provider,
        model: model,
        dimensions: dimensions,
        configuration_version: configuration_version
      }
    end

    private

    def integer_value(values, key, default)
      value = Integer(values.fetch(key, default.to_s))
      value
    rescue ArgumentError, TypeError
      raise ConfigurationError, "#{key} must be an integer"
    end

    def boolean_value(values, key, default)
      value = values.fetch(key, default.to_s).to_s
      return true if value.casecmp("true").zero?
      return false if value.casecmp("false").zero?

      raise ConfigurationError, "#{key} must be true or false"
    end

    def validate!
      raise ConfigurationError, "EMBEDDING_PROVIDER must be openai_compatible" unless provider == "openai_compatible"
      unless valid_api_base_url?
        raise ConfigurationError, "EMBEDDING_API_BASE_URL must be an HTTP(S) URL without credentials"
      end
      raise ConfigurationError, "EMBEDDING_MODEL must not be blank" if model.blank?
      raise ConfigurationError, "EMBEDDING_CONFIGURATION_VERSION must not be blank" if configuration_version.blank?
      unless dimensions.between?(1, 16_000)
        raise ConfigurationError, "EMBEDDING_DIMENSIONS must be between 1 and 16000"
      end
      raise ConfigurationError, "EMBEDDING_BATCH_SIZE must be positive" unless batch_size.positive?
      raise ConfigurationError, "EMBEDDING_MAX_INPUT_CHARACTERS must be positive" unless max_input_characters.positive?
      raise ConfigurationError, "Embedding timeouts must be positive" unless [ open_timeout, read_timeout, write_timeout ].all?(&:positive?)
      raise ConfigurationError, "EMBEDDING_RETRY_COUNT must not be negative" if retry_count.negative?
    end

    def valid_api_base_url?
      uri = URI.parse(api_base_url)
      uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
    rescue URI::InvalidURIError
      false
    end

    class ConfigurationError < StandardError; end
  end
end
