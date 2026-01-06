#!/bin/bash

set -euo pipefail

# Global variables
PACKAGE_MANAGER=""
ARCHITECTURE=""
KERNEL="linux"
SERVICE=""
PORT=""
SERVICE_START=false
INSTALL_NODE_EXPORTER=false
INSTALL_TEMPLATE_SERVICE=true

declare -a TOOLS_TO_INSTALL=()

# Versions (centralized for easy updates)
GUM_VERSION="0.16.1"
NODE_EXPORTER_VERSION="1.8.2"

create_monc_config() {
    mkdir -p ~/.config/monc > /dev/null 2>&1
    mkdir -p ~/.config/monc/export/databases/mysql > /dev/null 2>&1
    mkdir -p ~/.config/monc/export/endpoints/blackbox > /dev/null 2>&1
    mkdir -p ~/.config/monc/exportsystems/node > /dev/null 2>&1
    mkdir -p ~/.config/monc/store/prometheus > /dev/null 2>&1
    mkdir -p ~/.config/monc/visualize/grafana > /dev/null 2>&1
}

############################## pre functions #######################################
check_system_compatibility() {
    # check for the package manager  
    PACKAGE_MANAGER=""
    if [[ -e /etc/yum.conf ]] || command -v yum > /dev/null 2>&1; then
        PACKAGE_MANAGER="yum"
    elif [[ -e /etc/apt ]] || command -v apt > /dev/null 2>&1; then
        PACKAGE_MANAGER="apt"
    else
        echo "FATAL: Unsupported package manager"
        exit 1
    fi
    
    # check for architecture
    local arch=$(uname -m)
    if [[ ${arch} == "x86_64" ]]; then
        ARCHITECTURE="amd64"
    elif [[ ${arch} == "aarch64" || ${arch} == "arm64" ]]; then
        ARCHITECTURE="arm64"
    else
        echo "FATAL: Unsupported architecture: ${arch}"
        exit 1
    fi
    KERNEL="linux"
    
    # check for sudo access
    if ! sudo -n true 2>/dev/null; then
        echo "FATAL: This script requires sudo access"
        exit 1
    fi
}

check_and_install_script_dependencies() {
    # install wget 
    if command -v wget > /dev/null 2>&1; then
        echo "INFO: wget is installed"
    else
        echo "INFO: Installing wget..."
        if sudo $PACKAGE_MANAGER install wget -y > /dev/null 2>&1; then
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
        local gum_folder="gum_${GUM_VERSION}_Linux_${gum_arch}"
        local gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${gum_tarball}"
        
        if ! wget -q "${gum_url}"; then
            echo "ERROR: Failed to download gum"
            exit 1
        fi
        
        if ! tar -xzf "${gum_tarball}" 2>/dev/null; then
            echo "ERROR: Failed to extract gum"
            rm -f "${gum_tarball}"
            exit 1
        fi
        
        sudo mv "${gum_folder}"/gum /usr/local/bin/gum 2>/dev/null || {
            echo "ERROR: Failed to move gum to /usr/local/bin"
            rm -f "${gum_tarball}"
            exit 1
        }
        
        sudo chmod +x /usr/local/bin/gum
        rm -f "${gum_tarball}"
        rm -rf "${gum_folder}"
        
        if command -v gum > /dev/null 2>&1; then
            gum log --level info "gum installed successfully"
        else
            echo "ERROR: 'gum' installation failed"
            exit 1
        fi
    fi
}

################################## ask functions  #########################################

check_and_ask_input_dependencies() {
    # check for ss (iproute2)
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
}

