ActiveAdmin.register DocumentChunkEmbedding do
  menu parent: "Documents", priority: 3

  actions :index, :show

  filter :document_chunk
  filter :provider
  filter :model
  filter :dimensions
  filter :configuration_version
  filter :status

  index do
    id_column
    column(:document_chunk) do |embedding|
      link_to "#{embedding.document_chunk.document.filename} · chunk #{embedding.document_chunk.position}",
        admin_document_chunk_path(embedding.document_chunk)
    end
    column :provider
    column :model
    column :dimensions
    column :configuration_version
    column :input_checksum
    column :status
    column :error_message
    actions
  end

  show do
    attributes_table do
      row(:document_chunk) do |embedding|
        link_to "#{embedding.document_chunk.document.filename} · chunk #{embedding.document_chunk.position}",
          admin_document_chunk_path(embedding.document_chunk)
      end
      row :provider
      row :model
      row :dimensions
      row :configuration_version
      row :input_checksum
      row :status
      # row(:embedding) { |record| record.embedding&.first(20)&.join(", ") }
      row(:embedding) { |record| record.embedding }
      row :error_message
      row :created_at
      row :updated_at
    end
  end

  controller do
    def scoped_collection
      columns = [
        :id,
        :document_chunk_id,
        :provider,
        :model,
        :dimensions,
        :configuration_version,
        :input_checksum,
        :status,
        :error_message,
        :created_at,
        :updated_at
      ]
      columns << :embedding if action_name == "show"

      super.select(*columns)
    end
  end
end
