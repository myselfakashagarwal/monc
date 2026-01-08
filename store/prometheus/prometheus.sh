#!/bin/bash

# global variables
PACKAGE_MANAGER=""
ARCHITECTURE=""
KERNEL="linux"
GUM_VERSION="0.16.1"
declare -a TOOLS_TO_INSTALL=()
CONTEXT=""
PROMETHEUS_PORT=""
INSTALL_DOCKER=false 
INSTALL_GIT=false

create_monc_config() {
    mkdir -p ~/.config/monc  
    mkdir -p ~/.config/monc/export/databases/mysql  
    mkdir -p ~/.config/monc/export/endpoints/blackbox  
    mkdir -p ~/.config/monc/export/systems/node  
    mkdir -p ~/.config/monc/store/prometheus  
    mkdir -p ~/.config/monc/visualize/grafana  
}

check_system_compatibility() {
    PACKAGE_MANAGER=""
    if [[ -e /etc/yum ]]; then
        PACKAGE_MANAGER="yum"
    elif [[ -e /etc/apt ]]; then
        PACKAGE_MANAGER="apt"
    else
      echo "ERROR Unsupported package manager"
      exit 1;  
    fi
    
    # Detect architecture
    ARCHITECTURE=$(uname -m)
    case ${ARCHITECTURE} in
        x86_64)
            ARCHITECTURE="amd64"
            ;;
        aarch64|arm64)
            ARCHITECTURE="arm64"
            ;;
        armv7l)
            ARCHITECTURE="armv7"
            ;;
        *)
            echo "ERROR: Unsupported architecture: ${ARCHITECTURE}"
            exit 1
            ;;
    esac
    
    echo "INFO: Detected package manager: ${PACKAGE_MANAGER}"
    echo "INFO: Detected architecture: ${ARCHITECTURE}"
}

check_and_install_script_dependencies() {
    
    # install wget 
    if command -v wget > /dev/null 2>&1; then
        echo "INFO: wget is installed"
    else
        echo "INFO: Installing wget..."
        if sudo $PACKAGE_MANAGER install wget -y; then
            echo "INFO: wget installed successfully"
        else
            echo "FATAL: 'wget' installation failed"
            exit 1
        fi
    fi
    
    # install gum 
    if command -v gum > /dev/null 2>&1; then
        echo "INFO: gum is installed"
    else
        echo "INFO: Installing gum..."
        local gum_arch="${ARCHITECTURE}"
        if [[ ${ARCHITECTURE} == "amd64" ]]; then
            gum_arch="x86_64"
        fi
        
        local gum_tarball="gum_${GUM_VERSION}_Linux_${gum_arch}.tar.gz"
        local gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${gum_tarball}"
        
        echo "INFO: Downloading gum from ${gum_url}"
        
        if ! wget -q "${gum_url}"; then
            echo "ERROR: Failed to download gum"
            exit 1
        fi
        
        if ! tar -xzf "${gum_tarball}" 2>/dev/null; then
            echo "ERROR: Failed to extract gum"
            rm -f "${gum_tarball}"
            exit 1
        fi
        
        # Find the gum binary in extracted files
        local gum_binary=$(find . -name "gum" -type f -executable | head -n 1)
        
        if [[ -z "${gum_binary}" ]]; then
            echo "ERROR: gum binary not found in extracted files"
            rm -f "${gum_tarball}"
            exit 1
        fi
        
        if ! sudo mv "${gum_binary}" /usr/local/bin/gum 2>/dev/null; then
            echo "ERROR: Failed to move gum to /usr/local/bin"
            rm -f "${gum_tarball}"
            exit 1
        fi
        
        sudo chmod +x /usr/local/bin/gum
        
        # Clean up
        rm -f "${gum_tarball}"
        rm -rf gum_*
        
        if command -v gum > /dev/null 2>&1; then
            echo "INFO: gum installed successfully"
        else
            echo "ERROR: 'gum' installation failed"
            exit 1
        fi
    fi
  
}

