class CreateRagConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :rag_conversations do |t|
      t.references :user, foreign_key: true, null: true
      t.string :title
      t.jsonb :messages, null: false, default: []
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end
