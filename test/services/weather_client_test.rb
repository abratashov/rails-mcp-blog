require "test_helper"

class WeatherClientTest < ActiveSupport::TestCase
  setup do
    stub_request(:get, WeatherClient::GEOCODING_URL)
      .with(query: { name: "Lviv", count: "1", language: "en", format: "json" })
      .to_return(
        body: {
          results: [
            { name: "Lviv", country: "Ukraine", latitude: 49.84, longitude: 24.03 }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "fetches geocoding and current weather through mocked HTTP responses" do
    stub_request(:get, WeatherClient::WEATHER_URL)
      .with(query: hash_including("latitude" => "49.84", "longitude" => "24.03"))
      .to_return(
        body: {
          current: {
            temperature_2m: 10.5,
            apparent_temperature: 8.2,
            weather_code: 3
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    client = WeatherClient.new
    result = client.get_weather_for("Lviv")

    assert_equal 10.5, result.dig("current", "temperature_2m")
    assert_equal "Lviv", client.weather.location_name
    assert_equal "Ukraine", client.weather.country
    assert_equal 8.2, client.weather.feelslike
    assert_equal "Overcast", client.weather.description
  end

  test "reports a missing location" do
    stub_request(:get, WeatherClient::GEOCODING_URL)
      .with(query: hash_including("name" => "Atlantis"))
      .to_return(body: '{"results":[]}', headers: { "Content-Type" => "application/json" })

    error = assert_raises(RuntimeError) { WeatherClient.new.get_weather_for("Atlantis") }

    assert_equal "Location not found: Atlantis", error.message
  end

  test "reports unsuccessful weather API responses" do
    stub_request(:get, WeatherClient::WEATHER_URL)
      .with(query: hash_including("latitude" => "49.84", "longitude" => "24.03"))
      .to_return(status: 503, body: "maintenance")

    error = assert_raises(RuntimeError) { WeatherClient.new.get_weather_for("Lviv") }

    assert_equal "Weather API returned 503: maintenance", error.message
  end

  test "uses unknown for unrecognized weather codes" do
    stub_request(:get, WeatherClient::WEATHER_URL)
      .with(query: hash_including("latitude" => "49.84", "longitude" => "24.03"))
      .to_return(
        body: {
          current: {
            temperature_2m: 1,
            apparent_temperature: 0,
            weather_code: 999
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    client = WeatherClient.new
    client.get_weather_for("Lviv")

    assert_equal "Unknown", client.weather.description
  end
end
