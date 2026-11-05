require "test_helper"

class AIPromptRunnerTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class StubLLM
    def initialize(responses)
      @responses = responses
    end

    def chat(**_parameters)
      { "choices" => [ { "message" => @responses.shift } ] }
    end
  end

  test "starts with the prompt and returns the assistant turn" do
    workshop = build_workshop(
      [ { "role" => "user", "content" => "Workshop prompt" } ],
      [ { "role" => "assistant", "content" => "Choose a topic" } ]
    )

    result = workshop.start

    assert_equal "Choose a topic", result.fetch(:text)
    assert_equal %w[user assistant], workshop.messages.map { |message| message["role"] || message[:role] }
  end

  test "adds each reply and returns the next assistant turn" do
    workshop = build_workshop(
      [
        { "role" => "user", "content" => "Workshop prompt" },
        { "role" => "assistant", "content" => "Choose a topic" }
      ],
      [ { "role" => "assistant", "content" => "Here is your feedback" } ]
    )

    result = workshop.reply("My essay")

    assert_equal "Here is your feedback", result.fetch(:text)
    assert_equal %w[user assistant user assistant], workshop.messages.map { |message| message["role"] || message[:role] }
    assert_equal "My essay", workshop.messages[-2]["content"] || workshop.messages[-2][:content]
  end

  test "requires a started conversation before replying" do
    workshop = build_workshop(
      [ { "role" => "user", "content" => "Workshop prompt" } ],
      []
    )

    assert_raises(ArgumentError) { workshop.reply("My essay") }
  end

  test "does not allow starting a conversation twice" do
    workshop = build_workshop(
      [
        { "role" => "user", "content" => "Workshop prompt" },
        { "role" => "assistant", "content" => "Choose a topic" }
      ],
      []
    )

    assert_raises(ArgumentError) { workshop.start }
  end

  test "rejects a blank reply" do
    workshop = build_workshop(
      [
        { "role" => "user", "content" => "Workshop prompt" },
        { "role" => "assistant", "content" => "Choose a topic" }
      ],
      []
    )

    assert_raises(ArgumentError) { workshop.reply(" \n") }
  end

  test "surfaces an MCP error response with its message and code" do
    workshop = AI::PromptRunner.allocate

    error = assert_raises(MCP::Client::ServerError) do
      workshop.send(
        :result_from_response,
        { "error" => { "code" => -32602, "message" => "Missing required arguments: language" } },
        "prompts/get"
      )
    end

    assert_equal -32602, error.code
    assert_equal "Missing required arguments: language", error.message
  end

  private

  def build_workshop(messages, responses)
    workshop = AI::PromptRunner.allocate
    workshop.instance_variable_set(:@prompt_name, "essay_workshop")
    workshop.instance_variable_set(:@prompt_arguments, { "language" => "English" })
    workshop.instance_variable_set(:@has_started, messages.any? { |message| (message["role"] || message[:role]) == "assistant" })
    workshop.instance_variable_set(:@provider, :vllm)
    workshop.instance_variable_set(:@messages, messages)
    workshop.instance_variable_set(:@llm_tools, [])
    llm = StubLLM.new(responses)
    workshop.define_singleton_method(:llm) { llm }
    workshop
  end
end
