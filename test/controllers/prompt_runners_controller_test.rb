require "test_helper"

class PromptRunnersControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  include Devise::Test::IntegrationHelpers

  class StubWorkshop
    attr_reader :messages

    def initialize(messages)
      @messages = messages || [ { "role" => "user", "content" => "Workshop prompt" } ]
    end

    def start
      @messages << { "role" => "assistant", "content" => "**Choose a topic**" }
    end

    def reply(message)
      @messages << { "role" => "user", "content" => message }
      @messages << { "role" => "assistant", "content" => "**Choose a topic**" }
    end

    def close
    end
  end

  setup do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user = User.create!(email: "essay-workshop@example.test", password: "password")
    sign_in @user
  end

  test "lists available prompts" do
    get prompts_url

    assert_response :success
    assert_select "h1", "Prompts"
    assert_select "a[href='#{prompt_runner_path("essay_workshop")}']", "Essay Workshop"
  end

  test "shows the essay workshop prompt and its optional arguments" do
    get prompt_runner_url("essay_workshop")

    assert_response :success
    assert_select "h1", "Essay Workshop"
    assert_select "main[data-controller='scroll-to-bottom']"
    assert_select "input[name='arguments[language]']:not([required])"
    assert_select "input[type=submit][value='Run prompt']"
  end

  test "returns not found for an unknown prompt" do
    get prompt_runner_url("unknown_prompt")

    assert_response :not_found
  end

  test "rejects a response before the prompt starts" do
    post prompt_runner_url("essay_workshop"), params: { message: "Not started yet" }

    assert_response :unprocessable_content
    assert_select ".prompt-runner__error", "Start the prompt before sending a response."
    assert_select "input[type=submit][value='Run prompt']"
  end

  test "starts a prompt and renders the response as markdown" do
    with_stubbed_workshop_session do
      post prompt_runner_url("essay_workshop"), params: { arguments: { language: "English" } }
    end

    assert_redirected_to prompt_runner_url("essay_workshop")
    follow_redirect!
    assert_response :success
    assert_select ".prompt-runner__message-content strong", "Choose a topic"
    assert_select "textarea[name='message']"
    assert_select ".prompt-runner__actions button", "End Session"
  end

  test "starts the essay workshop without specifying its default language" do
    with_stubbed_workshop_session do
      post prompt_runner_url("essay_workshop")
    end

    assert_redirected_to prompt_runner_url("essay_workshop")
  end

  test "continues the prompt conversation with the previous messages" do
    with_stubbed_workshop_session do
      post prompt_runner_url("essay_workshop"), params: { arguments: { language: "English" } }
      follow_redirect!
      post prompt_runner_url("essay_workshop"), params: { message: "My essay response" }
      follow_redirect!
    end

    assert_response :success
    assert_select ".prompt-runner__message--user", /My essay response/
  end

  private

  def with_stubbed_workshop_session
    original_new = AI::PromptRunnerSession.method(:new)
    AI::PromptRunnerSession.define_singleton_method(:new) do |**options|
      original_new.call(
        **options,
        runner_factory: ->(**runner_options) { StubWorkshop.new(runner_options[:messages]) },
        access_token_provider: ->(_user) { StubAccessToken.new }
      )
    end

    yield
  ensure
    AI::PromptRunnerSession.define_singleton_method(:new, original_new)
  end

  class StubAccessToken
    def token
      "test-token"
    end

    def revoke
    end
  end
end
