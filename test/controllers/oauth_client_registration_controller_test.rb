require "test_helper"

class OauthClientRegistrationControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "registers a public MCP client and returns its metadata" do
    assert_difference("Doorkeeper::Application.count", 1) do
      post "/oauth/register",
        params: {
          client_name: "Test MCP client",
          redirect_uris: [ "https://client.example.test/callback" ]
        }.to_json,
        headers: { "CONTENT_TYPE" => "application/json" }
    end

    assert_response :created
    registration = response.parsed_body
    assert_equal "Test MCP client", registration.fetch("client_name")
    assert_equal [ "https://client.example.test/callback" ], registration.fetch("redirect_uris")
    assert_equal [ "authorization_code" ], registration.fetch("grant_types")
    assert_equal "client_secret_post", registration.fetch("token_endpoint_auth_method")
    assert registration.fetch("client_id").present?
    assert registration.fetch("client_secret").present?
  end

  test "rejects a non-JSON registration request" do
    post "/oauth/register",
      params: "client_name=client",
      headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }

    assert_response :bad_request
    assert_equal "invalid_request", response.parsed_body.fetch("error")
  end

  test "rejects invalid client metadata" do
    post "/oauth/register",
      params: { client_name: "Invalid client", redirect_uris: [ "not a url" ] }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
    assert_includes response.body, "invalid_redirect_uri"
  end
end
