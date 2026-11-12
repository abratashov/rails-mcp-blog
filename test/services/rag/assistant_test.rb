require "test_helper"

class RagAssistantTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "retrieves relevant chunks, assembles context, and returns a cited answer" do
    result = build_assistant.call("What should I do?", user: @user)

    assert result.grounded
    assert_equal "guide.txt", result.sources.first[:filename]
    assert_equal 1, result.sources.first[:label]
    assert_equal "Follow the checklist before publishing.", result.sources.first[:content]
    assert_includes result.answer, "Sources:"
    assert_includes result.answer, "[1] guide.txt"
  end

  test "returns an explicit no-evidence response when retrieval finds nothing" do
    assistant = Rag::Assistant.new(
      retriever: FakeRetriever.new([]),
      answer_generator: FakeAnswerGenerator.new("unused")
    )

    result = assistant.call("What is in this document?", user: @user)

    assert_not result.grounded
    assert_empty result.sources
    assert_includes result.answer, "couldn't find enough relevant information"
  end

  test "returns retrieval failures as explicit errors" do
    assistant = Rag::Assistant.new(
      retriever: FailingRetriever.new("query embedding unavailable"),
      answer_generator: FakeAnswerGenerator.new("unused")
    )

    result = assistant.call("What should I do?", user: @user)

    assert_not result.grounded
    assert_equal "query embedding unavailable", result.error
    assert_includes result.answer, "retrieval or LLM response failed"
  end

  test "returns answer generation failures as explicit errors" do
    assistant = Rag::Assistant.new(
      retriever: FakeRetriever.new([
        Struct.new(:document_id, :filename, :page_start, :page_end, :position, :content, :score, :distance, :metadata).new(
          42, "guide.txt", nil, nil, 1, "Follow the checklist.", 0.9, 0.1, {}
        )
      ]),
      answer_generator: FailingAnswerGenerator.new("chat provider unavailable")
    )

    result = assistant.call("What should I do?", user: @user)

    assert_not result.grounded
    assert_equal "chat provider unavailable", result.error
    assert_includes result.answer, "retrieval or LLM response failed"
  end

  test "retriever delegates semantic search and preserves question context" do
    fake_search = FakeSemanticSearch.new
    retriever = Rag::Retriever.new(search_service: fake_search)

    results = retriever.call("Summarize the guide", user: @user, top_k: 7)

    assert_equal ["guide"], results.map(&:content)
    assert_equal "Summarize the guide", fake_search.options[:question]
  end

  private

  def build_assistant
    Rag::Assistant.new(
      retriever: FakeRetriever.new([
        Struct.new(:document_id, :filename, :page_start, :page_end, :position, :content, :score, :distance, :metadata).new(
          42,
          "guide.txt",
          2,
          4,
          1,
          "Follow the checklist before publishing.",
          0.92,
          0.08,
          { "language" => "en" }
        )
      ]),
      answer_generator: FakeAnswerGenerator.new("You should follow the checklist before publishing.")
    )
  end

  class FakeRetriever
    def initialize(results)
      @results = results
    end

    def call(_question, user:, document_id: nil, metadata: nil, top_k: nil)
      raise ArgumentError, "A user is required to retrieve document evidence" if user.blank?

      @results
    end
  end

  class FakeAnswerGenerator
    def initialize(answer)
      @answer = answer
    end

    def call(prompt:, conversation: [], model: nil)
      { text: @answer, provider: :fake, model: model || "fake-model" }
    end
  end

  class FailingRetriever
    def initialize(message)
      @message = message
    end

    def call(*, **)
      raise @message
    end
  end

  class FailingAnswerGenerator
    def initialize(message)
      @message = message
    end

    def call(**)
      raise @message
    end
  end

  class FakeSemanticSearch
    attr_reader :options

    def call(question, user:, document_id: nil, metadata: nil)
      @options = { question: question, user: user, document_id: document_id, metadata: metadata }
      [Struct.new(:content).new("guide")]
    end
  end
end
