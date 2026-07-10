require "rails_helper"

RSpec.describe TelemetryEventPublisher do
  let(:reading) { create(:telemetry_reading, sensor_id: "sensor-01") }
  let(:fake_producer) { instance_double(Kafka::Producer, produce: nil, deliver_messages: nil) }

  it "publishes the reading as a JSON message keyed by sensor_id" do
    publisher = described_class.new(producer: fake_producer)

    publisher.publish(reading)

    expect(fake_producer).to have_received(:produce).with(
      a_string_including(reading.sensor_id),
      topic: "telemetry.readings",
      key: reading.sensor_id
    )
    expect(fake_producer).to have_received(:deliver_messages)
  end

  it "logs and returns false instead of raising when Kafka is unreachable" do
    allow(fake_producer).to receive(:deliver_messages).and_raise(Kafka::DeliveryFailed.new("boom", []))
    publisher = described_class.new(producer: fake_producer)

    expect(publisher.publish(reading)).to eq(false)
  end
end
