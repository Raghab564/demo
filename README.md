# Demo — Telemetry Ingestion Service

A small Ruby on Rails (API-only) microservice that ingests vital-sign
readings (heart rate + temperature) from simulated wearable sensors,
persists them to MySQL, and publishes one Kafka event per reading for
downstream consumers (dashboards, alerting, long-term analytics storage).

## Stack

| Concern              | Choice                                             |
|-----------------------|-----------------------------------------------------|
| API                   | Rails 8, API-only mode                              |
| Datastore             | MySQL 8 (ActiveRecord / mysql2)                     |
| Streaming             | Kafka (`ruby-kafka` producer), single-topic         |
| AuthN                 | Mock OAuth2/OIDC bearer token (JWT, HS256)          |
| Tests                 | RSpec (request, model, service specs)               |
| Containers            | Docker + docker-compose (app, MySQL, Kafka KRaft)   |

## Quick start

```bash
docker compose up --build
```

This builds the app image and starts three containers: `db` (MySQL),
`kafka` (single-node KRaft broker, no Zookeeper needed), and `app` (Rails,
listening on `http://localhost:3000`). The entrypoint waits for MySQL and
runs `bin/rails db:prepare` automatically, so the schema is created on
first boot — no manual migration step required.

### Mint a mock bearer token

The ingestion endpoint is protected by a mock OAuth2/OIDC bearer token. There
is no real identity provider — `Auth::MockTokenIssuer` stands in for one and
signs a short-lived JWT the same way a `client_credentials` grant would:

```bash
docker compose exec app bin/rails 'token:generate[sensor-01]'
```

### Ingest a reading

```bash
TOKEN=$(docker compose exec -T app bin/rails 'token:generate[sensor-01]')

curl -X POST http://localhost:3000/api/v1/telemetry_readings \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "sensor_id": "sensor-01",
        "timestamp": "2026-07-08T12:00:00Z",
        "heart_rate": 78,
        "temperature": 36.9
      }'
```

