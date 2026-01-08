<img width="867" alt="Screenshot 2024-06-09 at 2 00 14 AM" src="https://github.com/myselfakashagarwal/monc/assets/106314226/06455067-da98-431d-a099-6d37729836c8">

## About
monc is a containerized stack for monitoring which includes exposing, storing and visualization of metrics, for servers, databases and endpoints. Comes with its own TUI based cli to handle all the heavy lifting of configurations and setting things up. 

## Features 
- Setups with no dependency hell with installation of dependencies on the go. 
- Easy setups with simple command and inputs 
- Strong system wide validation checks  
- Dynamic configuration management 
- TUI based interface powered by gum

## Supported system 
- Arch: amd64, arm64 (Linux) 
- Package: yum, apt 
- Init: (systemd)

## Core dependencies
- docker, gum, bash, wget, git

## Components 

### Export (Tier 1)
Export covers all the exporters which are used to generate metrics and expose them to an endpoint, the metrics are specificially for prometheus. This includes:
- node_exporter: exposes system metrics like cpu utilization, free memory etc to endpoint, implemented with systemd service. 
- blackbox_exporter: probing based solution for monitoring endpoints: http, tcp, ping, https. Also including a custom solution `bman` for editing configuration via web in realtime. 
- mysqld_exporter: exporting mysql database metrics for self managed and managed databases.

### Store (Tier 2)
- Prometheus: A realtime time series database for storing metrics, monc specificially uses its pull based mechanism its configuration is broadly managed by user. 

### Visualize (Tier 3)
- Grafana: An analytics and visualization platform.

## Working 
The stack is simplified for three tier usage, in which each tier is deployed independently with docker (if independent) and systemd based services, the implementation is flexible can be done with independent scripts or with the help of centrilised monc utility. The utility is extremely dynamic it asks all the configuration details from the user and generates the necessary files and services accordingly on the go. Also manages dependencies and ensures proper configuration of each component. Also includes aspects such as dependency managementm, input validations and management commands.  

### Deployment 
- For docker based deployments monc creates context from (default) and run compose service init, configured based of user inputs such as such as context name: `monc_$name` containers: `monc_$name_component` network: `monc_$name_component_default` 
- For systemd based services monc creates service with name: `$name.sevice` run by system account: `$name` on port: `$port`   
> [!NOTE]
> docker aspects are created with root ; thus might not be visible to normal user (ep. context) forked from default endpoint. 

### Configuration
- For all cases the base configuration is provided by monc itself, all files are stored at locations: (same as the directory structure of this repo) 
`~/.config/monc/export/$name`, `~/.config/monc/store/$name`, `~/.config/monc/visualize/$name` The configuration file are created on the go. 
Systemd service file stored the basic input info as content also docker compose implementation setup code can be found there too (bare mounts are used to store data) 

## Usage

## Just paste this and you are ready to go 
```bash
(sudo curl -fsSL https://raw.githubusercontent.com/myselfakashagarwal/monc/refs/heads/legacy/monc -o /usr/local/bin/monc && sudo chmod +x /usr/local/bin/monc)
```

### Options 
```bash
monc [option]
  Export 
    --create-export             # Create a new export configuration
    --remove-export             # Remove an existing export configuration
    --list-exports              # List all export configurations
  Store 
    --create-store              # Create a new store configuration
    --remove-store              # Remove an existing store configuration
    --list-stores               # List all store configurations       
  Visualization
    --create-visualization      # Create a new visualization configuration
    --remove-visualization      # Remove an existing visualization configuration
    --list-visualizations       # List all visualization configurations
```
