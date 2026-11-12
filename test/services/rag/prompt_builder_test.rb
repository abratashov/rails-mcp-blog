require "test_helper"

class RagPromptBuilderTest < ActiveSupport::TestCase
  Context = Struct.new(:filename, :page_start, :page_end, :content, keyword_init: true)

  test "includes grounding rules, context, conversation history, question, and detected language" do
    prompt = Rag::PromptBuilder.new.call(
      question: "Що радить цей документ? Які поради?",
      context: [ Context.new(filename: "guide.txt", page_start: 2, page_end: 3, content: "Перевірте список.") ],
      conversation: [
        { "role" => "user", "content" => "Поясни документ." },
        { "role" => "assistant", "content" => "Він містить інструкції." }
      ]
    )

    assert_includes prompt, "using only the retrieved document context"
    assert_includes prompt, "Answer in ukrainian"
    assert_includes prompt, "User: Поясни документ."
    assert_includes prompt, "Assistant: Він містить інструкції."
    assert_includes prompt, "[1] guide.txt (page 2-3)\nПеревірте список."
    assert_includes prompt, "Що радить цей документ? Які поради?"
  end

  test "explains when no relevant document context was retrieved" do
    prompt = Rag::PromptBuilder.new.call(question: "What is this about?", context: [])

    assert_includes prompt, "No relevant document context was retrieved."
    assert_includes prompt, "Answer in english"
  end
end
