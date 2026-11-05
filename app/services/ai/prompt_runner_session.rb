# frozen_string_literal: true

require "json"
require "securerandom"

module AI
  class PromptRunnerSession
    CACHE_TTL = 2.hours
    MAX_MESSAGE_LENGTH = 10_000
    SESSION_KEY_PREFIX = "prompt_runner:"

    Result = Struct.new(
      :messages, :started, :error, :success, :message, :prompt, :arguments, :not_found,
      keyword_init: true
    )

    def self.available_prompts
      MCP::Prompt.descendants
        .select { |prompt| prompt.name&.safe_constantize == prompt }
        .uniq(&:name_value)
        .map { |prompt| prompt_details(prompt) }
        .sort_by { |prompt| prompt.fetch(:name) }
    end

    def self.prompt_details(prompt)
      {
        name: prompt.name_value,
        title: prompt.title_value.presence || prompt.name_value.humanize,
        description: prompt.description_value,
        arguments: prompt.arguments_value.map(&:to_h)
      }
    end

    def initialize(
      user:,
      session:,
      prompt_name:,
      cache: Rails.cache,
      runner_factory: nil,
      access_token_provider: nil
    )
      @user = user
      @session = session
      @prompt_name = prompt_name.to_s
      @cache = cache
      @runner_factory = runner_factory || ->(**options) { PromptRunner.new(**options) }
      @access_token_provider = access_token_provider || method(:create_access_token)
    end

    def show
      prompt = find_prompt
      return result(messages: [], error: "Prompt not found.", not_found: true) unless prompt

      messages = load_messages
      if session_id && messages.nil?
        @session.delete(session_key)
        return result(
          messages: [],
          prompt: prompt,
          error: "Your session expired. Start a new session."
        )
      end

      result(messages: messages || [], prompt: prompt)
    end

    def submit(message, arguments: {})
      prompt = find_prompt
      return result(messages: [], error: "Prompt not found.", not_found: true) unless prompt

      messages = load_messages
      message = message.to_s
      arguments = normalize_arguments(arguments)

      if session_id && messages.nil?
        @session.delete(session_key)
        return result(
          messages: [],
          prompt: prompt,
          error: "Your session expired. Start a new session.",
          message: message,
          arguments: arguments
        )
      end

      if message.length > MAX_MESSAGE_LENGTH
        return result(
          messages: messages || [],
          prompt: prompt,
          error: "Messages must be 10,000 characters or fewer.",
          message: message,
          arguments: arguments
        )
      end

      if messages
        if message.blank?
          return result(
            messages: messages,
            prompt: prompt,
            error: "Please enter a message to continue.",
            message: message,
            arguments: arguments
          )
        end
      elsif message.present?
        return result(
          messages: [],
          prompt: prompt,
          error: "Start the prompt before sending a response.",
          message: message,
          arguments: arguments
        )
      end

      missing_arguments = prompt.fetch(:arguments)
        .select { |argument| argument[:required] && arguments[argument[:name]].blank? }
        .map { |argument| argument[:name] }

      if messages.nil? && missing_arguments.any?
        return result(
          messages: [],
          prompt: prompt,
          error: "Please provide the required prompt arguments: #{missing_arguments.join(", ")}.",
          arguments: arguments
        )
      end

      with_access_token do |token|
        runner = @runner_factory.call(
          prompt_name: @prompt_name,
          prompt_arguments: messages ? {} : arguments,
          provider: ENV.fetch("LLM_PROVIDER", "vllm"),
          mcp_url: ENV.fetch("MCP_URL", PromptRunner::MCP_URL),
          messages: messages.presence,
          access_token: token
        )

        messages ? runner.reply(message) : runner.start
        messages = runner.messages
        @session[session_key] ||= SecureRandom.uuid
        unless @cache.write(cache_key, JSON.generate(messages), expires_in: CACHE_TTL)
          raise "Unable to save the prompt conversation."
        end
      ensure
        runner&.close
      end

      result(messages: messages, prompt: prompt, success: true)
    end

    def end_session
      @cache.delete(cache_key) if session_id
      @session.delete(session_key)
    end

    private

    def result(messages:, error: nil, success: false, started: nil, message: nil, prompt: nil, arguments: {}, not_found: false)
      started = messages.length > 1 if started.nil?
      Result.new(
        messages: messages,
        started: started,
        error: error,
        success: success,
        message: message,
        prompt: prompt,
        arguments: arguments,
        not_found: not_found
      )
    end

    def find_prompt
      self.class.available_prompts.find { |prompt| prompt.fetch(:name) == @prompt_name }
    end

    def normalize_arguments(arguments)
      return {} unless arguments.respond_to?(:to_h)

      arguments.to_h.stringify_keys
    end

    def load_messages
      return unless session_id

      cached_messages = @cache.read(cache_key)
      JSON.parse(cached_messages) if cached_messages
    end

    def session_key
      "#{SESSION_KEY_PREFIX}#{@prompt_name}"
    end

    def session_id
      @session[session_key]
    end

    def cache_key
      "prompt_runner:#{@user.id}:#{@prompt_name}:#{session_id}"
    end

    def with_access_token
      access_token = @access_token_provider.call(@user)
      yield access_token.token
    ensure
      access_token&.revoke
    end

    def create_access_token(user)
      application = Doorkeeper::Application.find_or_create_by!(
        name: "Rails Prompt Runner"
      ) do |app|
        app.redirect_uri = "https://localhost"
        app.scopes = "public"
        app.confidential = true
      end

      Doorkeeper::AccessToken.create!(
        application: application,
        resource_owner_id: user.id,
        scopes: "public"
      )
    end
  end
end
