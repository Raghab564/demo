FactoryBot.define do
  factory :telemetry_reading do
    sequence(:sensor_id) { |n| "sensor-#{n}" }
    recorded_at { Time.current }
    heart_rate { 72 }
    temperature { 36.8 }
  end
end
