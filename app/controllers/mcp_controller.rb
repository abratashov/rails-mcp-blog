# frozen_string_literal: true

class McpController < ActionController::API
  before_action -> { doorkeeper_authorize! :public, :read, :write }
  before_action :validate_token_audience!

  def handle
    # if params[:method] == "notifications/initialized"
    #   head(:accepted) and return
    # end

    render(json: mcp_server.handle_json(request.body.read))
  end

  private

  def validate_token_audience!
    return true unless doorkeeper_token

    return if doorkeeper_token.resource == "#{request.base_url}/mcp"

    render json: {
      error: "invalid_token",
      error_description: "Token not valid for this resource"
    }, status: :unauthorized
  end

  def mcp_server
    MCP::Server.new(
      name: "rails_mcp_server",
      version: "1.0.0",
      tools: MCP::Tool.descendants,
      prompts: MCP::Prompt.descendants,
      server_context: { token: doorkeeper_token, user_id: doorkeeper_token.resource_owner_id }
    )
  end
end
