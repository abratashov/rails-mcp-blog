# frozen_string_literal: true

require "json"
require "mcp"
require "openai"
require "securerandom"

module AI
  class PromptRunner
    MCP_URL = ENV.fetch(
      "MCP_URL",
      "http://localhost:3000/mcp"
    )

    LLMS = {
      ollama: {
        access_token: "ollama",
        model: "qwen3:4b",
        url: "http://localhost:11434/v1"
      },

      openai: {
        access_token: ENV["OPENAI_API_KEY"],
        model: "gpt-5",
        url: "https://api.openai.com/v1"
      },

      openrouter: {
        access_token: ENV["OPENROUTER_API_KEY"],
        model: "openrouter/free",
        url: "https://openrouter.ai/api/v1"
      },

      vllm: {
        access_token: "vllm",
        model: "Qwen/Qwen3-4B-AWQ",
        url: "http://localhost:8000/v1"
      }
    }.freeze

    attr_reader :messages, :provider

    def initialize(
      prompt_name:,
      prompt_arguments: {},
      provider: :vllm,
      mcp_url: MCP_URL,
      messages: nil,
      access_token: nil
    )
      @provider = provider.to_sym
      @prompt_name = prompt_name.to_s
      @prompt_arguments = prompt_arguments.stringify_keys
      @mcp_url = mcp_url
      @access_token = access_token

      @has_started = !messages.nil?
      @messages = messages || load_initial_messages
      @llm_tools = load_llm_tools
    end

    def start
      raise ArgumentError, "The prompt has already started." if @has_started

      perform_turn.tap { @has_started = true }
    end

    def reply(user_input)
      raise ArgumentError, "The prompt has not started yet." unless @has_started
      raise ArgumentError, "A reply cannot be blank" if user_input.blank?

      add_user_message(user_input)
      perform_turn
    end

    def prompts
      client.prompts
    end

    def tools
      @mcp_tools
    end

    def initial_prompt
      @messages.first
    end

    def close
      transport.close
    end

    private

    def perform_turn
      assistant_message = nil
      tool_calls = []

      loop do
        response = llm.chat(
          parameters: {
            model: llm_config.fetch(:model),
            messages: @messages,
            tools: @llm_tools
          }
        )

        assistant_message = extract_assistant_message(response)

        @messages << assistant_message

        current_tool_calls = assistant_message["tool_calls"] || []

        current_tool_calls.each do |tool_call|
          tool_result = execute_tool(tool_call)

          tool_calls << tool_result

          @messages << {
            role: "tool",
            tool_call_id: tool_call.fetch("id"),
            content: tool_result.fetch(:content)
          }
        end

        break if current_tool_calls.empty?
      end

      {
        text: assistant_message["content"],
        tool_calls: tool_calls,
        messages: @messages
      }
    end

    # ------------------------------------------------------------
    # LLM
    # ------------------------------------------------------------

    def llm
      @llm ||= OpenAI::Client.new(
        access_token: llm_config.fetch(:access_token),
        uri_base: llm_config.fetch(:url)
      )
    end

    def llm_config
      LLMS.fetch(@provider)
    end

    def extract_assistant_message(response)
      response
        .fetch("choices")
        .first
        .fetch("message")
    end

    # ------------------------------------------------------------
    # MCP
    # ------------------------------------------------------------

    def transport
      raise ArgumentError, "access_token is required" if @access_token.blank?

      @transport ||= MCP::Client::HTTP.new(
        url: @mcp_url,
        headers: {
          "Authorization" => "Bearer #{@access_token}"
        }
      )
    end

    # def transport
    #   @transport ||= MCP::Client::HTTP.new(
    #     url: @mcp_url,
    #     oauth: AccessToken.new(@access_token)
    #   )
    # end

    def client
      @client ||= begin
        client = MCP::Client.new(transport: transport)
        client.connect
        client
      end
    end

    # ------------------------------------------------------------
    # Prompt
    # ------------------------------------------------------------

    def load_initial_messages
      response = client.transport.send_request(
        request: {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: "prompts/get",
          params: {
            name: @prompt_name,
            arguments: @prompt_arguments
          }
        }
      )

      result_from_response(response, "prompts/get")
        .fetch("messages")
        .map do |message|
          {
            role: message.fetch("role"),
            content: message.dig(
              "content",
              "text"
            )
          }
        end
    end

    # ------------------------------------------------------------
    # Tools
    # ------------------------------------------------------------

    def load_llm_tools
      response = client.transport
        .send_request(
          request: {
            jsonrpc: "2.0",
            id: SecureRandom.uuid,
            method: "tools/list",
            params: {}
          }
        )
      @mcp_tools = result_from_response(response, "tools/list").fetch("tools")

      @mcp_tools.map do |tool|
        {
          type: "function",
          function: {
            name: tool.fetch("name"),
            description: tool["description"],
            parameters: tool["inputSchema"] || {
              type: "object",
              properties: {}
            }
          }
        }
      end
    end

    def execute_tool(tool_call)
      function = tool_call.fetch("function")

      tool_name = function.fetch("name")

      arguments_json = function["arguments"] || "{}"

      arguments =
        begin
          JSON.parse(arguments_json)
        rescue JSON::ParserError => e
          return {
            id: tool_call.fetch("id"),
            name: tool_name,
            arguments: arguments_json,
            content: "Invalid JSON arguments: #{e.message}"
          }
        end

      response = client.transport.send_request(
        request: {
          jsonrpc: "2.0",
          id: SecureRandom.uuid,
          method: "tools/call",
          params: {
            name: tool_name,
            arguments: arguments
          }
        }
      )

      result = response.fetch("result", {})

      content = result["content"] || []

      text = content
        .select { |item| item["type"] == "text" }
        .map { |item| item["text"] }
        .join("\n")

      text = result.inspect if text.empty?

      {
        id: tool_call.fetch("id"),
        name: tool_name,
        arguments: arguments,
        content: text
      }
    end

    def result_from_response(response, method)
      return response.fetch("result") if response.key?("result")

      error = response["error"]
      if error
        raise MCP::Client::ServerError.new(
          error.fetch("message", "Unknown MCP error"),
          code: error.fetch("code"),
          data: error["data"]
        )
      end

      raise MCP::Client::ValidationError,
        "MCP #{method} response did not contain a result or error."
    end

    def add_user_message(content)
      @messages << {
        role: "user",
        content: content
      }
    end
  end
end
