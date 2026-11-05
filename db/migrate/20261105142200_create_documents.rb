class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :file_size, null: false
      t.string :checksum, null: false
      t.string :status, null: false, default: "pending"
      t.text :processing_error

      t.timestamps
    end

    add_index :documents, [ :user_id, :checksum ], unique: true
  end
end
