# monc

monc is a modular observability framework that standardizes the deployment and lifecycle management of production monitoring infrastructure. It treats telemetry collection, metrics storage, and visualization as independently deployable infrastructure layers rather than manually managed services, and ships with a TUI-based CLI, powered by `gum`, that handles system validation, dependency resolution, configuration generation, and service provisioning end to end.

## Design Philosophy

The core design principle of monc is that observability infrastructure is decomposed into three logically isolated layers - Telemetry, Storage, and Visualization - each with a single operational responsibility, each independently deployable, and each managed through the same orchestration flow rather than bespoke per-component tooling.

The layer is the contract. A component's layer (export, store, visualize) determines where its configuration lives on disk, how its runtime is provisioned, and how it is referenced by the CLI. A Telemetry component knows nothing about how Storage persists the metrics it exposes, and Storage knows nothing about how Visualization queries it. Each layer only has to honor its own contract with the one above it.

The name is the identity. Every component instance is addressed by a single user-supplied identifier, and that identifier is propagated consistently into every artifact the framework generates: the Docker context, the container name, the bridge network, the systemd unit name, the dedicated system account that runs it, and the configuration directory on disk. Nothing about a component's identity is derived separately or tracked in a side registry - it all folds out of that one name plus its layer.

The runtime follows the nature of the component. monc does not force a single deployment strategy. Components that are naturally containerized (Prometheus, Grafana) are provisioned through Docker Compose with a dedicated context and bridge network per instance. Components that are naturally host-level agents (node_exporter, mysqld_exporter) are provisioned as systemd services running under their own dedicated, unprivileged system account. The CLI abstracts this choice away from the operator - asking only for configuration inputs - while keeping the underlying primitives (Docker vs. systemd) fully visible and inspectable on disk.

The port is proven, not assumed. Before any component is provisioned, the port an operator supplies is run through an entire chain of independent, live checks rather than a single "is it free" test: it must fall outside the kernel's ephemeral port range (`/proc/sys/net/ipv4/ip_local_port_range`), it must not appear bound in current socket state (`ss -tuln`), it must not be forwarded by iptables NAT rules or exposed via nftables rulesets, it must not already be published by a running container in any Docker context on the host, and it must not collide with the Kubernetes NodePort range (30000–32767). A port only gets accepted once it clears every one of these independently.

Dependencies are asked, not forced. Every dependency that isn't strictly load-bearing for the CLI itself - `ss`/iproute2, iptables, nftables, Docker, node_exporter - is offered to the operator through a `gum confirm` prompt before anything is installed. Declining an optional tool degrades the accuracy of later checks (a warning is logged) rather than aborting; declining a required one (Docker for a store/visualize task, node_exporter for a node export task) is treated as fatal, since the task cannot proceed without it.

The CLI is a generator, not a daemon. monc itself does not run continuously or supervise the components it creates. Ownership of runtime behavior belongs entirely to Docker and systemd once provisioning finishes. monc's job ends at detecting the system, resolving dependencies, validating input, writing configuration, and issuing the create/remove/list operations that stand components up or tear them down.

## Architectural Layers

### Export Layer (Tier 1)
The Export layer provisions exporters that generate and expose metrics to a Prometheus-compatible endpoint. Every exporter in this layer is a pull-based target; none of them push data anywhere.
**node_exporter** - system-level metrics (CPU, memory, disk, network), run as a systemd service under a dedicated, unprivileged system account.
**blackbox_exporter** (+ **bman**) - probe-based monitoring over HTTP, HTTPS, TCP, and ICMP, paired with a companion web UI for live probe-configuration editing.
**mysqld_exporter** - MySQL metrics for self-managed and managed database instances.

### Store Layer (Tier 2)
The Store layer centralizes everything the Export layer exposes into a single persistence model.
**Prometheus** - a pull-based time-series database, deployed via Docker Compose, that scrapes exporter endpoints on operator-managed intervals.

### Visualize Layer (Tier 3)
The Visualize layer exposes what Storage has collected through a queryable, dashboard-driven interface.
**Grafana** - deployed via Docker Compose with Prometheus pre-registered as its default datasource through provisioning files, so no manual datasource setup is required inside the UI.

## Working

### Bootstrap
Every entry point - the base `monc` utility and every individual task script - begins with the same sequence: detect the package manager (`yum` or `apt`) and normalize the machine architecture (`x86_64` → `amd64`; `aarch64`/`arm64` → `arm64`), confirm sudo access, then install `wget` and `gum` if either is missing. `gum` is fetched as a version-pinned tarball directly from its GitHub release, extracted, and installed to `/usr/local/bin`. From this point forward every prompt, confirmation, and log line in the session is rendered through `gum`.

