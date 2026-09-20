# frozen_string_literal: true

class CheckWeatherTool < MCP::Tool
  tool_name "check-weather-tool"
  description "Get current weather information for a specified location using a Weather API"

  input_schema(
    properties: {
      location: { type: "string", description: "Location to get weather for (city, country)" }
    },
    required: [ "location" ]
  )

  def self.call(location:, server_context:)
    client = WeatherClient.new
    client.get_weather_for(location)

    weather = client.weather

    weather_text = <<~TEXT
      Weather in #{weather.location_name}, #{weather.country}:
      Temperature: #{weather.temperature}°C (feels like #{weather.feelslike}°C)
      Condition: #{weather.description}
    TEXT

    MCP::Tool::Response.new([
      { type: "text", text: weather_text.strip }
    ])
  rescue StandardError => e
    MCP::Tool::Response.new([
      { type: "text", text: "An error occurred: #{e.message}" }
    ])
  end
end
