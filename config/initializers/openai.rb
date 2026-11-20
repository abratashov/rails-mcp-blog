OpenAI.configure do |config|
  config.access_token = ENV.fetch("LLM_ACCESS_TOKEN")
end
