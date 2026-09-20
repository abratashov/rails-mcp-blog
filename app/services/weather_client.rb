# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class WeatherClient
  GEOCODING_URL = "https://geocoding-api.open-meteo.com/v1/search"
  WEATHER_URL = "https://api.open-meteo.com/v1/forecast"

  Weather = Data.define(
    :location_name,
    :country,
    :temperature,
    :feelslike,
    :description
  )

  attr_reader :weather

  def get_weather_for(location)
    coordinates = geocode(location)

    response = get(
      WEATHER_URL,
      latitude: coordinates.fetch("latitude"),
      longitude: coordinates.fetch("longitude"),
      current: "temperature_2m,apparent_temperature,weather_code",
      temperature_unit: "celsius"
    )

    @weather = build_weather(coordinates, response)

    response
  end

  private

  def geocode(location)
    response = get(
      GEOCODING_URL,
      name: location,
      count: 1,
      language: "en",
      format: "json"
    )

    result = response.fetch("results", []).first
    raise "Location not found: #{location}" unless result

    result
  end

  def build_weather(location, response)
    current = response.fetch("current")

    Weather.new(
      location_name: location.fetch("name"),
      country: location.fetch("country"),
      temperature: current.fetch("temperature_2m"),
      feelslike: current.fetch("apparent_temperature"),
      description: weather_description(current.fetch("weather_code"))
    )
  end

  def get(url, **params)
    uri = URI(url)
    uri.query = URI.encode_www_form(params)

    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Weather API returned #{response.code}: #{response.body}"
    end

    JSON.parse(response.body)
  end

  def weather_description(code)
    {
      0 => "Clear sky",
      1 => "Mainly clear",
      2 => "Partly cloudy",
      3 => "Overcast",
      45 => "Fog",
      48 => "Depositing rime fog",
      51 => "Light drizzle",
      53 => "Moderate drizzle",
      55 => "Dense drizzle",
      56 => "Light freezing drizzle",
      57 => "Dense freezing drizzle",
      61 => "Slight rain",
      63 => "Moderate rain",
      65 => "Heavy rain",
      66 => "Light freezing rain",
      67 => "Heavy freezing rain",
      71 => "Slight snow fall",
      73 => "Moderate snow fall",
      75 => "Heavy snow fall",
      77 => "Snow grains",
      80 => "Slight rain showers",
      81 => "Moderate rain showers",
      82 => "Violent rain showers",
      85 => "Slight snow showers",
      86 => "Heavy snow showers",
      95 => "Thunderstorm",
      96 => "Thunderstorm with slight hail",
      99 => "Thunderstorm with heavy hail"
    }.fetch(code, "Unknown")
  end
end
