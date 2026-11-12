module Retrieval
  class SearchConfiguration
    METRICS = %w[cosine inner_product euclidean].freeze
    DEFAULT_TOP_K = 5
    MAX_TOP_K = 100

    attr_reader :top_k, :threshold, :metric, :embedding_configuration

    def initialize(
      embedding_configuration: Embeddings::Configuration.new,
      embedding_identity: nil,
      top_k: DEFAULT_TOP_K,
      threshold: nil,
      metric: "cosine"
    )
      @top_k = integer_value(top_k, "Top-K")
      @threshold = threshold_value(threshold)
      @metric = metric.to_s
      raise ConfigurationError, "Metric must be one of #{METRICS.join(', ')}" unless METRICS.include?(@metric)
      raise ConfigurationError, "Top-K must be between 1 and #{MAX_TOP_K}" unless @top_k.between?(1, MAX_TOP_K)

      @embedding_configuration = configuration_for(embedding_configuration, embedding_identity)
      validate_threshold!
    end

    def embedding_identity
      @embedding_configuration.identity
    end

    def neighbor_threshold
      return if threshold.nil?

      metric == "cosine" ? 1.0 - threshold : threshold
    end

    class ConfigurationError < StandardError; end

    private

    def integer_value(value, name)
      Integer(value)
    rescue ArgumentError, TypeError
      raise ConfigurationError, "#{name} must be an integer"
    end

    def threshold_value(value)
      return if value.nil? || value.to_s.strip.empty?

      Float(value).tap do |number|
        raise ConfigurationError, "Threshold must be finite" unless number.finite?
      end
    rescue ArgumentError, TypeError
      raise ConfigurationError, "Threshold must be a number"
    end

    def configuration_for(base, identity)
      return base if identity.nil?

      identity = identity.to_h.transform_keys(&:to_sym)
      required = %i[provider model dimensions configuration_version]
      raise ConfigurationError, "Embedding identity is incomplete" unless required.all? { |key| identity.key?(key) }

      values = {
        "EMBEDDING_API_BASE_URL" => base.api_base_url,
        "EMBEDDING_API_KEY" => base.api_key,
        "EMBEDDING_PROVIDER" => identity.fetch(:provider).to_s,
        "EMBEDDING_MODEL" => identity.fetch(:model).to_s,
        "EMBEDDING_DIMENSIONS" => identity.fetch(:dimensions).to_s,
        "EMBEDDING_CONFIGURATION_VERSION" => identity.fetch(:configuration_version).to_s,
        "EMBEDDING_SEND_DIMENSIONS" => base.send_dimensions.to_s,
        "EMBEDDING_MAX_INPUT_CHARACTERS" => base.max_input_characters.to_s,
        "EMBEDDING_OPEN_TIMEOUT" => base.open_timeout.to_s,
        "EMBEDDING_READ_TIMEOUT" => base.read_timeout.to_s,
        "EMBEDDING_WRITE_TIMEOUT" => base.write_timeout.to_s,
        "EMBEDDING_RETRY_COUNT" => base.retry_count.to_s
      }

      Embeddings::Configuration.new(values)
    end

    def validate_threshold!
      return if threshold.nil?

      case metric
      when "cosine"
        unless threshold.between?(-1.0, 1.0)
          raise ConfigurationError, "Cosine similarity threshold must be between -1 and 1"
        end
      when "euclidean"
        raise ConfigurationError, "Euclidean distance threshold must not be negative" if threshold.negative?
      end
    end
  end
end
