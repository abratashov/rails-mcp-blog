ActiveAdmin.register Document do
  menu parent: "Documents", priority: 1

  permit_params :user_id, :file

  actions :index, :show, :new, :create, :destroy
  config.remove_action_item :destroy
  filter :filename
  filter :content_type
  filter :status
  filter :user
  filter :created_at

  index do
    selectable_column
    id_column
    column :filename
    column("Format") { |document| File.extname(document.filename).delete_prefix(".").upcase }
    column("Size") { |document| number_to_human_size(document.file_size) }
    column :user
    column :status
    column("Uploaded at", &:created_at)
    actions
  end

  show do
    attributes_table do
      row :filename
      row :content_type
      row(:file_size) { |document| number_to_human_size(document.file_size) }
      row :checksum
      row :status
      row :processing_error
      row :user
      row :created_at
      row(:file) do |document|
        link_to document.filename, url_for(document.file) if document.file.attached?
      end
    end

    panel "Extracted chunks" do
      table_for resource.document_chunks do
        column :position
        column :page_start
        column :page_end
        column(:content) { |chunk| simple_format(chunk.content) }
      end
    end

    panel "Embedding progress" do
      configuration = Embeddings::Configuration.new
      embeddings = resource.document_chunk_embeddings.where(configuration.identity)
      completed_count = embeddings.where(status: "completed").count
      status_by_chunk = embeddings.pluck(:document_chunk_id, :status, :error_message).to_h do |chunk_id, status, error_message|
        [ chunk_id, { status: status, error_message: error_message } ]
      end
      para "#{completed_count} of #{resource.document_chunks.count} chunks have embeddings for #{configuration.provider} / #{configuration.model} (#{configuration.dimensions} dimensions, configuration #{configuration.configuration_version})."

      table_for resource.document_chunks do
        column :position
        column("Status") do |chunk|
          status_by_chunk.dig(chunk.id, :status) || "not generated"
        end
        column("Error") do |chunk|
          status_by_chunk.dig(chunk.id, :error_message)
        end
      end
    end
  end

  form do |form|
    form.inputs do
      form.input :user
      form.input :file, as: :file
    end
    form.actions
  end

  controller do
    before_build do |document|
      document.user = current_user
    end
  end

  action_item :destroy, only: :show do
    button_to "Delete document", resource_path(resource), method: :delete,
      form: { data: { turbo_confirm: "Are you sure you want to delete this document?" } }
  end


  action_item :retry_processing, only: :show, if: proc { resource.status == "failed" } do
    button_to "Retry processing", retry_processing_admin_document_path(resource), method: :post
  end

  action_item :retry_embeddings, only: :show, if: proc {
    configuration = Embeddings::Configuration.new
    resource.document_chunk_embeddings.where(configuration.identity.merge(status: "failed")).exists?
  } do
    button_to "Retry failed embeddings", retry_embeddings_admin_document_path(resource), method: :post
  end

  member_action :retry_processing, method: :post do
    resource.update!(status: "pending", processing_error: nil)
    ProcessDocumentJob.perform_later(resource)
    redirect_to resource_path, notice: "Document processing has been queued."
  end

  member_action :retry_embeddings, method: :post do
    configuration = Embeddings::Configuration.new
    chunk_ids = resource.document_chunk_embeddings
      .where(configuration.identity.merge(status: "failed"))
      .pluck(:document_chunk_id)
    GenerateDocumentEmbeddingsJob.perform_later(resource.id, chunk_ids: chunk_ids)
    redirect_to resource_path, notice: "Failed document embeddings have been queued."
  end
end
