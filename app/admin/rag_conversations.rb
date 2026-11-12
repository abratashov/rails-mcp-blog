ActiveAdmin.register RagConversation do
  menu parent: "Documents", priority: 5

  permit_params :title

  index do
    selectable_column
    id_column
    column :user
    column :title
    column :created_at
    column :updated_at
    actions
  end

  show do
    attributes_table do
      row :id
      row :user
      row :title
      row :created_at
      row :updated_at
      row :metadata
    end

    panel "Messages" do
      if resource.messages_for_display.empty?
        para "No messages in this conversation."
      else
        resource.messages_for_display.each do |message|
          role = message.role.to_s
          message_metadata = message.metadata.is_a?(Hash) ? message.metadata : {}
          citations = message_metadata["citations"] || message_metadata[:citations] || []

          div class: "rag-chat__message rag-chat__message--#{role == "user" ? "user" : "assistant"}" do
            h4(role == "user" ? "User" : "Assistant")
            div class: "rag-chat__message-content" do
              if role == "assistant"
                text_node prompt_markdown(message.content.to_s)
              else
                simple_format(message.content.to_s)
              end
            end

            if role == "assistant" && citations.any?
              div class: "rag-chat__sources" do
                h5 "Sources"
                ul do
                  citations.each do |citation|
                    label = citation["label"] || citation[:label]
                    filename = citation["filename"] || citation[:filename]
                    document_id = citation["document_id"] || citation[:document_id]
                    page_start = citation["page_start"] || citation[:page_start]
                    page_end = citation["page_end"] || citation[:page_end]
                    pages = [page_start, page_end].compact.uniq

                    li do
                      text_node "[#{label}] "
                      if document_id.present?
                        link_to filename, admin_document_path(document_id)
                      else
                        text_node filename.to_s
                      end
                      text_node " — page #{pages.join("-")}" if pages.any?
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  form do |form|
    form.inputs do
      form.input :title
    end
    form.actions
  end

  controller do
    before_build do |conversation|
      conversation.user = current_user
    end
  end
end
