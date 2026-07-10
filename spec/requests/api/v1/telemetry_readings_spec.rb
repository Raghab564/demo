require "rails_helper"

RSpec.describe "Api::V1::TelemetryReadings", type: :request do
  let(:valid_payload) do
    {
      sensor_id: "sensor-01",
      timestamp: "2026-07-08T12:00:00Z",
      heart_rate: 78,
      temperature: 36.9
    }
  end
  let(:json_headers) { { "Content-Type" => "application/json" } }

  describe "POST /api/v1/telemetry_readings" do
    context "without an Authorization header" do
      it "returns 401 Unauthorized" do
        post "/api/v1/telemetry_readings", params: valid_payload.to_json, headers: json_headers

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an invalid token" do
      it "returns 401 Unauthorized" do
        post "/api/v1/telemetry_readings",
          params: valid_payload.to_json,
          headers: json_headers.merge("Authorization" => "Bearer not-a-real-token")

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a valid token and payload" do
      before { allow(TelemetryEventPublisher).to receive(:publish).and_return(true) }

      it "creates a telemetry reading and returns 201" do
        expect {
          post "/api/v1/telemetry_readings",
            params: valid_payload.to_json,
            headers: json_headers.merge(auth_headers)
        }.to change(TelemetryReading, :count).by(1)

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["sensor_id"]).to eq("sensor-01")
        expect(body["heart_rate"]).to eq(78)
      end

      it "publishes a Kafka event for the ingested reading" do
        post "/api/v1/telemetry_readings",
          params: valid_payload.to_json,
          headers: json_headers.merge(auth_headers)

        expect(TelemetryEventPublisher).to have_received(:publish).with(an_instance_of(TelemetryReading))
      end
    end

    context "with an invalid payload" do
      it "returns 422 with validation errors" do
        post "/api/v1/telemetry_readings",
          params: valid_payload.merge(heart_rate: -5).to_json,
          headers: json_headers.merge(auth_headers)

        expect(response).to have_http_status(:unprocessable_content)
        expect(JSON.parse(response.body)["error"]).to eq("validation_failed")
      end
    end

    context "with a reading that was already ingested" do
      it "returns 422 rather than creating a duplicate row" do
        create(:telemetry_reading, sensor_id: "sensor-01", recorded_at: "2026-07-08T12:00:00Z")

        post "/api/v1/telemetry_readings",
          params: valid_payload.to_json,
          headers: json_headers.merge(auth_headers)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
