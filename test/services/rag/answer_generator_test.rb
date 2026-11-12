require "test_helper"

class RagAnswerGeneratorTest < ActiveSupport::TestCase
  test "formats the LLM response into a document-grounded answer" do
    stub_client = Object.new
    stub_client.define_singleton_method(:chat) do |parameters:|
      { "choices" => [ { "message" => { "content" => "The answer is grounded in the uploaded document." } } ] }
    end

    generator = Rag::AnswerGenerator.new(client: stub_client, provider: :vllm, model: "fake-model")
    result = generator.call(prompt: "What is in the document?", conversation: [{ "role" => "user", "content" => "Earlier question" }])

    assert_equal "The answer is grounded in the uploaded document.", result[:text]
    assert_equal :vllm, result[:provider]
  end

  test "raises when the model returns an empty reply" do
    stub_client = Object.new
    stub_client.define_singleton_method(:chat) do |parameters:|
      { "choices" => [ { "message" => { "content" => "" } } ] }
    end

    generator = Rag::AnswerGenerator.new(client: stub_client, provider: :vllm, model: "fake-model")

    assert_raises(StandardError) { generator.call(prompt: "Question") }
  end

  test "raises for unsupported providers" do
    generator = Rag::AnswerGenerator.new(client: Object.new, provider: :unknown_provider)

    assert_raises(ArgumentError) { generator.call(prompt: "Question") }
  end
end
