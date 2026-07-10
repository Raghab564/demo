class CreateTelemetryReadings < ActiveRecord::Migration[8.0]
  def change
    create_table :telemetry_readings do |t|
      t.string :sensor_id, null: false
      t.datetime :recorded_at, null: false
      t.integer :heart_rate, null: false
      t.decimal :temperature, precision: 5, scale: 2, null: false

      t.timestamps
    end

    add_index :telemetry_readings, :sensor_id
    add_index :telemetry_readings, [ :sensor_id, :recorded_at ], unique: true,
      name: "index_telemetry_readings_on_sensor_id_and_recorded_at"
  end
end
