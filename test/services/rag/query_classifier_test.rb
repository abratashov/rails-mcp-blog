require "test_helper"

class RagQueryClassifierTest < ActiveSupport::TestCase
  test "returns structured classification for a supported question type" do
    classifier = Rag::QueryClassifier.new(
      client: StubClient.new('{"type":"comparative","confidence":0.92}'),
      confidence_threshold: 0.7
    )

    result = classifier.call("Discuss the relationship between lions and tigers")

    assert_equal "comparative", result.question_type
    assert_equal 0.92, result.confidence
    assert_nil result.error
  end

  test "accepts all supported question types" do
    {
      "specific" => "What do lions eat?",
      "comparative" => "Compare lions and tigers",
      "aggregation" => "How many species are mentioned?"
    }.each do |type, _question|
      classifier = Rag::QueryClassifier.new(
        client: StubClient.new({ type: type, confidence: 0.99 }.to_json),
        confidence_threshold: 0.7
      )

      assert_equal type, classifier.call("Tell me about animals.").question_type
    end
  end

  test "falls back to specific when confidence is below the configured threshold" do
    classifier = Rag::QueryClassifier.new(
      client: StubClient.new('{"type":"aggregation","confidence":0.4}'),
      confidence_threshold: 0.7
    )

    result = classifier.call("Give me a total for the species list.")

    assert_equal "specific", result.question_type
    assert_equal 0.4, result.confidence
    assert_match(/below the configured threshold/, result.error)
  end

  test "falls back to specific when the model response is not valid structured output" do
    classifier = Rag::QueryClassifier.new(
      client: StubClient.new("not JSON"),
      confidence_threshold: 0.5
    )

    result = classifier.call("Tell me about lion diets.")

    assert_equal "specific", result.question_type
    assert_match(/invalid structured result/, result.error)
  end

  test "falls back to specific when the provider request fails" do
    classifier = Rag::QueryClassifier.new(client: FailingClient.new, confidence_threshold: 0.5)

    result = classifier.call("Explain the relationship between lions and tigers.")

    assert_equal "specific", result.question_type
    assert_match(/Classification failed/, result.error)
  end

  test "rejects a confidence threshold outside the supported range" do
    assert_raises(ArgumentError) do
      Rag::QueryClassifier.new(client: StubClient.new("{}"), confidence_threshold: 1.1)
    end
  end

  test "classifies clear English, Ukrainian, and Russian intents without an LLM request" do
    classifier = Rag::QueryClassifier.new(client: FailingClient.new)
    questions = {
      "Compare lions and tigers" => "comparative",
      "Порівняй соціальну поведінку левів і тигрів." => "comparative",
      "How many species are described?" => "aggregation",
      "Скільки видів описано?" => "aggregation",
      "Как обычно живут взрослые тигры?" => "specific",
      "Чим харчуються пінгвіни?" => "specific"
    }

    questions.each do |question, expected_type|
      result = classifier.call(question)

      assert_equal expected_type, result.question_type, question
      assert_equal 1.0, result.confidence, question
      assert_nil result.error, question
    end
  end

  class StubClient
    def initialize(content)
      @content = content
    end

    def chat(parameters:)
      @calls = @calls.to_i + 1
      { "choices" => [ { "message" => { "content" => @content } } ] }
    end

    attr_reader :calls
  end

  class FailingClient
    def chat(parameters:)
      raise "provider unavailable"
    end
  end
end
