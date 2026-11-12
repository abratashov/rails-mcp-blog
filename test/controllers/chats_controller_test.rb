require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "secure-password", password_confirmation: "secure-password")
    post user_session_path, params: {
      user: { email: @user.email, password: "secure-password" }
    }
  end

  test "requires a signed-in user" do
    delete destroy_user_session_path

    get chat_path

    assert_redirected_to new_user_session_path
  end

  test "creates a chat, invokes RAG for the current user, and renders citations" do
    assistant = StubAssistant.new
    with_assistant(assistant) do
      post chat_path, params: { message: "What does the report say?" }
    end

    conversation = RagConversation.order(:id).last
    assert_redirected_to chat_conversation_path(conversation)
    assert_equal @user, conversation.user
    assert_equal %w[user assistant], conversation.messages.map { |message| message["role"] }
    assert_equal "What does the report say?", assistant.question
    assert_equal @user, assistant.options[:user]

    get chat_conversation_path(conversation)
    assert_response :success
    assert_select "h1", text: conversation.title
    assert_select "h3", text: "Sources"
    assert_select "li", text: /report.txt/
  end

  test "renders assistant messages as sanitized Markdown" do
    conversation = @user.rag_conversations.create!(title: "Markdown", messages: [])
    conversation.append_message(role: "user", content: "Question")
    conversation.append_message(role: "assistant", content: "**Cat (кошка)** and <script>alert('unsafe')</script>")

    get chat_conversation_path(conversation)

    assert_response :success
    assert_select ".rag-chat__message--assistant strong", text: "Cat (кошка)"
    assert_no_match "<script>", response.body
  end

  test "follow-up questions stay in the same conversation and use message history" do
    conversation = @user.rag_conversations.create!(title: "Report", messages: [])
    conversation.append_message(role: "user", content: "What is the report about?")
    conversation.append_message(role: "assistant", content: "It covers sales.")
    assistant = StubAssistant.new

    with_assistant(assistant) do
      post chat_messages_path(conversation), params: { message: "And the conclusion?" }
    end

    assert_redirected_to chat_conversation_path(conversation)
    assert_equal "And the conclusion?", assistant.question
    assert_equal 2, assistant.options[:conversation].length
    assert_equal 4, conversation.reload.messages.length
  end

  test "follow-up questions normalize legacy JSON-string metadata" do
    conversation = @user.rag_conversations.create!(title: "Legacy", messages: [])
    conversation.update_column(:metadata, "{}")
    assistant = StubAssistant.new

    with_assistant(assistant) do
      post chat_messages_path(conversation), params: { message: "Can you elaborate?" }
    end

    assert_redirected_to chat_conversation_path(conversation)
    assert_equal({ "document_id" => nil }, conversation.reload.metadata)
    assert_equal 2, conversation.messages.length
  end

  test "does not allow opening another user's conversation" do
    conversation = users(:two).rag_conversations.create!(title: "Private", messages: [])

    get chat_conversation_path(conversation)

    assert_response :not_found
  end

  test "does not allow selecting another user's document" do
    document = create_document(users(:two), "private.txt")

    assert_no_difference("RagConversation.count") do
      post chat_path, params: {
        message: "What is in this document?",
        document_id: document.id
      }
    end

    assert_response :unprocessable_content
    assert_includes response.body, "selected document is not available"
  end

  private

  def create_document(user, filename)
    document = Document.new(user: user)
    document.file.attach(
      io: StringIO.new("Private document content."),
      filename: filename,
      content_type: "text/plain"
    )
    document.save!
    document
  end

  def with_assistant(assistant)
    original = ChatsController.instance_method(:rag_assistant)
    ChatsController.define_method(:rag_assistant) { assistant }
    yield
  ensure
    ChatsController.define_method(:rag_assistant, original)
    ChatsController.send(:private, :rag_assistant)
  end

  class StubAssistant
    attr_reader :question, :options

    def call(question, **options)
      @question = question
      @options = options
      Rag::Result.new(
        answer: "The report describes the main findings.",
        citations: [{ label: 1, filename: "report.txt", document_id: nil, content: "Main findings." }],
        retrieved_chunks: [],
        context: [],
        grounded: true,
        provider: "test",
        model: "test-model",
        error: nil
      )
    end
  end
end