install_input_dependencies() {
    # Install all approved tools at once
    if [[ ${#TOOLS_TO_INSTALL[@]} -gt 0 ]]; then
        gum log --level info "Installing ${#TOOLS_TO_INSTALL[@]} package(s): ${TOOLS_TO_INSTALL[*]}"
        
        if ! sudo $PACKAGE_MANAGER install -y "${TOOLS_TO_INSTALL[@]}"; then
            gum log --level error "Package installation failed"
            exit 1
        fi
        
        # Verify installations
        for tool in "${TOOLS_TO_INSTALL[@]}"; do
            case $tool in
                iproute2)
                    if command -v ss > /dev/null 2>&1; then
                        gum log --level info "iproute2 installed successfully"
                    else
                        gum log --level error "iproute2 installation failed"
                        exit 1
                    fi
                    ;;
                iptables)
                    if command -v iptables > /dev/null 2>&1; then
                        gum log --level info "iptables installed successfully"
                    else
                        gum log --level error "iptables installation failed"
                        exit 1
                    fi
                    ;;
                nftables)
                    if command -v nft > /dev/null 2>&1; then
                        gum log --level info "nftables installed successfully"
                    else
                        gum log --level error "nftables installation failed"
                        exit 1
                    fi
                    ;;
            esac
        done
    fi
} 

check_and_ask_task_dependencies() {
 
    # check for node_exporter (special case - not from package manager)
    if command -v node_exporter > /dev/null 2>&1; then
        gum log --level info "node_exporter is already installed"
    else
        if gum confirm "Install 'node_exporter'?" --default=yes; then
            INSTALL_NODE_EXPORTER=true
            gum log --level info "node_exporter will be installed"
        else
            gum log --level fatal "node_exporter not installed, it is required for the script to run"
            exit 1
        fi
    fi
    
}

ask_task() {
    # ask for creational 
    if gum confirm "Create a system account for the service?" --default=yes; then
        gum log --level info "system account will be created"
    else
        gum log --level fatal "System account creation declined, cannot proceed"
        exit 1
    fi
    
    if gum confirm "Create systemd service?" --default=yes; then
        gum log --level info "systemd service will be created"
    else
        gum log --level fatal "Service creation declined, cannot proceed"
        exit 1
    fi
    

    
    if gum confirm "Start service immediately after creation?" --default=yes; then
        gum log --level info "service will be started immediately after creation"
        SERVICE_START=true
    else
        gum log --level warn "service will not be started immediately after creation"
        SERVICE_START=false
    fi
}

################################ input functions #########################################

validate_service() {
    # empty or whitespace check
    if [[ -z "${SERVICE// }" ]]; then
        gum log --level error "Service name cannot be empty"
        return 1
    fi

    # invalid characters
    if [[ "${SERVICE}" =~ [^a-zA-Z0-9_-] ]]; then
        gum log --level error "Service name can only contain alphanumeric characters, hyphens, and underscores"
        return 1
    fi

    # systemd service already exists
    if [[ -e "/etc/systemd/system/${SERVICE}.service" ]] || \
       [[ -e "/usr/lib/systemd/system/${SERVICE}.service" ]] || \
       [[ -e "/etc/systemd/system/${SERVICE}.service.d" ]] || \
       [[ -e "/usr/lib/systemd/system/${SERVICE}.service.d" ]]; then
        gum log --level error "Service name already exists"
        return 1
    fi

    # service account already exists
    if getent passwd "${SERVICE}" >/dev/null 2>&1; then
        gum log --level error "Service account already exists"
        return 1
    fi
    
    # existing systemd service (installed, enabled, disabled, masked, static)
    if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${SERVICE}.*"; then
        gum log --level error "Reserved unit name"
        return 1
    fi
    
    if [[ "${SERVICE}" =~ ^(systemd|root|daemon|bin|sys|sync|shutdown|halt|user)$ ]]; then
        gum log --level error "Reserved system service name"
        return 1
    fi
    
    # reserved service template by monc 
    if [[ ${SERVICE} == "template" ]]; then
        gum log --level error "Template service name is not allowed, it's reserved for monc"
        return 1
    fi
}

input_service() {
    SERVICE=$(gum input --prompt "Input the name of service: ")
    until validate_service; do
        SERVICE=$(gum input --prompt "Input the name of service: ")
    done
    gum log --level info "Service name: ${SERVICE}"
}

