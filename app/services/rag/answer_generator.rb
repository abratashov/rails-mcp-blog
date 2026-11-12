module Rag
  class AnswerGenerator
    def initialize(client: nil, provider: ENV.fetch("LLM_PROVIDER", "vllm").to_sym, model: nil, temperature: 0.2, max_tokens: nil)
      @client = client
      @provider = provider.to_sym
      @model = model
      @temperature = temperature
      @max_tokens = max_tokens
    end

    def call(prompt:, conversation: [], model: nil)
      client = @client || OpenAI::Client.new(
        access_token: llm_config.fetch(:access_token),
        uri_base: llm_config.fetch(:url)
      )

      messages = Array(conversation).map { |message| normalize_message(message) }
      messages << { "role" => "user", "content" => prompt.to_s }

      parameters = {
        model: model || @model || llm_config.fetch(:model),
        messages: messages
      }
      parameters[:temperature] = @temperature unless @temperature.nil?
      parameters[:max_tokens] = @max_tokens unless @max_tokens.nil?

      response = client.chat(parameters: parameters)
      content = response.dig("choices", 0, "message", "content") || response.dig("output_text") || response.dig("message", "content")
      text = extract_text(content)

      raise StandardError, "The LLM returned an empty response" if text.to_s.strip.empty?

      {
        text: text.to_s.strip,
        provider: @provider,
        model: parameters[:model]
      }
    end

    private

    def llm_config
      AI::PromptRunner::LLMS.fetch(@provider)
    rescue KeyError
      raise ArgumentError, "Unsupported LLM provider: #{@provider}"
    end

    def normalize_message(message)
      return message if message.is_a?(Hash) && message.key?("role") || message.is_a?(Hash) && message.key?(:role)

      if message.is_a?(Hash)
        return {
          "role" => message[:role] || message["role"],
          "content" => message[:content] || message["content"]
        }
      end

      { "role" => "user", "content" => message.to_s }
    end

    def extract_text(content)
      case content
      when Array
        content.map { |entry| entry.is_a?(Hash) ? entry["text"].to_s : entry.to_s }.join
      when Hash
        content["text"].to_s
      else
        content.to_s
      end
    end
  end
end
