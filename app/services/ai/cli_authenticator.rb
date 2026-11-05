# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "uri"
require "webrick"

module AI
  class CLIAuthenticator
    DEFAULT_CALLBACK_PORT = 9876
    CALLBACK_PATH = "/oauth/callback"

    DEFAULT_AUTHORIZATION_URL = "http://localhost:3000/oauth/authorize"
    DEFAULT_TOKEN_URL = "http://localhost:3000/oauth/token"

    def initialize(
      client_id:,
      authorization_url: ENV.fetch(
        "MCP_OAUTH_AUTHORIZATION_URL",
        DEFAULT_AUTHORIZATION_URL
      ),
      token_url: ENV.fetch(
        "MCP_OAUTH_TOKEN_URL",
        DEFAULT_TOKEN_URL
      ),
      scope: ENV.fetch("MCP_OAUTH_SCOPE", "public"),
      port: ENV.fetch(
        "MCP_OAUTH_CALLBACK_PORT",
        DEFAULT_CALLBACK_PORT
      ).to_i
    )
      @client_id = client_id
      @authorization_url = authorization_url
      @token_url = token_url
      @scope = scope
      @port = port
    end

    def authenticate
      code_verifier = generate_code_verifier
      code_challenge = generate_code_challenge(code_verifier)
      redirect_uri = callback_url

      authorization_url = build_authorization_url(
        redirect_uri: redirect_uri,
        code_challenge: code_challenge
      )

      callback_server, callback_thread, callback =
        start_callback_server

      puts
      puts "Opening browser for authentication..."
      puts
      puts authorization_url
      puts
      puts "Waiting for authentication..."
      puts

      open_browser(authorization_url)

      result = callback.pop

      if result[:error]
        message = result[:error]

        if result[:error_description]
          message += ": #{result[:error_description]}"
        end

        raise "OAuth authentication failed: #{message}"
      end

      access_token = exchange_code_for_token(
        code: result.fetch(:code),
        code_verifier: code_verifier,
        redirect_uri: redirect_uri
      )

      puts
      puts "Authentication successful."
      puts

      access_token
    ensure
      callback_server&.shutdown
      callback_thread&.join
    end

    private

    def generate_code_verifier
      SecureRandom.urlsafe_base64(64)
    end

    def generate_code_challenge(code_verifier)
      digest = Digest::SHA256.digest(code_verifier)

      Base64.urlsafe_encode64(
        digest,
        padding: false
      )
    end

    def callback_url
      "http://127.0.0.1:#{@port}#{CALLBACK_PATH}"
    end

    def build_authorization_url(
      redirect_uri:,
      code_challenge:
    )
      uri = URI.parse(@authorization_url)

      params = {
        response_type: "code",
        client_id: @client_id,
        redirect_uri: redirect_uri,
        scope: @scope,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      }

      uri.query = URI.encode_www_form(params)

      uri.to_s
    end

    def start_callback_server
      server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: "127.0.0.1",
        AccessLog: [],
        Logger: WEBrick::Log.new(File::NULL)
      )

      callback = Queue.new

      server.mount_proc(CALLBACK_PATH) do |request, response|
        if request.query["error"]
          callback << {
            error: request.query["error"],
            error_description: request.query["error_description"]
          }

          response.status = 400
          response["Content-Type"] = "text/html; charset=utf-8"
          response.body = <<~HTML
            <!DOCTYPE html>
            <html>
              <body>
                <h1>Authentication failed</h1>
                <p>You can close this window.</p>
              </body>
            </html>
          HTML
        else
          callback << {
            code: request.query.fetch("code")
          }

          response.status = 200
          response["Content-Type"] = "text/html; charset=utf-8"
          response.body = <<~HTML
            <!DOCTYPE html>
            <html>
              <body>
                <h1>Authentication successful</h1>
                <p>You can close this window and return to the terminal.</p>
              </body>
            </html>
          HTML
        end
      end

      thread = Thread.new do
        server.start
      end

      # Return both objects so authenticate can wait for the callback.
      [server, thread, callback]
    end

    # def handle_oauth_error(request, response)
    #   @oauth_error = request.query["error"]
    #   @oauth_error_description = request.query["error_description"]

    #   response.status = 400
    #   response["Content-Type"] = "text/html; charset=utf-8"
    #   response.body = <<~HTML
    #     <!DOCTYPE html>
    #     <html>
    #       <head>
    #         <meta charset="UTF-8">
    #         <title>Authentication failed</title>
    #       </head>
    #       <body>
    #         <h1>Authentication failed</h1>
    #         <p>You can close this window and return to the terminal.</p>
    #       </body>
    #     </html>
    #   HTML
    # end

    # def handle_oauth_success(request, response)
    #   @authorization_code = request.query["code"]

    #   response.status = 200
    #   response["Content-Type"] = "text/html; charset=utf-8"
    #   response.body = <<~HTML
    #     <!DOCTYPE html>
    #     <html>
    #       <head>
    #         <meta charset="UTF-8">
    #         <title>Authentication successful</title>
    #       </head>
    #       <body>
    #         <h1>Authentication successful</h1>
    #         <p>You can close this window and return to the terminal.</p>
    #       </body>
    #     </html>
    #   HTML
    # end

    def exchange_code_for_token(
      code:,
      code_verifier:,
      redirect_uri:
    )
      uri = URI.parse(@token_url)

      params = {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri,
        client_id: @client_id,
        code_verifier: code_verifier
      }

      request = Net::HTTP::Post.new(uri)

      request["Content-Type"] =
        "application/x-www-form-urlencoded"

      request.body = URI.encode_www_form(params)

      response = Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https"
      ) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise <<~ERROR
          OAuth token request failed.

          HTTP status: #{response.code}

          Response:
          #{response.body}
        ERROR
      end

      body = JSON.parse(response.body)

      unless body["access_token"]
        raise(
          "OAuth response does not contain an access_token: " \
          "#{body.inspect}"
        )
      end

      body["access_token"]
    rescue JSON::ParserError => e
      raise(
        "OAuth token response contains invalid JSON: #{e.message}\n" \
        "Response:\n#{response&.body}"
      )
    end

    def open_browser(url)
      command =
        case RUBY_PLATFORM
        when /linux/
          ["xdg-open", url]
        when /darwin/
          ["open", url]
        when /mswin|mingw|cygwin/
          ["start", "", url]
        end

      return false unless command

      system(*command)
    end
  end
end
