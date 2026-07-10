module Auth
  # Validates a mock OAuth2 / OIDC bearer token.
  #
  # In production this would fetch the issuer's JWKS (from
  # `<issuer>/.well-known/openid-configuration`) and verify an RS256-signed
  # ID/access token against the matching public key. For this take-home
  # exercise the identity provider is mocked: tokens are HS256-signed with a
  # shared secret (Auth::MockTokenIssuer), which lets the middleware exercise
  # the real validation surface (issuer, audience, expiry, signature) without
  # standing up a full IdP.
  class TokenValidator
    class AuthenticationError < StandardError; end

    ALGORITHM = "HS256".freeze

    def initialize(token)
      @token = token
    end

    def call
      payload, _header = JWT.decode(
        @token,
        secret,
        true,
        algorithm: ALGORITHM,
        iss: issuer,
        verify_iss: true,
        aud: audience,
        verify_aud: true,
        verify_expiration: true
      )
      payload
    rescue JWT::ExpiredSignature
      raise AuthenticationError, "Token has expired"
    rescue JWT::InvalidIssuerError
      raise AuthenticationError, "Token issuer is not trusted"
    rescue JWT::InvalidAudError
      raise AuthenticationError, "Token audience is invalid"
    rescue JWT::DecodeError => e
      raise AuthenticationError, "Invalid token: #{e.message}"
    end

    private

    def secret
      ENV.fetch("OIDC_SHARED_SECRET", "development-only-insecure-secret")
    end

    def issuer
      ENV.fetch("OIDC_ISSUER", "https://mock-idp.demo.local/")
    end

    def audience
      ENV.fetch("OIDC_AUDIENCE", "demo-api")
    end
  end
end
