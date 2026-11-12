class CreateDocumentChunkEmbeddings < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :document_chunk_embeddings do |t|
      t.references :document_chunk, null: false, foreign_key: { on_delete: :cascade }
      t.column :embedding, "vector"
      t.string :provider, null: false, limit: 64
      t.string :model, null: false
      t.integer :dimensions, null: false
      t.string :configuration_version, null: false, limit: 64
      t.string :input_checksum, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message

      t.timestamps
    end

    add_index :document_chunk_embeddings,
      [ :document_chunk_id, :provider, :model, :dimensions, :configuration_version ],
      unique: true,
      name: "index_document_chunk_embeddings_on_identity"
    add_index :document_chunk_embeddings, :status
    add_check_constraint :document_chunk_embeddings, "dimensions BETWEEN 1 AND 16000",
      name: "document_chunk_embeddings_dimensions_valid"
    add_check_constraint :document_chunk_embeddings,
      "status IN ('pending', 'processing', 'completed', 'failed')",
      name: "document_chunk_embeddings_valid_status"
    add_check_constraint :document_chunk_embeddings,
      "(status = 'completed' AND embedding IS NOT NULL) OR (status <> 'completed' AND embedding IS NULL)",
      name: "document_chunk_embeddings_status_matches_embedding"
    add_check_constraint :document_chunk_embeddings,
      "embedding IS NULL OR vector_dims(embedding) = dimensions",
      name: "document_chunk_embeddings_vector_dimensions_match"
  end
end