### Interactive dependency resolution
Once bootstrapped, a task script asks - rather than assumes - for everything it needs beyond the bootstrap layer:
**Input-validation tooling**: `ss` (iproute2), `iptables`, and `nftables` are checked individually; each missing tool is offered via a confirm prompt, and anything declined is simply skipped with a warning that later port-collision checks may be less accurate.
**Task-critical tooling**: Docker (for any store/visualize task) or node_exporter (for a node export task) is confirmed the same way, but declining here is fatal - the task cannot continue without it.

### Input collection
Every task script then collects and validates the identifiers it needs:
A **systemd task** collects a service name, validated against emptiness, disallowed characters, existing unit files (installed or masked), existing system accounts, and a short list of reserved names (`systemd`, `root`, `daemon`, `template`, etc.).
A **Docker task** collects a name, automatically prefixed `monc_`, validated against any Docker context already carrying that name.
Both collect a port, run through the full validation chain described above.

### Provisioning
From here the two runtimes diverge:
**systemd path** (node_exporter): a template unit file has its service name and port substituted in, a dedicated system account is created with `useradd --no-create-home --shell /usr/sbin/nologin`, the unit is installed to `/etc/systemd/system/`, `systemctl daemon-reload` is run, and the service is optionally enabled and started immediately, all inside a single flow, with cleanup logic that unwinds the unit file and system account if any step fails partway through.
**Docker path** (Prometheus, Grafana): a dedicated config and data directory pair is created under the component's config path, service-specific configuration is generated (`prometheus.yml` with a self-scrape job; `grafana.ini` plus a `provisioning/` tree wiring in the Prometheus datasource and default dashboard folder), a `docker-compose.yml` and `.env` file are written, a Docker context named after the component is created and switched to, and `docker compose up -d` brings the container up - after which the script checks for the running container before reporting success.

### Configuration on disk
Regardless of runtime, generated files land in a layer-mirrored path:
```
~/.config/monc/export/databases/mysql/<name>
~/.config/monc/export/systems/node/<name>
~/.config/monc/export/endpoints/blackbox/<name>
~/.config/monc/store/prometheus/<name>/{config,data,docker-compose.yml,.env}
~/.config/monc/visualize/grafana/<name>/{config,data,docker-compose.yml,.env}
```
For Docker components, data persistence is handled via bind mounts into `data/` rather than named volumes, so component state stays inspectable directly on the host filesystem. For systemd components, the operative state - the port and service name - is written back into a flat key-value file under the export config path for later listing and teardown.

## Components

### Export layer
| Component | Runtime | Notes |
|---|---|---|
| node_exporter | systemd, dedicated unprivileged account | Version-pinned binary fetched from the upstream GitHub release; unit binds `--web.listen-address=:<port>` |
| blackbox_exporter (+ bman) | Docker | Probes HTTP/HTTPS/TCP/ICMP targets; bman edits probe config live over the web |
| mysqld_exporter | systemd, dedicated unprivileged account | Metrics for self-managed and managed MySQL instances |

### Store layer
| Component | Runtime | Notes |
|---|---|---|
| Prometheus | Docker Compose, context `monc_<name>` | Self-scrapes on the operator-supplied port; config and data bind-mounted, retention set to 30 days by default; supports hot config reload via `/-/reload` |

### Visualize layer
| Component | Runtime | Notes |
|---|---|---|
| Grafana | Docker Compose, context `monc_<name>` | Ships with Prometheus pre-registered as the default datasource via provisioning files; default `admin`/`admin` credentials are surfaced with an explicit warning to rotate them post-install |

## Supported Systems
**Arch**: amd64, arm64 (Linux)
**Package managers**: yum, apt
**Init system**: systemd

## Core Dependencies
`docker`, `gum`, `bash`, `wget`, `git` - monc resolves and installs these on the go where possible, so setup carries no pre-existing dependency requirement.

## Installation
```bash
sudo curl -fsSL https://raw.githubusercontent.com/myselfakashagarwal/monc/refs/heads/legacy/monc -o /usr/local/bin/monc && sudo chmod +x /usr/local/bin/monc
```

## Usage
```bash
monc [option]
  Export
    --create-export              # Create a new export configuration
    --remove-export               # Remove an existing export configuration
    --list-exports                # List all export configurations
  Store
    --create-store                # Create a new store configuration
    --remove-store                 # Remove an existing store configuration
    --list-stores                  # List all store configurations
  Visualization
    --create-visualization         # Create a new visualization configuration
    --remove-visualization          # Remove an existing visualization configuration
    --list-visualizations           # List all visualization configurations
```
