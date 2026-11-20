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
    assert_equal "specific", result.metadata[:question_type]
    assert_equal "semantic_top_k", result.metadata[:retrieval_strategy]
  end

  test "returns an explicit no-evidence response when retrieval finds nothing" do
    assistant = Rag::Assistant.new(
      retriever: FakeRetriever.new([]),
      query_classifier: FakeQueryClassifier.new("specific"),
      answer_generator: FakeAnswerGenerator.new("unused")
    )

    result = assistant.call("What is in this document?", user: @user)

    assert_not result.grounded
    assert_empty result.sources
    assert_includes result.answer, "couldn't find enough relevant information"
  end

  test "records comparative queries and selected chunks and asks for an evidence-based comparison" do
    chunks = [
      Struct.new(:document_id, :filename, :page_start, :page_end, :position, :content, :score, :distance, :metadata).new(
        42, "wildlife.txt", 1, 1, 1, "Lions live in groups.", 0.9, 0.1, { "comparative_subject" => "lions" }
      ),
      Struct.new(:document_id, :filename, :page_start, :page_end, :position, :content, :score, :distance, :metadata).new(
        43, "wildlife.txt", 2, 2, 1, "Tigers are solitary.", 0.8, 0.2, { "comparative_subject" => "tigers" }
      )
    ]
    queries = [
      { subject: "lions", aspect: nil, text: "lions" },
      { subject: "tigers", aspect: nil, text: "tigers" }
    ]
    router = Struct.new(:result) do
      def call(*, **)
        result
      end
    end.new(Rag::RetrievalRouter::RoutingResult.new(
      chunks: chunks,
      strategy: "multi_chunk",
      retrieval_queries: queries
    ))
    answer_generator = CapturingAnswerGenerator.new("Lions live in groups [1], while tigers are solitary [2].")
    assistant = Rag::Assistant.new(
      query_classifier: FakeQueryClassifier.new("comparative"),
      retrieval_router: router,
      answer_generator: answer_generator
    )

    result = assistant.call("Compare lions and tigers", user: @user)

    assert_equal queries, result.metadata[:retrieval_queries]
    assert_equal [ 1, 1 ], result.metadata[:selected_chunks].map { |chunk| chunk[:position] }
    assert_includes answer_generator.prompt, "identify meaningful similarities and differences"
    assert_includes result.answer, "[1] wildlife.txt (p. 1)"
  end

  test "passes conversation history only to the answer generator" do
    conversation = [
      { "role" => "user", "content" => "Earlier question" },
      { "role" => "assistant", "content" => "Earlier answer" }
    ]
    answer_generator = CapturingAnswerGenerator.new("Grounded reply.")
    assistant = Rag::Assistant.new(
      query_classifier: FakeQueryClassifier.new("specific"),
      retriever: FakeRetriever.new([
        Struct.new(:document_id, :filename, :page_start, :page_end, :position, :content, :score, :distance, :metadata).new(
          42, "guide.txt", nil, nil, 1, "Document evidence.", 0.9, 0.1, {}
        )
      ]),
      answer_generator: answer_generator
    )

    assistant.call("Current question", user: @user, conversation: conversation)

    assert_equal conversation, answer_generator.conversation
    assert_includes answer_generator.prompt, "Current question"
    assert_not_includes answer_generator.prompt, "Earlier question"
    assert_not_includes answer_generator.prompt, "Earlier answer"
  end

  test "returns retrieval failures as explicit errors" do
    assistant = Rag::Assistant.new(
      retriever: FailingRetriever.new("query embedding unavailable"),
      query_classifier: FakeQueryClassifier.new("specific"),
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
      query_classifier: FakeQueryClassifier.new("specific"),
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
      query_classifier: FakeQueryClassifier.new("specific"),
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

  class CapturingAnswerGenerator < FakeAnswerGenerator
    attr_reader :prompt, :conversation

    def call(prompt:, conversation: [], **options)
      @prompt = prompt
      @conversation = conversation
      super(prompt: prompt, conversation: conversation, **options)
    end
  end

  class FakeQueryClassifier
    def initialize(question_type)
      @question_type = question_type
    end

    def call(_question)
      Rag::QueryClassifier::Classification.new(question_type: @question_type, confidence: 0.99)
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