check_and_ask_input_dependencies() {
    if command -v ss > /dev/null 2>&1; then
        gum log --level info "ss is already installed"
    else
        if gum confirm "Install 'ss' (iproute2)?" --default=yes; then
            TOOLS_TO_INSTALL+=("iproute2")
            gum log --level info "iproute2 will be installed"
        else
            gum log --level warn "ss not installed, input checking might not be accurate"
        fi
    fi
    
    # check for iptables
    if command -v iptables > /dev/null 2>&1; then
        gum log --level info "iptables is already installed"
    else
        if gum confirm "Install 'iptables'?" --default=yes; then
            TOOLS_TO_INSTALL+=("iptables")
            gum log --level info "iptables will be installed"
        else
            gum log --level warn "iptables not installed, input checking might not be accurate"
        fi
    fi
    
    # check for nftables
    if command -v nft > /dev/null 2>&1; then
        gum log --level info "nftables is already installed"
    else
        if gum confirm "Install 'nftables'?" --default=yes; then
            TOOLS_TO_INSTALL+=("nftables")
            gum log --level info "nftables will be installed"
        else
            gum log --level warn "nftables not installed, input checking might not be accurate"
        fi
    fi
    
    
    if command -v which > /dev/null 2>&1; then
        gum log --level info "which is already installed"
    else
        if gum confirm "Install 'which'?" --default=yes; then
            TOOLS_TO_INSTALL+=("which")
            gum log --level info "which will be installed"
        else
            gum log --level warn "which not installed, input checking might not be accurate"
        fi
    fi

    if command -v awk > /dev/null 2>&1; then
        gum log --level info "awk is already installed"
    else
        if gum confirm "Install 'awk'?" --default=yes; then
            TOOLS_TO_INSTALL+=("awk")
            gum log --level info "awk will be installed"
        else
            gum log --level warn "awk not installed, input checking might not be accurate"
        fi
    fi

    if command -v cut > /dev/null 2>&1; then
        gum log --level info "cut is already installed"
    else
        if gum confirm "Install 'cut'?" --default=yes; then
            TOOLS_TO_INSTALL+=("cut")
            gum log --level info "cut will be installed"
        else
            gum log --level warn "cut not installed, input checking might not be accurate"
        fi
    fi

    if command -v grep > /dev/null 2>&1; then
        gum log --level info "grep is already installed"
    else
        if gum confirm "Install 'grep'?" --default=yes; then
            TOOLS_TO_INSTALL+=("grep")
            gum log --level info "grep will be installed"
        else
            gum log --level warn "grep not installed, input checking might not be accurate"
        fi
    fi
    
    if command -v sed > /dev/null 2>&1; then
        gum log --level info "sed is already installed"
    else
        if gum confirm "Install 'sed'?" --default=yes; then
            TOOLS_TO_INSTALL+=("sed")
            gum log --level info "sed will be installed"
        else
            gum log --level warn "sed not installed, input checking might not be accurate"
        fi
    fi
}

check_and_ask_task_dependencies() {
    if command -v docker > /dev/null 2>&1; then
        gum log --level info "docker is already installed"
    else
        if gum confirm "Install 'docker'?" --default=yes; then
            INSTALL_DOCKER=true
            gum log --level info "docker will be installed"
        else
            gum log --level fatal "docker not installed, its required for the task"
            exit 1
        fi
    fi
}


install_input_dependencies() {
    for tool in "${TOOLS_TO_INSTALL[@]}"; do
        case $tool in
            iproute2)
                sudo $PACKAGE_MANAGER install iproute2 -y
                if command -v ss > /dev/null 2>&1; then
                    gum log --level info "iproute2 installed successfully"
                else
                    gum log --level error "iproute2 installation failed"
                    exit 1
                fi
                ;;
            iptables)
                sudo $PACKAGE_MANAGER install iptables -y
                if command -v iptables > /dev/null 2>&1; then
                    gum log --level info "iptables installed successfully"
                else
                    gum log --level error "iptables installation failed"
                    exit 1
                fi
                ;;
            nftables)
                sudo $PACKAGE_MANAGER install nftables -y
                if command -v nft > /dev/null 2>&1; then
                    gum log --level info "nftables installed successfully"
                else
                    gum log --level error "nftables installation failed"
                    exit 1
                fi
                ;;
            *)
                sudo ${PACKAGE_MANAGER} install $tool -y
                if command -v $tool > /dev/null 2>&1; then
                    gum log --level info "$tool installed successfully"
                else
                    gum log --level error "$tool installation failed"
                    exit 1
                fi
            ;;
        esac
    done
}

