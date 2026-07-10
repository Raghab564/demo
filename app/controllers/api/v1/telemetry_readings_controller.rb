module Api
  module V1
    class TelemetryReadingsController < ApplicationController
      include TokenAuthenticatable

      # Requests arrive as a flat JSON body (sensor_id/timestamp/heart_rate/
      # temperature), not wrapped under a model key.
      wrap_parameters false

      def create
        reading = TelemetryReading.new(reading_params)

        unless reading.save
          return render json: { error: "validation_failed", messages: reading.errors.full_messages },
                         status: :unprocessable_content
        end

        TelemetryEventPublisher.publish(reading)

        render json: serialize(reading), status: :created
      end

      private

      def reading_params
        permitted = params.permit(:sensor_id, :timestamp, :heart_rate, :temperature)
        {
          sensor_id: permitted[:sensor_id],
          recorded_at: permitted[:timestamp],
          heart_rate: permitted[:heart_rate],
          temperature: permitted[:temperature]
        }
      end

      def serialize(reading)
        {
          id: reading.id,
          sensor_id: reading.sensor_id,
          timestamp: reading.recorded_at.iso8601,
          heart_rate: reading.heart_rate,
          temperature: reading.temperature.to_f,
          ingested_at: reading.created_at.iso8601
        }
      end
    end
  end
end
