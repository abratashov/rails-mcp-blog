Rails.application.routes.draw do
  devise_for :users
  use_doorkeeper

  resources :comments
  resources :posts

  # RFC 7591: Dynamic Client Registration Protocol
  post "/oauth/register", to: "oauth_client_registration#create", as: :oauth_register

  # RFC 9728: Protected Resource Metadata (MCP server as protected resource)
  get "/.well-known/oauth-protected-resource",       to: "oauth_authorization_server_metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp",   to: "oauth_authorization_server_metadata#protected_resource"

  # RFC 8414: Authorization Server Metadata (OAuth server endpoints)
  get "/.well-known/oauth-authorization-server",     to: "oauth_authorization_server_metadata#authorization_server"
  get "/.well-known/oauth-authorization-server/mcp", to: "oauth_authorization_server_metadata#authorization_server"

  # Model Context Protocol
  post "/mcp", to: "mcp#handle"
  get  "/mcp", to: "mcp#handle"
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "posts#index"
end
