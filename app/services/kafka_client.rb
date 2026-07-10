# Thin wrapper around the ruby-kafka client so the rest of the app only
# depends on `KafkaClient.producer` rather than connection configuration.
# Connecting is lazy (ruby-kafka only opens a socket on first delivery), so
# requiring this class does not require a broker to be reachable.
class KafkaClient
  class << self
    def producer
      client.producer
    end

    private

    def client
      @client ||= Kafka.new(
        seed_brokers: brokers,
        client_id: ENV.fetch("KAFKA_CLIENT_ID", "vital-connect-api"),
        connect_timeout: 5,
        socket_timeout: 5,
        logger: Rails.logger
      )
    end

    def brokers
      ENV.fetch("KAFKA_BROKERS", "localhost:9092").split(",")
    end
  end
end
