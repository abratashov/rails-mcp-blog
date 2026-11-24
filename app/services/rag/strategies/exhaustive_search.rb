module Rag
  module Strategies
    class ExhaustiveSearch
      SearchResult = Struct.new(:chunks, :incomplete_documents, :document_count, keyword_init: true)

      def call(_question, user:, document_id: nil, metadata: nil, top_k: nil)
        raise ArgumentError, "A user is required to search documents" unless user
        unless metadata.nil? || metadata.is_a?(Hash)
          raise ArgumentError, "Chunk metadata filter must be a hash"
        end

        documents = Document.where(user_id: user.id)
        documents = documents.where(id: document_id) if document_id.present?

        completed_documents = documents.where(status: "completed")
        incomplete_documents = documents
          .where.not(status: "completed")
          .order(:id)
          .map do |document|
            {
              document_id: document.id,
              filename: document.filename,
              status: document.status,
              error: document.processing_error
            }
          end

        unless incomplete_documents.empty?
          Rails.logger.warn(
            "RAG exhaustive retrieval skipped incomplete documents: " \
            "#{incomplete_documents.map { |document| [ document[:document_id], document[:status] ] }.inspect}"
          )
        end

        chunks = chunk_scope(completed_documents, metadata)
          .order(:document_id, :position)
          .preload(:document)
          .map { |chunk| build_result(chunk) }

        SearchResult.new(
          chunks: chunks,
          incomplete_documents: incomplete_documents,
          document_count: documents.count
        )
      end

      private

      def chunk_scope(documents, metadata)
        scope = DocumentChunk.joins(:document).where(document_id: documents.select(:id))
        scope = scope.where("document_chunks.metadata @> ?::jsonb", metadata.to_json) if metadata.present?
        scope
      end

      def build_result(chunk)
        Rag::Retrieval::Result.new(
          id: chunk.id,
          content: chunk.content,
          document_id: chunk.document_id,
          filename: chunk.document.filename,
          page_start: chunk.page_start,
          page_end: chunk.page_end,
          position: chunk.position,
          score: nil,
          distance: nil,
          metadata: chunk.metadata
        )
      end
    end
  end
end
