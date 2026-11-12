require "test_helper"

class RagConversationTest < ActiveSupport::TestCase
  test "allows only safe attributes and the user association in Ransack" do
    assert_equal %w[created_at id title updated_at user_id], RagConversation.ransackable_attributes
    assert_equal %w[user], RagConversation.ransackable_associations
  end

  test "appends a user message with metadata" do
    conversation = RagConversation.new(user: users(:one), title: "Follow-up", messages: [])

    conversation.append_message(
      role: "user",
      content: "What happened in the report?",
      metadata: { "document" => "report.pdf" }
    )

    assert_equal "user", conversation.messages.last["role"]
    assert_equal "What happened in the report?", conversation.messages.last["content"]
    assert_equal "report.pdf", conversation.messages.last["metadata"]["document"]
  end

  test "normalizes JSON-string metadata" do
    conversation = RagConversation.new(
      user: users(:one),
      title: "Conversation",
      messages: [],
      metadata: '{"document_id":12}'
    )

    assert conversation.valid?
    assert_equal({ "document_id" => 12 }, conversation.metadata)
    assert_equal({ "document_id" => 12 }, conversation.metadata_hash)
  end
end
