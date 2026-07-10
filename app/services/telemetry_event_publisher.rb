# Publishes one Kafka message per ingested telemetry reading so downstream
# consumers (dashboards, alerting, long-term analytics storage) can react to
# vitals in near real time without coupling to the ingestion API.
class TelemetryEventPublisher
  TOPIC = ENV.fetch("KAFKA_TELEMETRY_TOPIC", "telemetry.readings")

  def self.publish(reading)
    new.publish(reading)
  end

  def initialize(producer: KafkaClient.producer)
    @producer = producer
  end

  def publish(reading)
    @producer.produce(event_payload(reading), topic: TOPIC, key: reading.sensor_id)
    @producer.deliver_messages
    true
  rescue Kafka::Error => e
    # The reading is already durably persisted in MySQL at this point, so a
    # broker outage should not fail the ingestion request. Log loudly instead
    # — a production system would additionally push this into a retry/outbox
    # table so the event isn't silently lost.
    Rails.logger.error(
      "[TelemetryEventPublisher] failed to publish reading=#{reading.id} sensor=#{reading.sensor_id}: " \
      "#{e.class}: #{e.message}"
    )
    false
  end

  private

  def event_payload(reading)
    {
      id: reading.id,
      sensor_id: reading.sensor_id,
      timestamp: reading.recorded_at.iso8601,
      heart_rate: reading.heart_rate,
      temperature: reading.temperature.to_f,
      ingested_at: reading.created_at.iso8601
    }.to_json
  end
end
