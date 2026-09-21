# frozen_string_literal: true

class McpController < ActionController::API
  # Auth only for testing purpose
  # USER_API_KEYS = { "ma9.2z-6vL" => 1, "493ovgHmsi" => 2 }.freeze

  def handle
    render(json: mcp_server.handle_json(request.body.read))
  end

  private

  def mcp_server
    # user_id = USER_API_KEYS [params[:api_key]]
    # head: unauthorized unless user_id

    MCP::Server.new(
      name: "rails_mcp_server",
      version: "1.0.0",
      tools: MCP::Tool.descendants,
      prompts: MCP::Prompt.descendants
      # server_context: { user_id: }
    )
  end
end
