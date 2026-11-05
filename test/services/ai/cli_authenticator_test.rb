require "test_helper"
require "uri"
require "net/http"
require "socket"

class AICLIAuthenticatorTest < ActiveSupport::TestCase
  setup do
    @authenticator = AI::CLIAuthenticator.new(
      client_id: "test-client",
      authorization_url: "https://auth.example.test/authorize",
      token_url: "https://auth.example.test/token",
      scope: "public read",
      port: 19_876
    )
  end

  test "builds a PKCE authorization URL with an S256 challenge" do
    verifier = @authenticator.send(:generate_code_verifier)
    challenge = @authenticator.send(:generate_code_challenge, verifier)
    url = URI.parse(@authenticator.send(
      :build_authorization_url,
      redirect_uri: "http://127.0.0.1:19876/oauth/callback",
      code_challenge: challenge
    ))
    params = URI.decode_www_form(url.query).to_h

    assert_equal "https", url.scheme
    assert_equal "code", params.fetch("response_type")
    assert_equal "test-client", params.fetch("client_id")
    assert_equal "public read", params.fetch("scope")
    assert_equal "S256", params.fetch("code_challenge_method")
    assert_equal challenge, params.fetch("code_challenge")
    assert_equal "http://127.0.0.1:19876/oauth/callback", params.fetch("redirect_uri")
    assert_equal 43, challenge.length
  end

  test "exchanges an authorization code for a token using a mocked OAuth response" do
    stub_request(:post, "https://auth.example.test/token")
      .with(
        body: hash_including(
          "grant_type" => "authorization_code",
          "client_id" => "test-client",
          "code" => "authorization-code",
          "code_verifier" => "verifier"
        )
      )
      .to_return(
        body: { access_token: "mock-access-token" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    token = @authenticator.send(
      :exchange_code_for_token,
      code: "authorization-code",
      code_verifier: "verifier",
      redirect_uri: "http://127.0.0.1:19876/oauth/callback"
    )

    assert_equal "mock-access-token", token
  end

  test "reports OAuth error, unsuccessful token response, missing token, and invalid JSON" do
    assert_raises(RuntimeError) { authenticate_with_result(error: "access_denied", error_description: "User cancelled") }

    stub_request(:post, "https://auth.example.test/token")
      .to_return(status: 401, body: "unauthorized")
    error = assert_raises(RuntimeError) do
      exchange_token
    end
    assert_includes error.message, "HTTP status: 401"

    stub_request(:post, "https://auth.example.test/token")
      .to_return(body: '{"token_type":"Bearer"}')
    error = assert_raises(RuntimeError) { exchange_token }
    assert_includes error.message, "does not contain an access_token"

    stub_request(:post, "https://auth.example.test/token")
      .to_return(body: "not-json")
    error = assert_raises(RuntimeError) { exchange_token }
    assert_includes error.message, "contains invalid JSON"
  end

  test "completes authentication and cleans up the callback server" do
    server = Object.new
    server.define_singleton_method(:shutdown) { @stopped = true }
    callback = Queue.new
    callback << { code: "authorization-code" }
    thread = Thread.new { }

    @authenticator.define_singleton_method(:start_callback_server) { [ server, thread, callback ] }
    @authenticator.define_singleton_method(:open_browser) { |_url| true }

    stub_request(:post, "https://auth.example.test/token")
      .to_return(body: { access_token: "mock-access-token" }.to_json)

    output, = capture_io do
      assert_equal "mock-access-token", @authenticator.authenticate
    end

    assert_includes output, "Authentication successful."
    assert thread.join
    assert server.instance_variable_get(:@stopped)
  end

  test "opens the authorization URL with the platform browser command" do
    command = nil
    @authenticator.define_singleton_method(:system) do |*arguments|
      command = arguments
      true
    end

    assert @authenticator.send(:open_browser, "https://auth.example.test/authorize")
    assert_equal [ "xdg-open", "https://auth.example.test/authorize" ], command
  end

  test "handles successful and failed OAuth callback requests" do
    with_callback_server do |server, thread, callback|
      response = callback_request("/oauth/callback?code=returned-code")

      assert_equal "200", response.code
      assert_includes response.body, "Authentication successful"
      assert_equal({ code: "returned-code" }, callback.pop)
    ensure
      server&.shutdown
      thread&.join
    end

    with_callback_server do |server, thread, callback|
      response = callback_request("/oauth/callback?error=access_denied&error_description=Cancelled")

      assert_equal "400", response.code
      assert_includes response.body, "Authentication failed"
      assert_equal(
        { error: "access_denied", error_description: "Cancelled" },
        callback.pop
      )
    ensure
      server&.shutdown
      thread&.join
    end
  end

  private

  def with_callback_server
    server, thread, callback = @authenticator.send(:start_callback_server)
    yield server, thread, callback
  ensure
    server&.shutdown
    thread&.join
  end

  def callback_request(path)
    uri = URI("http://127.0.0.1:19876#{path}")
    30.times do
      return Net::HTTP.get_response(uri)
    rescue Errno::ECONNREFUSED
      sleep 0.01
    end

    raise "OAuth callback server did not start"
  end

  def exchange_token
    @authenticator.send(
      :exchange_code_for_token,
      code: "authorization-code",
      code_verifier: "verifier",
      redirect_uri: "http://127.0.0.1:19876/oauth/callback"
    )
  end

  def authenticate_with_result(result)
    callback = Queue.new
    callback << result
    server = Object.new
    server.define_singleton_method(:shutdown) { }
    thread = Thread.new { }
    @authenticator.define_singleton_method(:start_callback_server) { [ server, thread, callback ] }
    @authenticator.define_singleton_method(:open_browser) { |_url| true }

    capture_io { @authenticator.authenticate }
  end
end
