require "rails_helper"

RSpec.describe TelemetryReading, type: :model do
  subject { build(:telemetry_reading) }

  it { is_expected.to be_valid }

  it "requires a sensor_id" do
    subject.sensor_id = nil
    expect(subject).not_to be_valid
  end

  it "requires recorded_at" do
    subject.recorded_at = nil
    expect(subject).not_to be_valid
  end

  it "rejects a heart rate outside the plausible human range" do
    subject.heart_rate = 301
    expect(subject).not_to be_valid
  end

  it "rejects a temperature outside the plausible human range" do
    subject.temperature = 10.0
    expect(subject).not_to be_valid
  end

  it "rejects duplicate sensor_id + recorded_at pairs" do
    create(:telemetry_reading, sensor_id: "dup-sensor", recorded_at: "2026-01-01T00:00:00Z")
    duplicate = build(:telemetry_reading, sensor_id: "dup-sensor", recorded_at: "2026-01-01T00:00:00Z")

    expect(duplicate).not_to be_valid
  end
end
