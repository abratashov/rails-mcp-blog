ActiveAdmin.register DocumentChunk do
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
  end
end
