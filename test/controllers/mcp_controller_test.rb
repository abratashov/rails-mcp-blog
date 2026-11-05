require "test_helper"

class McpControllerTest < ActionController::TestCase
  self.fixture_table_names = []

  test "excludes unloaded subclasses after a Rails reload" do
    old_class = MCP.const_set(:ReloadedTestTool, Class.new(MCP::Tool))
    Object.const_get("MCP::ReloadedTestTool").tool_name("reloaded-test-tool")

    MCP.send(:remove_const, :ReloadedTestTool)
    current_class = MCP.const_set(:ReloadedTestTool, Class.new(MCP::Tool))
    current_class.tool_name("reloaded-test-tool")

    subclasses = @controller.send(:current_descendants, MCP::Tool)

    assert_includes subclasses, current_class
    assert_not_includes subclasses, old_class
  ensure
    MCP.send(:remove_const, :ReloadedTestTool) if MCP.const_defined?(:ReloadedTestTool, false)
  end
end

class McpControllerIntegrationTest < ActionDispatch::IntegrationTest
  self.fixture_table_names = []

  setup do
    @user = User.create!(email: "mcp-integration@example.test", password: "password")
    @application = Doorkeeper::Application.create!(
      name: "MCP integration test",
      redirect_uri: "https://example.test/callback",
      scopes: "public read write"
    )
    @access_token = Doorkeeper::AccessToken.create!(
      application: @application,
      resource_owner_id: @user.id,
      scopes: "public read write"
    )
  end

  test "requires an access token for MCP requests" do
    post "/mcp",
      params: mcp_request("tools/list").to_json,
      headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :unauthorized
  end

  test "an authenticated MCP client lists and calls a tool over HTTP" do
    Post.create!(title: "MCP integration post", body: "Created through the test database")

    initialize_response = mcp_post(
      "initialize",
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: { name: "test-client", version: "1.0.0" }
    )

    assert_response :success
    assert_equal "2025-03-26", initialize_response.dig("result", "protocolVersion")

    post "/mcp",
      params: mcp_notification("notifications/initialized").to_json,
      headers: mcp_headers

    assert_response :accepted
    assert_empty response.body

    list_response = mcp_post("tools/list")

    assert_response :success
    tools = list_response.dig("result", "tools")
    assert_includes tools.map { |tool| tool.fetch("name") }, "post-index-tool"

    call_response = mcp_post(
      "tools/call",
      name: "post-index-tool",
      arguments: { count: 1 }
    )

    assert_response :success
    assert_equal "2.0", call_response.fetch("jsonrpc")
    assert_includes call_response.dig("result", "content", 0, "text"), "MCP integration post"
    assert_nil call_response["error"]
  end

  private

  def mcp_post(method, **params)
    post "/mcp",
      params: mcp_request(method, **params).to_json,
      headers: mcp_headers

    response.parsed_body
  end

  def mcp_headers
    {
      "CONTENT_TYPE" => "application/json",
      "HTTP_AUTHORIZATION" => "Bearer #{@access_token.token}"
    }
  end

  def mcp_request(method, **params)
    {
      jsonrpc: "2.0",
      id: SecureRandom.uuid,
      method: method,
      params: params
    }
  end

  def mcp_notification(method, **params)
    {
      jsonrpc: "2.0",
      method: method,
      params: params
    }
  end
end
