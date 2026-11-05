require "test_helper"

class CheckWeatherToolTest < ActiveSupport::TestCase
  test "returns current weather from mocked geocoding and forecast APIs" do
    stub_request(:get, WeatherClient::GEOCODING_URL)
      .with(query: hash_including("name" => "Kyiv"))
      .to_return(
        body: { results: [ { name: "Kyiv", country: "Ukraine", latitude: 50.45, longitude: 30.52 } ] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    stub_request(:get, WeatherClient::WEATHER_URL)
      .with(query: hash_including("latitude" => "50.45", "longitude" => "30.52"))
      .to_return(
        body: {
          current: { temperature_2m: 12, apparent_temperature: 10, weather_code: 0 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    response = CheckWeatherTool.call(location: "Kyiv", server_context: {})

    assert_includes response.content.first.fetch(:text), "Weather in Kyiv, Ukraine"
    assert_includes response.content.first.fetch(:text), "Condition: Clear sky"
  end

  test "returns an error message when the weather lookup fails" do
    stub_request(:get, WeatherClient::GEOCODING_URL)
      .with(query: hash_including("name" => "Nowhere"))
      .to_return(body: '{"results":[]}')

    response = CheckWeatherTool.call(location: "Nowhere", server_context: {})

    assert_includes response.content.first.fetch(:text), "An error occurred: Location not found: Nowhere"
  end
end
