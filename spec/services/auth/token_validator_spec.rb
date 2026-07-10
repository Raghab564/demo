require "rails_helper"

RSpec.describe Auth::TokenValidator do
  let(:sensor_id) { "sensor-42" }

  it "accepts a token minted by the mock issuer" do
    token = Auth::MockTokenIssuer.call(sensor_id: sensor_id)

    payload = described_class.new(token).call

    expect(payload["sub"]).to eq(sensor_id)
  end

  it "rejects an expired token" do
    token = Auth::MockTokenIssuer.call(sensor_id: sensor_id, ttl: -10)

    expect { described_class.new(token).call }
      .to raise_error(Auth::TokenValidator::AuthenticationError, /expired/)
  end

  let(:configured_secret) { ENV.fetch("OIDC_SHARED_SECRET", "development-only-insecure-secret") }
  let(:configured_issuer) { ENV.fetch("OIDC_ISSUER", "https://mock-idp.demo.local/") }
  let(:configured_audience) { ENV.fetch("OIDC_AUDIENCE", "demo-api") }

  it "rejects a token signed with the wrong secret" do
    bad_token = JWT.encode(
      { iss: configured_issuer, aud: configured_audience, sub: sensor_id, exp: Time.now.to_i + 3600 },
      "wrong-secret",
      "HS256"
    )

    expect { described_class.new(bad_token).call }
      .to raise_error(Auth::TokenValidator::AuthenticationError)
  end

  it "rejects a token with an untrusted issuer" do
    bad_token = JWT.encode(
      { iss: "https://evil.example.com/", aud: configured_audience, sub: sensor_id, exp: Time.now.to_i + 3600 },
      configured_secret,
      "HS256"
    )

    expect { described_class.new(bad_token).call }
      .to raise_error(Auth::TokenValidator::AuthenticationError, /issuer/)
  end

  it "rejects a malformed token" do
    expect { described_class.new("not-a-jwt").call }
      .to raise_error(Auth::TokenValidator::AuthenticationError)
  end
end