install_task_dependencies() {
    if [[ ${INSTALL_DOCKER} == true ]]; then 
        if [[ $PACKAGE_MANAGER == "apt" ]]; then
            gum log --level info "Installing Docker"
            sudo $PACKAGE_MANAGER install -y docker.io docker-compose > /dev/null 2>&1
            if command -v docker > /dev/null 2>&1; then
                gum log --level info "Docker installed successfully"
            else
                gum log --level error "Docker installation failed"
                exit 1
            fi
            gum log --level info "Adding user to docker group"
            sudo groupadd docker > /dev/null 2>&1
            sudo usermod -aG docker $USER > /dev/null
            gum log --level info "User added to docker group successfully"
            gum log --level info "Enabling Docker service"
            sudo systemctl enable docker > /dev/null 2>&1
            gum log --level info "Docker service enabled successfully"
            gum log --level info "Starting Docker service"
            sudo systemctl start docker > /dev/null 2>&1
            if sudo systemctl is-active --quiet docker; then
                gum log --level info "Docker service started successfully"
            else
                gum log --level error "Docker service failed to start"
                exit 1
            fi
        elif [[ $PACKAGE_MANAGER == "yum" ]]; then
            gum log --level info "Updating system"
            sudo yum update -y > /dev/null 2>&1
            sudo yum install -y yum-utils device-mapper-persistent-data lvm2 > /dev/null 2>&1
            gum log --level info "System updated successfully"
            gum log --level info "Installing Docker"
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
            sudo yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin --allowerasing > /dev/null 2>&1
            if command -v docker > /dev/null 2>&1; then
                gum log --level info "Docker installed successfully"
            else
                gum log --level error "Docker installation failed"
                exit 1
            fi
            gum log --level info "Adding user to docker group"
            sudo groupadd docker > /dev/null 2>&1
            sudo usermod -aG docker $USER > /dev/null
            gum log --level info "User added to docker group successfully"
            gum log --level info "Enabling Docker service"
            sudo systemctl enable docker > /dev/null 2>&1
            gum log --level info "Docker service enabled successfully"
            gum log --level info "Starting Docker service"
            sudo systemctl start docker > /dev/null 2>&1
            if sudo systemctl is-active --quiet docker; then
                gum log --level info "Docker service started successfully"
            else
                gum log --level error "Docker service failed to start"
                exit 1
            fi
            gum log --level warn "After installation is complete, please log out and log back in to apply the changes." 
        fi
    fi
}

validate_context() {
    if [[ -z $(docker context ls | awk 'NR!=1{ print $1 }' | grep -w ${CONTEXT}) ]]; then 
        return 0;
    else 
        gum log --level error "Context already exists"
        return 1;
    fi
}

input_context() {
    CONTEXT="monc_$(gum input --prompt 'Input name: ')"
    until validate_context; do
        CONTEXT="monc_$(gum input --prompt 'Input name: ')"
    done
    gum log --level info "Context: ${CONTEXT}"
}


