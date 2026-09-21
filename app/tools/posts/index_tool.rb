module Posts
  class IndexTool < MCP::Tool
    tool_name "post-index-tool"
    description "List the last count of Posts entities. The count parameter is an integer and defaults to 10."
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    input_schema(
      properties: {
        count: { type: "integer" }
      }
    )

    def self.call(count: 10, server_context:)
      posts = Post.all
      posts = posts.last(count)

      response = posts.map(&:to_mcp_response).join("\n")
      response = "Nothing was found" unless response.present?

      MCP::Tool::Response.new([ { type: "text", text: response } ])
    rescue StandardError => e
      MCP::Tool::Response.new([ { type: "text", text: "An error occurred, what happened was #{e.message}" } ])
    end
  end
end
