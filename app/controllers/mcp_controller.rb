# frozen_string_literal: true

class McpController < ActionController::API
  before_action -> { doorkeeper_authorize! :public, :read, :write }

  # Resource validation is optional; enable when using OAuth Resource Indicators (RFC 8707)
  # before_action :validate_token_audience!

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
      tools: current_descendants(MCP::Tool),
      prompts: current_descendants(MCP::Prompt),
      resources: current_descendants(MCP::Resource),
      resource_templates: current_descendants(MCP::ResourceTemplate),
      server_context: { token: doorkeeper_token, user_id: doorkeeper_token.resource_owner_id }
    )
  end

  def current_descendants(base_class)
    base_class.descendants.select do |subclass|
      subclass.name&.safe_constantize == subclass
    end
  end
end