validate_port() {
    local PORT=$1
    local PORT_NAME=$2
    
    # empty check
    if [[ -z "${PORT}" ]]; then
        gum log --level error "${PORT_NAME} cannot be empty"
        return 1
    fi

    # numeric check
    if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
        gum log --level error "${PORT_NAME} must be numeric"
        return 1
    fi

    # valid range (combining privileged port check)
    if (( PORT < 1024 || PORT > 65535 )); then
        gum log --level error "${PORT_NAME} must be between 1024 and 65535 (privileged ports below 1024 are not allowed)"
        return 1
    fi

    # ephemeral port range
    if [[ -f /proc/sys/net/ipv4/ip_local_port_range ]]; then
        read EPHEMERAL_START EPHEMERAL_END < /proc/sys/net/ipv4/ip_local_port_range
        if (( PORT >= EPHEMERAL_START && PORT <= EPHEMERAL_END )); then
            gum log --level error "${PORT_NAME} is in ephemeral range (${EPHEMERAL_START}-${EPHEMERAL_END})"
            return 1
        fi
    fi

    # socket bound ports
    if command -v ss > /dev/null 2>&1; then
        if ss -H -tuln 2>/dev/null | awk '{print $5}' | sed 's/.*://' | grep -qx "${PORT}"; then
            gum log --level error "${PORT_NAME} already in use by a running service"
            return 1
        fi
    fi

    # iptables NAT ports
    if command -v iptables >/dev/null 2>&1; then
        if sudo iptables -t nat -L -n 2>/dev/null | grep -q "dpt:${PORT}"; then
            gum log --level error "${PORT_NAME} already exposed via iptables NAT"
            return 1
        fi
    fi

    # nftables ports
    if command -v nft >/dev/null 2>&1; then
        if sudo nft list ruleset 2>/dev/null | grep -q "dport ${PORT}"; then
            gum log --level error "${PORT_NAME} already exposed via nftables"
            return 1
        fi
    fi

    # docker published ports
    if command -v docker >/dev/null 2>&1; then
        if sudo docker context ls --format '{{.Name}}' 2>/dev/null \
            | xargs -I{} sudo docker --context {} ps --format '{{.Ports}}' 2>/dev/null \
            | grep -qE "(^|,|\s)(0\.0\.0\.0|\[::\]):${PORT}->"; then
            gum log --level error "${PORT_NAME} already published by Docker"
            return 1
        fi
    fi

    # kubernetes NodePort range
    if (( PORT >= 30000 && PORT <= 32767 )); then
        gum log --level error "${PORT_NAME} conflicts with Kubernetes NodePort range"
        return 1
    fi
}

input_prometheus_port() {
    PROMETHEUS_PORT=$(gum input --prompt "Input Prometheus port: " --placeholder "9090")
    until validate_port "${PROMETHEUS_PORT}" "Prometheus port"; do
        PROMETHEUS_PORT=$(gum input --prompt "Input Prometheus port: " --placeholder "9090")
    done
    gum log --level info "Prometheus Port: ${PROMETHEUS_PORT}"
}

ask_task() {
    if gum confirm "Create Prometheus context?" --default=yes; then
        gum log --level info "Prometheus context will be created"
    else
        gum log --level fatal "Prometheus context creation is required for the task"
        exit 1
    fi
}

manage_dependencies() {
    check_system_compatibility
    check_and_install_script_dependencies
    check_and_ask_input_dependencies
    check_and_ask_task_dependencies
    ask_task 
    install_input_dependencies
    install_task_dependencies
}

get_inputs() {
    input_context
    input_prometheus_port
}

create_prometheus_config() {
    local config_dir="$1"
    local prom_port="$2"
    
    gum log --level info "Creating Prometheus configuration..."
    
    cat > "${config_dir}/prometheus.yml" << EOF
# Prometheus Configuration
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    monitor: 'monc-prometheus'

# Alertmanager configuration (optional)
alerting:
  alertmanagers:
    - static_configs:
        - targets: []
          # - 'alertmanager:9093'

# Load rules once and periodically evaluate them
rule_files:
  # - "alerts/*.yml"
  # - "rules/*.yml"

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:${prom_port}']
        labels:
          instance: 'prometheus'
          environment: 'production'

  # Example: Node Exporter
  # - job_name: 'node'
  #   static_configs:
  #     - targets: ['node-exporter:9100']
  #       labels:
  #         instance: 'node-01'

  # Example: Blackbox Exporter
  # - job_name: 'blackbox'
  #   static_configs:
  #     - targets: ['blackbox-exporter:9115']
  #       labels:
  #         instance: 'blackbox-exporter'

  # Example: HTTP endpoint monitoring via Blackbox
  # - job_name: 'http_targets'
  #   metrics_path: /probe
  #   params:
  #     module: [http_2xx]
  #   static_configs:
  #     - targets:
  #       - https://example.com
  #       - https://api.example.com
  #   relabel_configs:
  #     - source_labels: [__address__]
  #       target_label: __param_target
  #     - source_labels: [__param_target]
  #       target_label: instance
  #     - target_label: __address__
  #       replacement: blackbox-exporter:9115

EOF

    gum log --level info "Prometheus configuration created successfully"
}

