module TokenAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request!
  end

  private

  def authenticate_request!
    token_payload = Auth::TokenValidator.new(bearer_token).call
    @current_token_payload = token_payload
  rescue Auth::TokenValidator::AuthenticationError => e
    render json: { error: "unauthorized", message: e.message }, status: :unauthorized
  end

  def bearer_token
    header = request.headers["Authorization"]
    scheme, token = header.to_s.split(" ", 2)

    unless scheme == "Bearer" && token.present?
      raise Auth::TokenValidator::AuthenticationError, "Missing or malformed Authorization header"
    end

    token
  end

  # The subject (sensor/device ID) claim of the validated token, if a
  # controller needs to know which caller made the request.
  def current_sensor_id
    @current_token_payload && @current_token_payload["sub"]
  end
end
