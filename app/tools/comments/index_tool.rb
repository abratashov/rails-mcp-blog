module Comments
  class IndexTool < MCP::Tool
    tool_name "comment-index-tool"
    description "List the last count of Comments entities. The count parameter is an integer and defaults to 10. post_id property may be used to filter by integer identifier of the related Post entity."
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )

    input_schema(
      properties: {
        count: { type: "integer" },
        post_id: { type: "integer" },
      }
    )

    def self.call(count: 10, post_id: nil, server_context:)
      comments = Comment.all
      comments = comments.where(post_id: post_id) if post_id.present? 
      comments = comments.last(count)

      response = comments.map(&:to_mcp_response).join("\n")
      response = "Nothing was found" unless response.present?

      MCP::Tool::Response.new([ { type: "text", text: response } ])
    rescue StandardError => e
      MCP::Tool::Response.new([ { type: "text", text: "An error occurred, what happened was #{e.message}" } ])
    end
  end
end
