require "net/http"
require "json"

module Embeddings
  class OpenAICompatibleProvider < Provider
    RETRYABLE_STATUS_CODES = [ 408, 429, 500, 502, 503, 504 ].freeze

    def initialize(configuration:, http_factory: Net::HTTP, sleeper: ->(seconds) { Kernel.sleep(seconds) })
      @configuration = configuration
      @http_factory = http_factory
      @sleeper = sleeper
    end

    def embed(texts)
      raise Error, "Embedding input batch must not be empty" if texts.empty?

      @configuration.validate_provider!
      request = Net::HTTP::Post.new(endpoint)
      request["Authorization"] = "Bearer #{@configuration.api_key}"
      request["Content-Type"] = "application/json"
      payload = {
        input: texts,
        model: @configuration.model
      }
      payload[:dimensions] = @configuration.dimensions if @configuration.send_dimensions
      request.body = JSON.generate(payload)

      response = perform_with_retries(request)
      parse_response(response, texts.length)
    end

    private

    def endpoint
      URI.join("#{@configuration.api_base_url.chomp("/")}/", "embeddings")
    end

    def perform_with_retries(request)
      attempts = 0

      loop do
        begin
          uri = endpoint
          http = @http_factory.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.open_timeout = @configuration.open_timeout
          http.read_timeout = @configuration.read_timeout
          http.write_timeout = @configuration.write_timeout if http.respond_to?(:write_timeout=)
          response = http.start { |connection| connection.request(request) }
        rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Net::HTTPError,
            SocketError, IOError, SystemCallError => error
          raise Error, "Embedding API request failed: #{error.class}" if attempts >= @configuration.retry_count

          attempts += 1
          @sleeper.call([ 0.5 * (2**(attempts - 1)), 30 ].min)
          next
        rescue OpenSSL::SSL::SSLError => error
          raise Error, "Embedding API TLS connection failed: #{error.class}"
        end

        if RETRYABLE_STATUS_CODES.include?(response.code.to_i)
          raise Error, "Embedding API returned HTTP #{response.code}: #{error_detail(response)}" if attempts >= @configuration.retry_count

          delay = retry_after(response) || 0.5 * (2**attempts)
          attempts += 1
          @sleeper.call([ [ delay, 0 ].max, 30 ].min)
          next
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "Embedding API returned HTTP #{response.code}: #{error_detail(response)}"
        end

        return response
      end
    end

    def parse_response(response, expected_count)
      payload = JSON.parse(response.body)
      data = payload.fetch("data")
      raise Error, "Embedding API returned an invalid data collection" unless data.is_a?(Array)
      raise Error, "Embedding API returned #{data.length} items for #{expected_count} inputs" unless data.length == expected_count

      indexed = data.map do |item|
        index = Integer(item.fetch("index"))
        vector = item.fetch("embedding")
        raise Error, "Embedding API returned an invalid vector" unless vector.is_a?(Array)
        raise Error, "Embedding API returned a non-numeric vector value" unless vector.all? { |value| value.is_a?(Numeric) && value.to_f.finite? }

        [ index, vector.map(&:to_f) ]
      end
      raise Error, "Embedding API returned duplicate or missing indexes" unless indexed.map(&:first).sort == (0...expected_count).to_a

      indexed.sort_by(&:first).map(&:last)
    rescue JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError => error
      raise Error, "Invalid embedding API response: #{error.message}"
    end

    def error_detail(response)
      payload = JSON.parse(response.body)
      payload.dig("error", "message").presence || response.body.to_s.truncate(500)
    rescue JSON::ParserError, TypeError, NoMethodError
      response.body.to_s.truncate(500)
    end

    def retry_after(response)
      value = response["Retry-After"]
      Float(value) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
