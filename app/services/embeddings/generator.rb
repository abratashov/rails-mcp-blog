require "digest"

module Embeddings
  class Generator
    PROCESSING_TIMEOUT = 30.minutes

    def initialize(configuration: Configuration.new, provider: nil)
      @configuration = configuration
      @provider = provider || OpenAICompatibleProvider.new(configuration: configuration)
    end

    def call(chunks)
      chunks.in_batches(of: @configuration.batch_size) do |batch|
        generate_batch(batch.to_a)
      end
    end

    private

    def generate_batch(chunks)
      claimed = chunks.filter_map { |chunk| claim(chunk) }
      return if claimed.empty?

      eligible, invalid = claimed.partition do |_record, content|
        content.present? && content.length <= @configuration.max_input_characters
      end
      invalid.each do |embedding_record, content, input_checksum|
        reason = content.blank? ? "Chunk content is empty." : "Chunk content exceeds the #{@configuration.max_input_characters}-character embedding limit."
        mark_failed(embedding_record, input_checksum, Provider::Error.new(reason))
      end
      return if eligible.empty?

      vectors = @provider.embed(eligible.map { |_, content, _| content })
      unless vectors.is_a?(Array) && vectors.length == eligible.length
        raise Provider::Error, "Embedding provider returned an unexpected number of vectors"
      end

      eligible.zip(vectors).each do |(embedding_record, _content, input_checksum), vector|
        persist_vector(embedding_record, input_checksum, vector)
      rescue Provider::Error, Configuration::ConfigurationError => error
        mark_failed(embedding_record, input_checksum, error)
      end
    rescue Provider::Error, Configuration::ConfigurationError => error
      eligible.each do |embedding_record, _content, input_checksum|
        mark_failed(embedding_record, input_checksum, error)
      end
    end

    def claim(chunk)
      input_checksum = Digest::SHA256.hexdigest(chunk.content)
      embedding = find_or_create_embedding(chunk)
      claimed = false

      embedding.with_lock do
        same_content = embedding.input_checksum == input_checksum
        return if embedding.completed? && same_content
        return if embedding.status == "processing" && embedding.updated_at > PROCESSING_TIMEOUT.ago

        embedding.update!(
          status: "processing",
          input_checksum: input_checksum,
          embedding: nil,
          error_message: nil
        )
        claimed = true
      end

      [ embedding, chunk.content, input_checksum ] if claimed
    end

    def find_or_create_embedding(chunk)
      chunk.document_chunk_embeddings.find_or_create_by!(@configuration.identity) do |record|
        record.input_checksum = Digest::SHA256.hexdigest(chunk.content)
        record.status = "pending"
      end
    rescue ActiveRecord::RecordNotUnique
      chunk.document_chunk_embeddings.find_by!(@configuration.identity)
    end

    def persist_vector(embedding_record, input_checksum, vector)
      unless vector.is_a?(Array) && vector.length == @configuration.dimensions &&
          vector.all? { |value| value.is_a?(Numeric) && value.to_f.finite? }
        raise Provider::Error, "Embedding vector must contain #{@configuration.dimensions} finite numeric values"
      end

      embedding_record.with_lock do
        return unless embedding_record.status == "processing" &&
          embedding_record.input_checksum == input_checksum

        current_checksum = Digest::SHA256.hexdigest(embedding_record.document_chunk.reload.content)
        if current_checksum != input_checksum
          embedding_record.update!(
            status: "pending",
            embedding: nil,
            error_message: "Chunk content changed while embedding was generated."
          )
          return
        end

        embedding_record.update!(
          embedding: vector,
          dimensions: @configuration.dimensions,
          status: "completed",
          error_message: nil
        )
      end
    end

    def mark_failed(embedding_record, input_checksum, error)
      embedding_record.with_lock do
        return unless embedding_record.status == "processing" &&
          embedding_record.input_checksum == input_checksum

        embedding_record.update!(
          embedding: nil,
          status: "failed",
          error_message: "#{error.class}: #{error.message}".truncate(10_000)
        )
      end
    end
  end
end
