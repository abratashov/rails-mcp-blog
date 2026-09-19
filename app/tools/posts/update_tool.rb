module Posts
  class UpdateTool < MCP::Tool
    tool_name "post-update-tool"
    description "Update a Post entity of a given ID"
    annotations(
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    input_schema(
      properties: {
        id: { type: "integer" },
        title: { type: "string" },
        body: { type: "string" },
      },
      required: [ "id" ]
    )

    def self.call(id:, title: MCP::EmptyProperty, body: MCP::EmptyProperty, server_context:)
      post = Post.find(id)

      post.title = title unless title == MCP::EmptyProperty
      post.body = body unless body == MCP::EmptyProperty

      if post.save
        MCP::Tool::Response.new([ { type: "text", text: "Updated #{post.to_mcp_response}" } ])
      else
        MCP::Tool::Response.new([ { type: "text", text: "Post of id = #{id} was not updated due to the following errors: #{post.errors.full_messages.join(', ')}" } ])
      end
    rescue ActiveRecord::RecordNotFound
      MCP::Tool::Response.new([ { type: "text", text: "Post of id = #{id} was not found" } ])
    rescue StandardError => e
      MCP::Tool::Response.new([ { type: "text", text: "An error occurred, what happened was #{e.message}" } ])
    end
  end
end
