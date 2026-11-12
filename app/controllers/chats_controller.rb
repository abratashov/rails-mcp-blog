class ChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :load_documents
  before_action :load_conversation, only: %i[show create_message]

  def index
    @conversations = current_user_conversations
  end

  def show
    @conversations = current_user_conversations
    @selected_document_id = @conversation.metadata_hash["document_id"]
  end

  def create
    return render_new_chat unless valid_question?

    document = selected_document
    @conversation = current_user.rag_conversations.create!(
      title: params[:message].to_s.squish.truncate(80),
      messages: [],
      metadata: { "document_id" => document&.id }
    )
    submit_question(document)

    redirect_to chat_conversation_path(@conversation), status: :see_other
  rescue ActiveRecord::RecordNotFound
    render_new_chat("The selected document is not available.")
  end

  def create_message
    @conversations = current_user_conversations
    @selected_document_id = params[:document_id].presence
    return render :show, status: :unprocessable_content unless valid_question?

    document = selected_document
    submit_question(document)
    @selected_document_id = document&.id

    redirect_to chat_conversation_path(@conversation), status: :see_other
  rescue ActiveRecord::RecordNotFound
    @error = "The selected document is not available."
    render :show, status: :unprocessable_content
  end

  private

  def load_documents
    @documents = current_user.documents.order(:filename)
  end

  def load_conversation
    @conversation = current_user_conversations.find(params[:id])
  end

  def current_user_conversations
    current_user.rag_conversations.order(updated_at: :desc)
  end

  def valid_question?
    if params[:message].to_s.strip.blank?
      @error = "Enter a question to send."
      false
    else
      true
    end
  end

  def render_new_chat(error = nil)
    @error = error if error.present?
    @conversations = current_user_conversations
    render :index, status: :unprocessable_content
  end

  def selected_document
    return if params[:document_id].blank?

    current_user.documents.find(params[:document_id])
  end

  def submit_question(document)
    question = params[:message].to_s.strip
    history = @conversation.messages_for_display.map do |message|
      { "role" => message.role, "content" => message.content }
    end
    result = rag_assistant.call(
      question,
      user: current_user,
      document_id: document&.id,
      conversation: history
    )

    @conversation.update!(metadata: @conversation.metadata_hash.merge("document_id" => document&.id))
    @conversation.append_message(
      role: "user",
      content: question,
      metadata: { "document_id" => document&.id }
    )
    @conversation.append_message(
      role: "assistant",
      content: result.answer,
      metadata: {
        "citations" => result.citations || [],
        "retrieved_chunks" => serialize_chunks(result.retrieved_chunks),
        "context" => serialize_context(result.context),
        "provider" => result.provider,
        "model" => result.model,
        "grounded" => result.grounded,
        "error" => result.error
      }
    )
    @error = result.error
  end

  def serialize_chunks(chunks)
    Array(chunks).map do |chunk|
      {
        "document_id" => chunk.document_id,
        "filename" => chunk.filename,
        "page_start" => chunk.page_start,
        "page_end" => chunk.page_end,
        "position" => chunk.position,
        "score" => chunk.score,
        "distance" => chunk.distance,
        "provider" => chunk.provider,
        "model" => chunk.model,
        "dimensions" => chunk.dimensions,
        "content" => chunk.content,
        "metadata" => chunk.metadata
      }
    end
  end

  def serialize_context(context)
    Array(context).map do |item|
      {
        "source_id" => item.source_id,
        "filename" => item.filename,
        "page_start" => item.page_start,
        "page_end" => item.page_end,
        "score" => item.score,
        "content" => item.content,
        "token_count" => item.token_count
      }
    end
  end

  def rag_assistant
    Rag::Assistant.new
  end
end
