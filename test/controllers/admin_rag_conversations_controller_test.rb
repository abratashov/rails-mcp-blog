require "test_helper"

class AdminRagConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(password: "secure-password", password_confirmation: "secure-password")
    post user_session_path, params: {
      user: { email: @user.email, password: "secure-password" }
    }
  end

  test "new conversation form hides the user selector" do
    get new_admin_rag_conversation_path

    assert_response :success
    assert_select "select[name='rag_conversation[user_id]']", count: 0
    assert_select "input[name='rag_conversation[title]']"
    assert_select "textarea[name='rag_conversation[messages]']", count: 0
    assert_select "textarea[name='rag_conversation[metadata]']", count: 0
  end

  test "assigns the signed-in user and ignores a submitted user id" do
    another_user = users(:two)

    assert_difference("RagConversation.count") do
      post admin_rag_conversations_path, params: {
        rag_conversation: {
          title: "Test conversation",
          messages: "not valid JSON",
          metadata: "{}",
          user_id: another_user.id
        }
      }
    end

    assert_equal @user, RagConversation.order(:id).last.user
    assert_empty RagConversation.order(:id).last.messages
  end

  test "shows markdown-formatted messages stored as a JSON string" do
    conversation = RagConversation.create!(
      user: @user,
      title: "Existing conversation",
      messages: [{ "role" => "assistant", "content" => "**Cat (кошка)**", "metadata" => {} }]
    )
    conversation.update_column(:messages, '[{"role":"assistant","content":"**Cat (кошка)**","metadata":{}}]')

    get admin_rag_conversation_path(conversation)

    assert_response :success
    assert_select ".rag-chat__message--assistant strong", text: "Cat (кошка)"
    assert_no_match "**Cat (кошка)**", response.body
  end

  test "does not permit messages to be overwritten when updating a conversation" do
    conversation = @user.rag_conversations.create!(
      title: "Original title",
      messages: [{ "role" => "assistant", "content" => "Original answer", "metadata" => {} }],
      metadata: { "document_id" => 12 }
    )

    patch admin_rag_conversation_path(conversation), params: {
      rag_conversation: {
        title: "Updated title",
        messages: "not valid JSON",
        metadata: "not valid JSON either"
      }
    }

    assert_redirected_to admin_rag_conversation_path(conversation)
    assert_equal "Updated title", conversation.reload.title
    assert_equal "Original answer", conversation.messages.first["content"]
    assert_equal({ "document_id" => 12 }, conversation.metadata)
  end
end
