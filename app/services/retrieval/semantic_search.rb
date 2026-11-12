module Retrieval
  class SemanticSearch
    def initialize(configuration: SearchConfiguration.new, query_embedder: nil)
      @configuration = configuration
      @query_embedder = query_embedder || QueryEmbedder.new(
        configuration: configuration.embedding_configuration
      )
    end

    def call(query, user:, document_id: nil, metadata: nil)
      raise ArgumentError, "A user is required to search documents" unless user
      unless metadata.nil? || metadata.is_a?(Hash)
        raise ArgumentError, "Chunk metadata filter must be a hash"
      end

      vector = @query_embedder.call(query)
      identity = @configuration.embedding_identity
      scope = DocumentChunkEmbedding
        .joins(document_chunk: :document)
        .where(documents: { user_id: user.id })
        .where(
          provider: identity.fetch(:provider),
          model: identity.fetch(:model),
          dimensions: identity.fetch(:dimensions),
          configuration_version: identity.fetch(:configuration_version),
          status: "completed"
        )
        .where("vector_dims(document_chunk_embeddings.embedding) = ?", identity.fetch(:dimensions))

      scope = scope.where(document_chunks: { document_id: document_id }) if document_id.present?
      scope = scope.where("document_chunks.metadata @> ?::jsonb", metadata.to_json) if metadata.present?

      scope
        .nearest_neighbors(
          :embedding,
          vector,
          distance: @configuration.metric,
          threshold: @configuration.neighbor_threshold
        )
        .limit(@configuration.top_k)
        .preload(document_chunk: :document)
        .map { |embedding| build_result(embedding, identity) }
    end

    private

    def build_result(embedding, identity)
      chunk = embedding.document_chunk
      document = chunk.document
      neighbor_value = embedding.neighbor_distance.to_f
      if @configuration.metric == "inner_product"
        score = neighbor_value
        distance = -score
      else
        distance = neighbor_value
        score = @configuration.metric == "cosine" ? 1.0 - distance : -distance
      end

      Result.new(
        content: chunk.content,
        document_id: document.id,
        filename: document.filename,
        page_start: chunk.page_start,
        page_end: chunk.page_end,
        position: chunk.position,
        distance: distance,
        score: score,
        metric: @configuration.metric,
        provider: identity.fetch(:provider),
        model: identity.fetch(:model),
        dimensions: identity.fetch(:dimensions),
        configuration_version: identity.fetch(:configuration_version),
        metadata: chunk.metadata
      )
    end
  end
end
