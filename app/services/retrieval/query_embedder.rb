module Retrieval
  class QueryEmbedder
    def initialize(configuration: Embeddings::Configuration.new, provider: nil)
      @configuration = configuration
      @provider = provider || Embeddings::OpenAICompatibleProvider.new(configuration: configuration)
    end

    def call(query)
      text = query.to_s.strip
      raise ArgumentError, "Search query must not be blank" if text.blank?
      if text.length > @configuration.max_input_characters
        raise ArgumentError, "Search query exceeds the #{@configuration.max_input_characters}-character embedding limit"
      end

      vectors = @provider.embed([ text ])
      unless vectors.is_a?(Array) && vectors.length == 1
        raise Embeddings::Provider::Error, "Embedding provider returned an unexpected number of query vectors"
      end

      vector = vectors.first
      unless vector.is_a?(Array) && vector.length == @configuration.dimensions &&
          vector.all? { |value| value.is_a?(Numeric) && value.to_f.finite? }
        raise Embeddings::Provider::Error,
          "Query embedding must contain #{@configuration.dimensions} finite numeric values"
      end

      vector.map(&:to_f)
    end
  end
end