validate_port() {
    # empty check
    if [[ -z "${PORT}" ]]; then
        gum log --level error "Port cannot be empty"
        return 1
    fi

    # numeric check
    if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
        gum log --level error "Port must be numeric"
        return 1
    fi

    # valid range (combining privileged port check)
    if (( PORT < 1024 || PORT > 65535 )); then
        gum log --level error "Port must be between 1024 and 65535 (privileged ports below 1024 are not allowed)"
        return 1
    fi

    # ephemeral port range
    if [[ -f /proc/sys/net/ipv4/ip_local_port_range ]]; then
        read EPHEMERAL_START EPHEMERAL_END < /proc/sys/net/ipv4/ip_local_port_range
        if (( PORT >= EPHEMERAL_START && PORT <= EPHEMERAL_END )); then
            gum log --level error "Port is in ephemeral range (${EPHEMERAL_START}-${EPHEMERAL_END})"
            return 1
        fi
    fi

    # socket bound ports
    if ss -H -tuln 2>/dev/null | awk '{print $5}' | sed 's/.*://' | grep -qx "${PORT}"; then
        gum log --level error "Port already in use by a running service"
        return 1
    fi

    # iptables NAT ports
    if command -v iptables >/dev/null 2>&1; then
        if sudo iptables -t nat -L -n 2>/dev/null | grep -q "dpt:${PORT}"; then
            gum log --level error "Port already exposed via iptables NAT"
            return 1
        fi
    fi

    # nftables ports
    if command -v nft >/dev/null 2>&1; then
        if sudo nft list ruleset 2>/dev/null | grep -q "dport ${PORT}"; then
            gum log --level error "Port already exposed via nftables"
            return 1
        fi
    fi

    # docker published ports
    if command -v docker >/dev/null 2>&1; then
        if docker context ls --format '{{.Name}}' \
            | xargs -I{} docker --context {} ps --format '{{.Ports}}' \
            | grep -qE "(^|,|\s)(0\.0\.0\.0|\[::\]):${PORT}->"; then
            gum log --level error "Port already published by Docker"
            return 1
        fi
    fi

    # kubernetes NodePort range
    if (( PORT >= 30000 && PORT <= 32767 )); then
        gum log --level error "Port conflicts with Kubernetes NodePort range"
        return 1
    fi
}

input_port() {
    PORT=$(gum input --prompt "Input port: ")
    until validate_port; do
        PORT=$(gum input --prompt "Input port: ")
    done
    gum log --level info "Port: ${PORT}"
}

############################### installations  #########################


install_task_dependencies() {

    # Install node_exporter separately if needed
    if [[ ${INSTALL_NODE_EXPORTER} == true ]]; then
        gum log --level info "Installing node_exporter..."
        
        local ne_arch="${ARCHITECTURE}"
        if [[ ${ARCHITECTURE} == "amd64" ]]; then
            ne_arch="amd64"
        fi
        
        local ne_tarball="node_exporter-${NODE_EXPORTER_VERSION}.${KERNEL}-${ne_arch}.tar.gz"
        local ne_url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${ne_tarball}"
        
        if ! wget -q "${ne_url}"; then
            gum log --level error "Failed to download node_exporter"
            exit 1
        fi
        
        if ! tar -xzf "${ne_tarball}" 2>/dev/null; then
            gum log --level error "Failed to extract node_exporter"
            rm -f "${ne_tarball}"
            exit 1
        fi
        
        sudo mv "./node_exporter-${NODE_EXPORTER_VERSION}.${KERNEL}-${ne_arch}/node_exporter" /usr/local/bin/ || {
            gum log --level error "Failed to move node_exporter to /usr/local/bin"
            rm -f "${ne_tarball}"
            rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.${KERNEL}-${ne_arch}"
            exit 1
        }
        
        rm -f "${ne_tarball}"
        rm -rf "node_exporter-${NODE_EXPORTER_VERSION}.${KERNEL}-${ne_arch}"
        
        if command -v node_exporter > /dev/null 2>&1; then
            gum log --level info "node_exporter installed successfully"
        else
            gum log --level error "node_exporter installation failed"
            exit 1
        fi
    fi
    
    # install template service
    if [[ ${INSTALL_TEMPLATE_SERVICE} == true ]]; then
        gum log --level info "Creating template.service file..."
        cat > template.service <<'EOF'
[Unit]
Description=PLACEHOLDER_SERVICE Service
After=network.target

[Service]
Type=simple
User=PLACEHOLDER_SERVICE
ExecStart=/usr/local/bin/node_exporter --web.listen-address=:PLACEHOLDER_PORT
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        gum log --level info "template.service created successfully"
    fi
}



