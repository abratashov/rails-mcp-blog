class CreateDocumentChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :document_chunks do |t|
      t.references :document, null: false, foreign_key: { on_delete: :cascade }
      t.text :content, null: false
      t.integer :position, null: false
      t.integer :page_start
      t.integer :page_end
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :document_chunks, [ :document_id, :position ], unique: true
  end
end
