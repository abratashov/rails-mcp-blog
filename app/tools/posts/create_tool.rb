module Posts
  class CreateTool < MCP::Tool
    tool_name "post-create-tool"
    description "Create a new Post entity"
    annotations(
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: false,
      open_world_hint: false
    )

    input_schema(
      properties: {
        title: { type: "string" },
        body: { type: "string" }
      }
    )

    def self.call(title: nil, body: nil, server_context:)
      post = Post.new(
        title: title,
        body: body
      )

      if post.save
        MCP::Tool::Response.new([ { type: "text", text: "Created #{post.to_mcp_response}" } ])
      else
        MCP::Tool::Response.new([ { type: "text", text: "Post was not created due to the following errors: #{post.errors.full_messages.join(', ')}" } ])
      end
    rescue StandardError => e
      MCP::Tool::Response.new([ { type: "text", text: "An error occurred, what happened was #{e.message}" } ])
    end
  end
end
