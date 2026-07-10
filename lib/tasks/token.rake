namespace :token do
  desc "Generate a mock OIDC bearer token for local testing. Usage: bin/rails 'token:generate[sensor-01]'"
  task :generate, [ :sensor_id ] => :environment do |_task, args|
    sensor_id = args[:sensor_id].presence || "demo-sensor"
    puts Auth::MockTokenIssuer.call(sensor_id: sensor_id)
  end
end