A `201 Created` response means the reading was persisted **and** a message
was published to the `telemetry.readings` Kafka topic. Watch it arrive:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic telemetry.readings --from-beginning
```

### Error responses

| Condition                              | Status | Body                                             |
|-----------------------------------------|--------|---------------------------------------------------|
| Missing/invalid/expired bearer token    | 401    | `{"error":"unauthorized","message":"..."}`         |
| Malformed JSON body                     | 400    | `{"error":"bad_request","message":"..."}`          |
| Failed validation (bad values, dup read)| 422    | `{"error":"validation_failed","messages":[...]}`   |
| Success                                 | 201    | The persisted reading, serialized as JSON          |

### Stopping the stack

```bash
docker compose down       # stop and remove containers, keep DB/Kafka data
docker compose down -v    # also wipe the MySQL and Kafka volumes
```

## Running the test suite

The specs need a real MySQL instance (mysql2 has no in-memory mode), so run
them through the same compose stack:

```bash
docker compose run --rm -e RAILS_ENV=test app bin/rails db:prepare
docker compose run --rm -e RAILS_ENV=test app bundle exec rspec
```

Coverage: request specs for the ingestion endpoint (auth success/failure,
validation, duplicate detection, Kafka publish call), model validations
(including the sensor_id + recorded_at uniqueness constraint), and service
specs for both the token validator and the Kafka publisher (using a stubbed
producer double, so no test depends on a live broker).

## Design decisions

**MySQL over MongoDB.** The payload shape is fixed and small (sensor_id,
timestamp, heart_rate, temperature), so there's no schema-flexibility
argument for a document store here. MySQL gives ActiveRecord validations,
a real UNIQUE constraint for idempotent ingestion (see below), and is the
more common operational choice for a Rails shop. At genuinely high
cardinality/throughput this table would eventually want to move to a
purpose-built time-series store (see Scaling, below) — MySQL is the right
starting point, not necessarily the end state.

**Idempotent ingestion.** Wearables retry on dropped acks, which would
otherwise double-count a vital sign. `telemetry_readings` has a unique
index on `(sensor_id, recorded_at)`; a retransmit fails validation with
`422` instead of silently creating a duplicate row or a duplicate Kafka
event.

**Kafka publish failure does not fail the request.** By the time
`TelemetryEventPublisher` runs, the reading is already durably committed to
MySQL. If the broker is unreachable, the publish is logged as an error and
the request still returns `201` — losing a downstream notification is
recoverable (replay from the DB), losing the vital sign itself is not. A
production version of this would additionally write to an outbox table and
replay it via a background job, rather than only logging.

**Mock OIDC, not a full IdP.** `Auth::TokenValidator` validates the real
surface a resource server would check — signature, issuer, audience,
expiry — via `ruby-jwt`. The only thing mocked is the signing algorithm:
HS256 with a shared secret instead of RS256 verified against a JWKS
endpoint. Swapping in a real IdP (Cognito, Auth0, Okta) means replacing the
`secret`/`issuer`/`audience` lookups in `Auth::TokenValidator` with a JWKS
fetch-and-cache step; `TokenAuthenticatable` (the controller concern) and
the rest of the app don't change.

**Flat JSON body, not a nested `telemetry_reading` param.** A wearable
gateway posting raw sensor data has no reason to know Rails' strong-params
conventions, so `wrap_parameters` is disabled on this controller and the
body is read as `{sensor_id, timestamp, heart_rate, temperature}` directly.

## Scaling considerations on AWS

- **Compute**: run the API on EKS (Fargate or managed node groups) behind
  an ALB, autoscaled on CPU/RPS via HPA (see `k8s/deployment.yaml`).
  Ingestion is stateless and horizontally scalable — the interesting limits
  are downstream (DB, broker).
- **Database**: RDS for MySQL / Aurora MySQL with a read replica for
  reporting queries so ingestion writes never contend with clinician-facing
  reads. At thousands-of-sensors-times-per-second write volume, the next
  steps are (a) partitioning `telemetry_readings` by time (monthly range
  partitions) so old data can be archived/dropped cheaply, and (b)
  evaluating a purpose-built time-series store (Timestream, or
  Timescale-on-RDS) if MySQL write throughput becomes the bottleneck rather
  than convenience.
- **Streaming**: swap the single-broker dev Kafka for MSK, with the
  `telemetry.readings` topic partitioned by `sensor_id` (already the
  producer's partition key here) so per-sensor ordering is preserved while
  spreading load across brokers/consumers. Add a schema registry
  (MSK Connect / Glue Schema Registry) once more than one consumer depends
  on the event shape.
- **Backpressure / durability**: the ingestion path currently does a
  synchronous `produce` + `deliver_messages` per request. At real wearable
  fleet volume this should move to an async/batched producer (ruby-kafka
  supports `async_producer`) or, more robustly, a transactional outbox
  table drained by a background worker — so a Kafka hiccup never risks an
  unbounded queue of unflushed messages living only in process memory.
- **AuthN/AuthZ**: replace the mock validator with Amazon Cognito (or
  another OIDC-compliant IdP) issuing RS256 tokens; verify via its JWKS
  endpoint with in-memory caching (keys rotate infrequently) instead of a
  shared HMAC secret. Put the ALB or an API Gateway in front to enforce
  TLS termination, WAF rules, and per-sensor rate limiting.
- **Compliance (HIPAA)**: vitals tied to a sensor/patient ID are PHI.
  In AWS that means: encryption at rest (RDS/MSK with KMS) and in transit
  (TLS everywhere), VPC-only networking with no public DB/broker endpoints,
  CloudTrail + RDS audit logging for access review, and a signed AWS BAA.
  None of that is implemented here — it's a mock take-home service — but it
  shapes every choice above (e.g. why secrets come from Secrets Manager in
  `k8s/secret.example.yaml` rather than plain env vars in a real deploy).

## Bonus: Kubernetes manifests

`k8s/deployment.yaml`, `k8s/service.yaml`, `k8s/configmap.yaml`, and
`k8s/secret.example.yaml` sketch what deploying this to a cluster looks
like: a 3-replica Deployment with liveness/readiness probes against `/up`,
an HPA scaling on CPU, and a ClusterIP Service in front. They're
illustrative, not applied anywhere — the placeholder image URI and
Secret values need to be filled in for a real cluster.

## What's intentionally out of scope

- A real identity provider (documented above).
- Multi-tenant sensor registration/pairing — `sensor_id` is trusted as
  given in the payload.
- A consumer for the Kafka topic — the exercise asked for a producer
  integrated into the ingestion path, not the downstream analytics service
  that would consume `telemetry.readings`.
