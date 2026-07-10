module AuthHelpers
  def bearer_token_for(sensor_id: "sensor-01", ttl: 3600)
    Auth::MockTokenIssuer.call(sensor_id: sensor_id, ttl: ttl)
  end

  def auth_headers(sensor_id: "sensor-01")
    { "Authorization" => "Bearer #{bearer_token_for(sensor_id: sensor_id)}" }
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