create_docker_compose() {
    local compose_dir="$1"
    local config_dir="$2"
    local data_dir="$3"
    
    gum log --level info "Creating Docker Compose configuration..."
    
    cat > "${compose_dir}/docker-compose.yml" << EOF
services:
  prometheus:
    image: prom/prometheus:latest
    user: root
    container_name: \${PROMETHEUS_CONTAINER_NAME}
    restart: unless-stopped
    ports:
      - "\${PROMETHEUS_PORT}:9090"
    volumes:
      - ${data_dir}:/prometheus
      - ${config_dir}/prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/usr/share/prometheus/console_libraries'
      - '--web.console.templates=/usr/share/prometheus/consoles'
      - '--storage.tsdb.retention.time=30d'
      - '--web.enable-lifecycle'
    labels:
      - "com.monc.service=prometheus"
      - "com.monc.context=${CONTEXT}"
EOF

    gum log --level info "Docker Compose configuration created successfully"
}

create_env_file() {
    local env_file="$1"
    
    gum log --level info "Creating environment file..."
    
    cat > "${env_file}" << EOF
# Prometheus Configuration
PROMETHEUS_PORT=${PROMETHEUS_PORT}
PROMETHEUS_CONTAINER_NAME=${CONTEXT}_prometheus
EOF

    gum log --level info "Environment file created successfully"
}

setup_compose_and_start() {
    local base_dir="${HOME}/.config/monc/store/prometheus/${CONTEXT}"
    local config_dir="${base_dir}/config"
    local data_dir="${base_dir}/data"
    
    gum log --level info "Setting up Prometheus directories..."
    
    # Create directory structure
    mkdir -p "${config_dir}"
    mkdir -p "${data_dir}"
    
    # Create configurations
    create_prometheus_config "${config_dir}" "${PROMETHEUS_PORT}"
    create_docker_compose "${base_dir}" "${config_dir}" "${data_dir}"
    create_env_file "${base_dir}/.env"
    
    gum log --level info "Creating and configuring Docker context..."
    
    # Setup docker context and start compose
    cd "${base_dir}"
    sudo docker context use default > /dev/null 2>&1
    sudo docker context create ${CONTEXT} > /dev/null 2>&1
    sudo docker context use ${CONTEXT} > /dev/null 2>&1
    
    gum log --level info "Starting Prometheus container..."
    sudo docker compose up -d
    
    # Wait for Prometheus to be ready
    gum log --level info "Waiting for Prometheus to be ready..."
    sleep 5
    
    # Check if container is running
    if sudo docker ps | grep -q "${CONTEXT}_prometheus"; then
        gum log --level info "✓ Prometheus is running successfully!"
        gum log --level info "Access Prometheus at: http://$(hostname -I | awk '{print $1}'):${PROMETHEUS_PORT}"
        gum log --level info "Data directory: ${data_dir}"
        gum log --level info "Config directory: ${config_dir}"
        echo ""
        gum log --level info "To reload configuration without restart:"
        gum log --level info "  curl -X POST http://localhost:${PROMETHEUS_PORT}/-/reload"
    else
        gum log --level error "Failed to start Prometheus container"
        gum log --level info "Check logs with: docker logs ${CONTEXT}_prometheus"
        exit 1
    fi
}

perform_task() {
    create_monc_config
    manage_dependencies
    get_inputs
    setup_compose_and_start
}

########################## calls ################################
perform_task