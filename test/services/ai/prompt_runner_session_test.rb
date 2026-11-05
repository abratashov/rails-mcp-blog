require "test_helper"

class AIPromptRunnerSessionTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  class StubWorkshop
    attr_reader :messages

    def initialize(messages)
      @messages = messages || [ { "role" => "user", "content" => "Workshop prompt" } ]
    end

    def start
      @messages << { "role" => "assistant", "content" => "Choose a topic" }
    end

    def reply(message)
      @messages << { "role" => "user", "content" => message }
      @messages << { "role" => "assistant", "content" => "Here is your feedback" }
    end

    def close
    end
  end

  class StubAccessToken
    attr_reader :revoked

    def token
      "test-token"
    end

    def revoke
      @revoked = true
    end
  end

  setup do
    @user = User.create!(email: "essay-session@example.test", password: "password")
    @session = {}
    @cache = ActiveSupport::Cache::MemoryStore.new
    @tokens = []
    @runner_options = []
    @workshop_factory = ->(**options) do
      @runner_options << options
      StubWorkshop.new(options[:messages])
    end
    @access_token_provider = ->(_user) do
      token = StubAccessToken.new
      @tokens << token
      token
    end
  end

  test "starts a prompt, caches messages, and revokes its temporary token" do
    result = service.submit(nil, arguments: { language: "English" })

    assert result.success
    assert result.started
    assert_equal "Choose a topic", result.messages.last.fetch("content")
    assert_equal "essay_workshop", @runner_options.first.fetch(:prompt_name)
    assert_equal({ "language" => "English" }, @runner_options.first.fetch(:prompt_arguments))
    assert @tokens.first.revoked
    assert_equal result.messages, service.show.messages
  end

  test "continues the prompt conversation from cached messages" do
    service.submit(nil, arguments: { language: "English" })
    result = service.submit("My essay")

    assert result.success
    assert_equal "My essay", result.messages[-2].fetch("content")
    assert_equal "Here is your feedback", result.messages.last.fetch("content")
  end

  test "rejects a reply before starting without issuing a token" do
    result = service.submit("My essay")

    assert_equal "Start the prompt before sending a response.", result.error
    assert_empty @tokens
    assert_empty @session
  end

  test "rejects blank messages and preserves them in the result" do
    service.submit(nil, arguments: { language: "English" })
    result = service.submit(" ")

    assert_equal "Please enter a message to continue.", result.error
    assert_equal " ", result.message
  end

  test "ends a prompt session and deletes cached messages" do
    service.submit(nil, arguments: { language: "English" })
    service.end_session

    assert_nil @session["prompt_runner:essay_workshop"]
    assert_empty service.show.messages
  end

  private

  def service
    AI::PromptRunnerSession.new(
      user: @user,
      session: @session,
      prompt_name: "essay_workshop",
      cache: @cache,
      runner_factory: @workshop_factory,
      access_token_provider: @access_token_provider
    )
  end
end
