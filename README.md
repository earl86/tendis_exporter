# Tendis Exporter

Prometheus exporter for Tendis server metrics.

## Introduction

Tendis Exporter is a Prometheus exporter that collects and exposes metrics from Tendis instances. It supports collecting various metrics including Tendis INFO, SLOWLOG, CLUSTER INFO, RocksDB stats, and process-level metrics.

## Features

- **Tendis Info Collection**: Collects comprehensive metrics from Tendis INFO, SLOWLOG, CLUSTER INFO and RocksDB stats
- **Process Metrics**: Collects in-depth tendis process metrics via /proc/[pid]/{stat,status,io}
- **Multi-target Support**: Supports scraping multiple Tendis instances from a single exporter
- **TLS and Authentication**: Supports TLS encryption and basic authentication for the metrics endpoint
- **Configurable Logging**: Flexible logging with different levels and formats

## Building and Running

### Build

```bash
go mod download
go mod tidy

# 然后执行 build
make build
or
go build -o tendis_exporter .

```

### Running

#### Single exporter mode

Running the exporter to scrape a single Tendis instance:

```bash
./tendis_exporter --tendis.addr=localhost:6379 --tendis.password=your_password
```

#### Multi-target support

This exporter supports the multi-target pattern, allowing you to run a single instance for multiple Tendis targets.

To use the multi-target functionality, send an HTTP request to the endpoint `/probe?target=foo:6379` where target is set to the address of the Tendis instance to scrape metrics from.

On the Prometheus side, you can set a scrape config as follows:

```yaml
- job_name: 'tendis_exporter'  # To get metrics about the Tendis exporter's targets
  metrics_path: /probe
  static_configs:
    - targets:
      # All Tendis hostnames to monitor.
      - server1:6379
      - server2:6379
      - server3:6379
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      # The tendis_exporter host:port
      replacement: localhost:9121
```

## Command Line Flags

### Connection Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--tendis.addr` | Address of the Tendis instance to scrape (default target) | `localhost:6379` |
| `--tendis.password` | Password of the Tendis instance | (empty) |

### Collector Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--collect.tendis_info` | Collects Tendis INFO, SLOWLOG, CLUSTER INFO and RocksDB stats | `true` |
| `--collect.tendis_process` | Collects in-depth tendis process metrics via /proc/[pid]/{stat,status,io} | `false` |

### Web Server Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--web.listen-address` | Addresses on which to expose metrics and web interface. Examples: `:9100` or `[::1]:9100` for http, `vsock://:9100` for vsock | `:9121` |
| `--web.telemetry-path` | Path under which to expose metrics | `/metrics` |
| `--web.config.file` | Path to configuration file that can enable TLS or authentication | (empty) |
| `--web.systemd-socket` | Use systemd socket activation listeners instead of port listeners (Linux only) | `false` |

### General Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--log.level` | Only log messages with the given severity or above. One of: [debug, info, warn, error] | `info` |
| `--log.format` | Output format of log messages. One of: [logfmt, json] | `logfmt` |
| `--timeout-offset` | Offset to subtract from timeout in seconds | `0.25` |
| `--version` | Show application version | - |

## Environment Variables

| Name | Description |
|------|-------------|
| `TENDIS_EXPORTER_PASSWORD` | Password to be used for connecting to Tendis instance |

## TLS and Basic Authentication

The Tendis Exporter supports TLS and basic authentication for securing the metrics endpoint.

To use TLS and/or basic authentication, you need to pass a configuration file using the `--web.config.file` parameter. The format of the file is described [in the exporter-toolkit repository](https://github.com/prometheus/exporter-toolkit/blob/master/docs/web-configuration.md).

Example configuration file (`web-config.yml`):

```yaml
tls_server_config:
  cert_file: /path/to/cert.pem
  key_file: /path/to/key.pem

basic_auth_users:
  admin: $2b$12$6YjKJZKZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZkZk
```

Run the exporter with TLS enabled:

```bash
./tendis_exporter --web.config.file=web-config.yml
```

## Using Docker

You can deploy this exporter using Docker.

Example:

```bash
docker network create my-tendis-network
docker pull tendis-exporter:latest

docker run -d \
  -p 9121:9121 \
  -v /path/to/web-config.yml:/web-config.yml \
  --network my-tendis-network \
  tendis-exporter:latest \
  --web.config.file=/web-config.yml \
  --tendis.addr=tendis:6379
```

## Filtering Enabled Collectors

The `tendis_exporter` will expose all metrics from enabled collectors by default. This is the recommended way to collect metrics to avoid errors when comparing metrics of different families.

For advanced use, the `tendis_exporter` can be passed an optional list of collectors to filter metrics. The `collect[]` parameter may be used multiple times. In Prometheus configuration, you can use this syntax under the [scrape config](https://prometheus.io/docs/prometheus/latest/configuration/configuration/#<scrape_config>).

```yaml
params:
  collect[]:
  - tendis_info
  - tendis_process
```

This can be useful for having different Prometheus servers collect specific metrics from targets.

## Metrics Examples

After starting the exporter, metrics will be available at `http://localhost:9121/metrics`.

Example metrics include:

- `tendis_up`: Whether the Tendis server is up
- `tendis_commands_total`: Total number of commands processed
- `tendis_keyspace_hits_total`: Total number of successful key lookups
- `tendis_keyspace_misses_total`: Total number of failed key lookups
- `tendis_memory_used_bytes`: Amount of memory used by Tendis
- `tendis_connected_clients`: Number of connected clients
- `tendis_connections_received_total`: Total number of connections accepted
- `tendis_rejected_connections_total`: Total number of rejected connections
- And many more...

## Example Rules, Alerts, and Dashboards

There is a set of sample rules, alerts, and dashboards available in the [tendis-mixin](tendis-mixin/) directory.

To use the mixin:

```bash
cd tendis-mixin
make build
```

The mixin includes:
- Pre-configured recording rules
- Alert rules for common Tendis issues
- Grafana dashboards for monitoring Tendis performance

## License

See [LICENSE](LICENSE) file for details.
