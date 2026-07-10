module Auth
  # Stands in for an OAuth2/OIDC identity provider's token endpoint so the
  # ingestion API can be exercised end-to-end without a real IdP. Wearables
  # would normally obtain this token via the client_credentials grant.
  class MockTokenIssuer
    def self.call(sensor_id:, ttl: 3600)
      new.call(sensor_id: sensor_id, ttl: ttl)
    end

    def call(sensor_id:, ttl: 3600)
      now = Time.now.to_i
      payload = {
        iss: ENV.fetch("OIDC_ISSUER", "https://mock-idp.demo.local/"),
        aud: ENV.fetch("OIDC_AUDIENCE", "demo-api"),
        sub: sensor_id,
        iat: now,
        exp: now + ttl
      }
      JWT.encode(payload, secret, "HS256")
    end

    private

    def secret
      ENV.fetch("OIDC_SHARED_SECRET", "development-only-insecure-secret")
    end
  end
end
