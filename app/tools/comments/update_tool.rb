module Comments
  class UpdateTool < MCP::Tool
    tool_name "comment-update-tool"
    description "Update a Comment entity of a given ID"
    annotations(
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    input_schema(
      properties: {
        id: { type: "integer" },
        post_id: { type: "integer" },
        content: { type: "string" }
      },
      required: [ "id" ]
    )

    def self.call(id:, post_id: MCP::EmptyProperty, content: MCP::EmptyProperty, server_context:)
      comment = Comment.find(id)

      comment.post_id = post_id unless post_id == MCP::EmptyProperty
      comment.content = content unless content == MCP::EmptyProperty

      if comment.save
        MCP::Tool::Response.new([ { type: "text", text: "Updated #{comment.to_mcp_response}" } ])
      else
        MCP::Tool::Response.new([ { type: "text", text: "Comment of id = #{id} was not updated due to the following errors: #{comment.errors.full_messages.join(', ')}" } ])
      end
    rescue ActiveRecord::RecordNotFound
      MCP::Tool::Response.new([ { type: "text", text: "Comment of id = #{id} was not found" } ])
    rescue StandardError => e
      MCP::Tool::Response.new([ { type: "text", text: "An error occurred, what happened was #{e.message}" } ])
    end
  end
end
