class ApplicationController < ActionController::API
  rescue_from ActionDispatch::Http::Parameters::ParseError do |_exception|
    render json: { error: "bad_request", message: "Malformed JSON payload" }, status: :bad_request
  end
end
