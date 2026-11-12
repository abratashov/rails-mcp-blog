ActiveAdmin.register DocumentChunk do
  menu parent: "Documents", priority: 2

  actions :index, :show

  filter :document
  filter :position
  filter :page_start
  filter :page_end

  index do
    id_column
    column(:document) { |chunk| link_to chunk.document.filename, admin_document_path(chunk.document) }
    column :position
    column :page_start
    column :page_end
    column :content
    column("Embeddings") do |chunk|
      chunk.document_chunk_embeddings.pluck(:provider, :model, :status, :dimensions).map do |provider, model, status, dimensions|
        "#{provider} / #{model}: #{status} (#{dimensions})"
      end.join(", ")
    end
    actions
  end

  show do
    attributes_table do
      row(:document) { |chunk| link_to chunk.document.filename, admin_document_path(chunk.document) }
      row :position
      row :page_start
      row :page_end
      row :content
      row :metadata
    end

    panel "Embeddings" do
      table_for resource.document_chunk_embeddings do
        column :provider
        column :model
        column :dimensions
        column :configuration_version
        column :status
        column :error_message
        column("Embedding") do |embedding|
          link_to "View", admin_document_chunk_embedding_path(embedding)
        end
      end
    end
  end

  action_item :retry_embedding, only: :show do
    button_to "Retry embedding", retry_embedding_admin_document_chunk_path(resource), method: :post
  end

  member_action :retry_embedding, method: :post do
    GenerateDocumentEmbeddingsJob.perform_later(resource.document_id, chunk_ids: [ resource.id ])
    redirect_to resource_path, notice: "Chunk embedding generation has been queued."
  end
end
