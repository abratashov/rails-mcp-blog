module Comments
  class CreateTool < MCP::Tool
    tool_name "comment-create-tool"
    description "Create a new Comment entity"
    annotations(
      read_only_hint: false,
      destructive_hint: false,
      idempotent_hint: false,
      open_world_hint: false
    )

    input_schema(
      properties: {
        post_id: { type: "integer" },
        content: { type: "string" }
      },
      required: [ "post_id" ]
    )

    def self.call(post_id: nil, content: nil, server_context:)
      comment = Comment.new(
        post_id: post_id,
        content: content
      )

      if comment.save
        MCP::Tool::Response.new([ { type: "text", text: "Created #{comment.to_mcp_response}" } ])
      else
        MCP::Tool::Response.new([ { type: "text", text: "Comment was not created due to the following errors: #{comment.errors.full_messages.join(', ')}" } ])
      end
    rescue StandardError => e
      MCP::Tool::Response.new([ { type: "text", text: "An error occurred, what happened was #{e.message}" } ])
    end
  end
end
