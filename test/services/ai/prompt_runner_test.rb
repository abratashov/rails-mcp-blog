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

  class StubTransport
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def send_request(request:)
      @requests << request
      @responses.shift
    end

    def close
      @closed = true
    end

    def closed?
      @closed
    end
  end

  class StubMcpClient
    attr_reader :transport

    def initialize(transport)
      @transport = transport
    end

    def prompts
      [ { "name" => "essay_workshop" } ]
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

  test "loads MCP prompt messages and exposes the initial prompt" do
    workshop = build_runner(
      [
        {
          "result" => {
            "messages" => [
              { "role" => "user", "content" => { "type" => "text", "text" => "Write an essay" } },
              { "role" => "assistant", "content" => { "type" => "text", "text" => "Start here" } }
            ]
          }
        }
      ]
    )

    messages = workshop.send(:load_initial_messages)
    workshop.instance_variable_set(:@messages, messages)

    assert_equal [ "user", "assistant" ], messages.map { |message| message.fetch(:role) }
    assert_equal "Write an essay", workshop.initial_prompt.fetch(:content)
    assert_equal [ { "name" => "essay_workshop" } ], workshop.prompts
  end

  test "maps MCP tool schemas into LLM functions and provides an empty-schema fallback" do
    workshop = build_runner(
      [
        {
          "result" => {
            "tools" => [
              { "name" => "create_post", "description" => "Create a post", "inputSchema" => { "type" => "object" } },
              { "name" => "health_check" }
            ]
          }
        }
      ]
    )

    mapped = workshop.send(:load_llm_tools)

    assert_equal "create_post", mapped.first.dig(:function, :name)
    assert_equal "Create a post", mapped.first.dig(:function, :description)
    assert_equal({ "type" => "object" }, mapped.first.dig(:function, :parameters))
    assert_equal({ type: "object", properties: {} }, mapped.last.dig(:function, :parameters))
    assert_equal 2, workshop.tools.length
  end

  test "executes MCP tools, handles empty output, and rejects malformed tool arguments" do
    workshop = build_runner(
      [
        { "result" => { "content" => [ { "type" => "text", "text" => "Created post" } ] } },
        { "result" => { "content" => [] } }
      ]
    )
    call = { "id" => "call-1", "function" => { "name" => "create_post", "arguments" => '{"title":"Hello"}' } }
    result = workshop.send(:execute_tool, call)

    assert_equal "Created post", result.fetch(:content)
    assert_equal({ "title" => "Hello" }, result.fetch(:arguments))

    empty_call = { "id" => "call-2", "function" => { "name" => "no_output" } }
    empty_result = workshop.send(:execute_tool, empty_call)
    assert_equal({ "content" => [] }.inspect, empty_result.fetch(:content))

    malformed = call.deep_dup
    malformed["function"]["arguments"] = "{"
    invalid_result = workshop.send(:execute_tool, malformed)
    assert_includes invalid_result.fetch(:content), "Invalid JSON arguments"
  end

  test "requires an access token" do
    workshop = AI::PromptRunner.allocate
    workshop.instance_variable_set(:@access_token, nil)

    assert_raises(ArgumentError) { workshop.send(:transport) }
  end

  test "closes the MCP transport" do
    workshop = AI::PromptRunner.allocate
    transport = StubTransport.new([])
    workshop.instance_variable_set(:@transport, transport)
    workshop.instance_variable_set(:@access_token, "test-token")

    workshop.close

    assert transport.closed?
  end

  private

  def build_runner(responses)
    workshop = AI::PromptRunner.allocate
    workshop.instance_variable_set(:@prompt_name, "essay_workshop")
    workshop.instance_variable_set(:@prompt_arguments, { "language" => "English" })
    transport = StubTransport.new(responses)
    workshop.define_singleton_method(:client) { StubMcpClient.new(transport) }
    workshop
  end

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