cleanup_on_failure() {
    local service_name=$1
    gum log --level warn "Cleaning up due to failure..."
    

    # Remove service file if it exists
    if [[ -e "/etc/systemd/system/${service_name}.service" ]]; then
        sudo rm -f "/etc/systemd/system/${service_name}.service"
        gum log --level info "Removed service file"
    fi
    
    # Remove user if it exists
    if getent passwd "${service_name}" >/dev/null 2>&1; then
        sudo userdel "${service_name}" 2>/dev/null
        gum log --level info "Removed service user"
    fi
    
    # Remove generated service file
    if [[ -e "${service_name}.service" ]]; then
        rm -f "${service_name}.service"
    fi
    
    sudo systemctl daemon-reload
}


create_service_file() {
    if [[ ! -e template.service ]]; then
        gum log --level error "template.service file not found"
        exit 1
    fi
    
    gum log --level info "Creating service file for ${SERVICE}..."
    
    if ! sed -e "s/PLACEHOLDER_SERVICE/${SERVICE}/g" -e "s/PLACEHOLDER_PORT/${PORT}/g" template.service > "${SERVICE}.service"; then
        gum log --level error "Failed to create service file"
        exit 1
    fi
    
    gum log --level info "Service file created: ${SERVICE}.service"
}

install_service() {
    gum log --level info "Installing service..."
    
    # Move service file
    if ! sudo mv "${SERVICE}.service" /etc/systemd/system/; then
        gum log --level error "Failed to move service file to /etc/systemd/system/"
        cleanup_on_failure "${SERVICE}"
        exit 1
    fi
    
    # Create service user
    if ! sudo useradd --no-create-home --shell /usr/sbin/nologin "${SERVICE}" 2>/dev/null; then
        gum log --level error "Failed to create service user"
        cleanup_on_failure "${SERVICE}"
        exit 1
    fi
    gum log --level info "Service user created: ${SERVICE}"
    
    # Reload systemd
    if ! sudo systemctl daemon-reload; then
        gum log --level error "Failed to reload systemd"
        cleanup_on_failure "${SERVICE}"
        exit 1
    fi
    
    
    # Enable and start service if requested
    if [[ ${SERVICE_START} == true ]]; then
        if ! sudo systemctl enable "${SERVICE}"; then
            gum log --level error "Failed to enable service"
            cleanup_on_failure "${SERVICE}"
            exit 1
        fi
        gum log --level info "Service enabled: ${SERVICE}"
        
        if ! sudo systemctl start "${SERVICE}"; then
            gum log --level error "Failed to start service"
            gum log --level info "Check status with: sudo systemctl status ${SERVICE}"
            cleanup_on_failure "${SERVICE}"
            exit 1
        fi
        gum log --level info "Service started: ${SERVICE}"
        
        # Show service status
        sudo systemctl status "${SERVICE}" --no-pager
    else
        gum log --level info "Service installed but not started"
        gum log --level info "To start: sudo systemctl start ${SERVICE}"
    fi
}

manage_dependencies() {
    check_system_compatibility
    create_monc_config
    check_and_install_script_dependencies
    check_and_ask_task_dependencies
}

get_inputs() {
    ask_task
    input_service
    input_port
}

setup_service() {
    create_service_file
    install_service
}

################################ perform tasks #########################################

perform_task() {
    manage_dependencies
    check_and_ask_input_dependencies
    install_input_dependencies
    get_inputs
    install_task_dependencies
    setup_service
    gum log --level info "✓ Service installation completed successfully!"
}

########################## calls #########################################################
perform_task