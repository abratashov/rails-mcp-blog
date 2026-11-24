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
      messages: [ { "role" => "assistant", "content" => "**Cat (кошка)**", "metadata" => {} } ]
    )
    conversation.update_column(:messages, '[{"role":"assistant","content":"**Cat (кошка)**","metadata":{}}]')

    get admin_rag_conversation_path(conversation)

    assert_response :success
    assert_select ".rag-chat__message--assistant strong", text: "Cat (кошка)"
    assert_no_match "**Cat (кошка)**", response.body
  end

  test "admin can delete a conversation through a CSRF-protected UJS link" do
    conversation = @user.rag_conversations.create!(title: "Conversation to delete", messages: [])
    with_forgery_protection do
      get admin_rag_conversations_path

      assert_response :success
      delete_path = admin_rag_conversation_path(conversation)
      document = Nokogiri::HTML(response.body)
      link = document.css("a.delete_link").find { |node| node["href"] == delete_path }
      assert link, "expected the index to render a delete link"
      assert_equal "delete", link["data-method"]
      token = document.at_css("meta[name='csrf-token']")&.[]("content")
      assert token.present?, "expected ActiveAdmin to publish the CSRF token for UJS"

      post delete_path, params: { _method: "delete" }
      assert_response :unprocessable_entity
      assert RagConversation.exists?(conversation.id), "a request without a CSRF token must not delete"

      post delete_path, params: { _method: "delete", authenticity_token: token }
      assert_redirected_to admin_rag_conversations_path
      assert_not RagConversation.exists?(conversation.id)
    end
  end

  test "show page renders a CSRF-protected UJS delete link" do
    conversation = @user.rag_conversations.create!(title: "Conversation to delete", messages: [])

    with_forgery_protection do
      get admin_rag_conversation_path(conversation)

      assert_response :success
      document = Nokogiri::HTML(response.body)
      link = document.css("a[data-method='delete']").find do |node|
        node["href"] == admin_rag_conversation_path(conversation)
      end
      assert link, "expected the show page to render a delete link"
      assert_equal "delete", link["data-method"]
      assert document.at_css("meta[name='csrf-token'][content]"), "expected a CSRF token for UJS"
    end
  end

  test "does not permit messages to be overwritten when updating a conversation" do
    conversation = @user.rag_conversations.create!(
      title: "Original title",
      messages: [ { "role" => "assistant", "content" => "Original answer", "metadata" => {} } ],
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

  private

  def with_forgery_protection
    controller = Admin::RagConversationsController
    previous_setting = controller.allow_forgery_protection
    controller.allow_forgery_protection = true
    yield
  ensure
    controller.allow_forgery_protection = previous_setting
  end
end
