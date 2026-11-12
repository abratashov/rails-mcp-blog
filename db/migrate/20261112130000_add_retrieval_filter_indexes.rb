class AddRetrievalFilterIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :document_chunk_embeddings,
      [ :provider, :model, :dimensions, :configuration_version, :status ],
      name: "index_embeddings_on_retrieval_identity"
    add_index :document_chunks, :metadata, using: :gin
  end
end
