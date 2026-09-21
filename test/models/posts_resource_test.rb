require "test_helper"
require "json"

class PostsResourceTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  setup do
    @post = Post.create!(title: "Test post", body: "Test body")
    Comment.create!(post: @post, content: "Test comment")
  end

  test "reads a post and its comments as markdown" do
    contents = Posts::Resource.contents(id: @post.id)

    assert_equal "posts://#{@post.id}", contents.uri
    assert_includes contents.text, "# Test post"
    assert_includes contents.text, "Test comment"
  end

  test "reads a post through the MCP server resource template" do
    server = MCP::Server.new(
      name: "rails_mcp_server",
      version: "1.0.0",
      resources: MCP::Resource.descendants,
      resource_templates: MCP::ResourceTemplate.descendants
    )

    response = JSON.parse(server.handle_json(
      {
        jsonrpc: "2.0",
        id: 1,
        method: "resources/read",
        params: { uri: "posts://#{@post.id}" }
      }.to_json
    ))

    assert_equal "posts://#{@post.id}", response.dig("result", "contents", 0, "uri")
    assert_includes response.dig("result", "contents", 0, "text"), "# Test post"
    assert_nil response["error"]
  end
end
