module Rag
  module Strategies
    class ComparativeSearch
      SearchResult = Struct.new(:chunks, :queries, keyword_init: true)

      DEFAULT_TOP_K = 3

      def initialize(
        fallback:,
        query_builder: Rag::Comparative::QueryBuilder.new,
        result_merger: Rag::Comparative::ResultMerger.new,
        top_k: ENV.fetch("RAG_COMPARATIVE_TOP_K", DEFAULT_TOP_K)
      )
        @fallback = fallback
        @query_builder = query_builder
        @result_merger = result_merger
        @top_k = Integer(top_k)
        unless @top_k.between?(1, Retrieval::SearchConfiguration::MAX_TOP_K)
          raise ArgumentError, "Comparative Top-K must be between 1 and #{Retrieval::SearchConfiguration::MAX_TOP_K}"
        end
      end

      def call(question, user:, document_id: nil, metadata: nil, top_k: nil)
        queries = @query_builder.call(question)
        query_results = queries.map do |query|
          {
            query: query,
            results: @fallback.call(
              query.text,
              user: user,
              document_id: document_id,
              metadata: metadata,
              top_k: @top_k
            )
          }
        end
        chunks = @result_merger.call(query_results)
        log_retrieval(queries, chunks)

        SearchResult.new(chunks: chunks, queries: queries.map(&:to_h))
      end

      private

      def log_retrieval(queries, chunks)
        Rails.logger.info(
          "RAG comparative retrieval: queries=#{queries.map(&:text).inspect} " \
          "selected_chunks=#{chunks.map { |chunk| [ chunk[:document_id], chunk[:position] ] }.inspect}"
        )
      end
    end
  end
end
