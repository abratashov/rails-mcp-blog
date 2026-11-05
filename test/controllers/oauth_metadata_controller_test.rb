require "test_helper"

class OauthMetadataControllerTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  test "returns protected resource metadata for the MCP endpoint" do
    get "/.well-known/oauth-protected-resource/mcp"

    assert_response :success
    assert_equal "http://www.example.com/mcp", response.parsed_body.fetch("resource")
    assert_equal [ "http://www.example.com" ], response.parsed_body.fetch("authorization_servers")
  end

  test "returns authorization server metadata" do
    get "/.well-known/oauth-authorization-server/mcp"

    assert_response :success
    metadata = response.parsed_body
    assert_equal "http://www.example.com", metadata.fetch("issuer")
    assert_equal "http://www.example.com/oauth/authorize", metadata.fetch("authorization_endpoint")
    assert_equal "http://www.example.com/oauth/token", metadata.fetch("token_endpoint")
    assert_equal [ "S256" ], metadata.fetch("code_challenge_methods_supported")
    assert_equal "http://www.example.com/oauth/register", metadata.fetch("registration_endpoint")
  end
end
