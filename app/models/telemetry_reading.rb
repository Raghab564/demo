class TelemetryReading < ApplicationRecord
  # A duplicate (sensor_id, recorded_at) pair means the same reading was
  # retransmitted (e.g. a sensor retrying after a dropped ack) — treat it as
  # a conflict rather than silently double-counting a vital sign.
  validates :sensor_id, presence: true
  validates :recorded_at, presence: true
  validates :heart_rate, presence: true,
    numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 300 }
  validates :temperature, presence: true,
    numericality: { greater_than_or_equal_to: 20.0, less_than_or_equal_to: 45.0 }
  validates :sensor_id, uniqueness: { scope: :recorded_at }
end
