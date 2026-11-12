class GenerateDocumentEmbeddingsJob < ApplicationJob
  queue_as :default

  def perform(document_id, chunk_ids: nil)
    chunks = DocumentChunk.where(document_id: document_id)
    chunks = chunks.where(id: chunk_ids) if chunk_ids.present?

    Embeddings::Generator.new.call(chunks.order(:position))
  end
end
