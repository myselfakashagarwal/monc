#!/bin/bash

set -euo pipefail

# Global variables
PACKAGE_MANAGER=""
ARCHITECTURE=""
KERNEL="linux"
SERVICE=""
PORT=""
SERVICE_START=false
INSTALL_MYSQL_EXPORTER=false
INSTALL_TEMPLATE_SERVICE=false
CONFIGURE_FIREWALL=false
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
MYSQL_USER=""
MYSQL_PASSWORD=""
declare -a TOOLS_TO_INSTALL=()

# Versions (centralized for easy updates)
GUM_VERSION="0.16.1"
MYSQL_EXPORTER_VERSION="0.15.1"

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

check_and_ask_task_dependencies() {
    # check for ss (iproute2)
    if command -v ss > /dev/null 2>&1; then
        gum log --level info "ss is already installed"
    else
        if gum confirm "Install 'ss' (iproute2)?" --default=yes; then
            TOOLS_TO_INSTALL+=("iproute2")
            gum log --level info "iproute2 will be installed"
        else
            gum log --level fatal "ss not installed, it is required for the script to run"
            exit 1
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
            gum log --level fatal "iptables not installed, it is required for the script to run"
            exit 1
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
            gum log --level fatal "nftables not installed, it is required for the script to run"
            exit 1
        fi
    fi
    
    # check for mysql client
    if command -v mysql > /dev/null 2>&1; then
        gum log --level info "mysql client is already installed"
    else
        if gum confirm "Install mysql client for testing?" --default=yes; then
            if [[ ${PACKAGE_MANAGER} == "apt" ]]; then
                TOOLS_TO_INSTALL+=("mysql-client")
            else
                TOOLS_TO_INSTALL+=("mysql")
            fi
            gum log --level info "mysql client will be installed"
        else
            gum log --level warn "mysql client not installed, connection testing will be skipped"
        fi
    fi
          
    # check for mysqld_exporter (special case - not from package manager)
    if command -v mysqld_exporter > /dev/null 2>&1; then
        gum log --level info "mysqld_exporter is already installed"
    else
        if gum confirm "Install 'mysqld_exporter'?" --default=yes; then
            INSTALL_MYSQL_EXPORTER=true
            gum log --level info "mysqld_exporter will be installed"
        else
            gum log --level fatal "mysqld_exporter not installed, it is required for the script to run"
            exit 1
        fi
    fi
    
    # check for required files and directories
    if [[ ! -e template.service ]]; then
        INSTALL_TEMPLATE_SERVICE=true
        gum log --level warn "template.service not found, will be created"
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
    
    if gum confirm "Configure firewall to allow traffic on the service port?" --default=yes; then
        gum log --level info "firewall will be configured"
        CONFIGURE_FIREWALL=true
    else
        gum log --level warn "firewall will not be configured"
        CONFIGURE_FIREWALL=false
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
    SERVICE=$(gum input --prompt "Input the name of service: " --placeholder "mysql-exporter")
    until validate_service; do
        SERVICE=$(gum input --prompt "Input the name of service: " --placeholder "mysql-exporter")
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
        if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q ":${PORT}->"; then
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
    PORT=$(gum input --prompt "Input exporter port: " --placeholder "9104")
    until validate_port; do
        PORT=$(gum input --prompt "Input exporter port: " --placeholder "9104")
    done
    gum log --level info "Exporter port: ${PORT}"
}

validate_mysql_host() {
    if [[ -z "${MYSQL_HOST// }" ]]; then
        gum log --level error "MySQL host cannot be empty"
        return 1
    fi
    
    # Basic validation for hostname/IP
    if [[ ! "${MYSQL_HOST}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]] && \
       [[ ! "${MYSQL_HOST}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        gum log --level error "Invalid hostname or IP address"
        return 1
    fi
}

input_mysql_host() {
    MYSQL_HOST=$(gum input --prompt "Input MySQL host: " --placeholder "localhost" --value "localhost")
    until validate_mysql_host; do
        MYSQL_HOST=$(gum input --prompt "Input MySQL host: " --placeholder "localhost" --value "localhost")
    done
    gum log --level info "MySQL host: ${MYSQL_HOST}"
}

validate_mysql_port() {
    if [[ -z "${MYSQL_PORT}" ]]; then
        gum log --level error "MySQL port cannot be empty"
        return 1
    fi

    if [[ ! "${MYSQL_PORT}" =~ ^[0-9]+$ ]]; then
        gum log --level error "Port must be numeric"
        return 1
    fi

    if (( MYSQL_PORT < 1 || MYSQL_PORT > 65535 )); then
        gum log --level error "Port must be between 1 and 65535"
        return 1
    fi
}

input_mysql_port() {
    MYSQL_PORT=$(gum input --prompt "Input MySQL port: " --placeholder "3306" --value "3306")
    until validate_mysql_port; do
        MYSQL_PORT=$(gum input --prompt "Input MySQL port: " --placeholder "3306" --value "3306")
    done
    gum log --level info "MySQL port: ${MYSQL_PORT}"
}

validate_mysql_user() {
    if [[ -z "${MYSQL_USER// }" ]]; then
        gum log --level error "MySQL user cannot be empty"
        return 1
    fi
    
    # MySQL username validation (max 32 chars, specific allowed characters)
    if [[ ${#MYSQL_USER} -gt 32 ]]; then
        gum log --level error "MySQL username cannot exceed 32 characters"
        return 1
    fi
    
    if [[ ! "${MYSQL_USER}" =~ ^[a-zA-Z0-9_]+$ ]]; then
        gum log --level error "MySQL username can only contain alphanumeric characters and underscores"
        return 1
    fi
}

input_mysql_user() {
    MYSQL_USER=$(gum input --prompt "Input MySQL username: " --placeholder "exporter")
    until validate_mysql_user; do
        MYSQL_USER=$(gum input --prompt "Input MySQL username: " --placeholder "exporter")
    done
    gum log --level info "MySQL user: ${MYSQL_USER}"
}

input_mysql_password() {
    MYSQL_PASSWORD=$(gum input --prompt "Input MySQL password: " --password)
    
    # Allow empty password but warn
    if [[ -z "${MYSQL_PASSWORD}" ]]; then
        if gum confirm "Password is empty. Continue?" --default=no; then
            gum log --level warn "Using empty password (not recommended)"
        else
            input_mysql_password
            return
        fi
    fi
    
    gum log --level info "MySQL password set"
}

test_mysql_connection() {
    if ! command -v mysql > /dev/null 2>&1; then
        gum log --level warn "mysql client not installed, skipping connection test"
        return 0
    fi
    
    gum log --level info "Testing MySQL connection..."
    
    local mysql_cmd="mysql -h${MYSQL_HOST} -P${MYSQL_PORT} -u${MYSQL_USER}"
    
    if [[ -n "${MYSQL_PASSWORD}" ]]; then
        mysql_cmd="${mysql_cmd} -p${MYSQL_PASSWORD}"
    fi
    
    if ${mysql_cmd} -e "SELECT 1;" >/dev/null 2>&1; then
        gum log --level info "MySQL connection successful"
        
        # Test required privileges
        if ${mysql_cmd} -e "SHOW GLOBAL STATUS;" >/dev/null 2>&1 && \
           ${mysql_cmd} -e "SHOW GLOBAL VARIABLES;" >/dev/null 2>&1; then
            gum log --level info "MySQL user has required privileges"
        else
            gum log --level warn "MySQL user may lack required privileges (PROCESS, REPLICATION CLIENT, SELECT)"
            gum log --level warn "Grant with: GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO '${MYSQL_USER}'@'%';"
        fi
        return 0
    else
        gum log --level error "MySQL connection failed"
        if gum confirm "Continue anyway?" --default=no; then
            gum log --level warn "Proceeding without connection validation"
            return 0
        else
            return 1
        fi
    fi
}

############################### installations  #########################

install_task_dependencies() {
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
                mysql|mysql-client)
                    if command -v mysql > /dev/null 2>&1; then
                        gum log --level info "mysql client installed successfully"
                    else
                        gum log --level error "mysql client installation failed"
                        exit 1
                    fi
                    ;;
            esac
        done
    fi
    
    # Install mysqld_exporter separately if needed
    if [[ ${INSTALL_MYSQL_EXPORTER} == true ]]; then
        gum log --level info "Installing mysqld_exporter..."
        
        local me_arch="${ARCHITECTURE}"
        if [[ ${ARCHITECTURE} == "amd64" ]]; then
            me_arch="amd64"
        fi
        
        local me_tarball="mysqld_exporter-${MYSQL_EXPORTER_VERSION}.${KERNEL}-${me_arch}.tar.gz"
        local me_url="https://github.com/prometheus/mysqld_exporter/releases/download/v${MYSQL_EXPORTER_VERSION}/${me_tarball}"
        
        if ! wget -q "${me_url}"; then
            gum log --level error "Failed to download mysqld_exporter"
            exit 1
        fi
        
        if ! tar -xzf "${me_tarball}" 2>/dev/null; then
            gum log --level error "Failed to extract mysqld_exporter"
            rm -f "${me_tarball}"
            exit 1
        fi
        
        sudo mv "./mysqld_exporter-${MYSQL_EXPORTER_VERSION}.${KERNEL}-${me_arch}/mysqld_exporter" /usr/local/bin/ || {
            gum log --level error "Failed to move mysqld_exporter to /usr/local/bin"
            rm -f "${me_tarball}"
            rm -rf "mysqld_exporter-${MYSQL_EXPORTER_VERSION}.${KERNEL}-${me_arch}"
            exit 1
        }
        
        rm -f "${me_tarball}"
        rm -rf "mysqld_exporter-${MYSQL_EXPORTER_VERSION}.${KERNEL}-${me_arch}"
        
        if command -v mysqld_exporter > /dev/null 2>&1; then
            gum log --level info "mysqld_exporter installed successfully"
        else
            gum log --level error "mysqld_exporter installation failed"
            exit 1
        fi
    fi
    
    # install template service
    if [[ ${INSTALL_TEMPLATE_SERVICE} == true ]]; then
        gum log --level info "Creating template.service file..."
        cat > template.service <<'EOF'
[Unit]
Description=PLACEHOLDER_SERVICE Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=PLACEHOLDER_SERVICE
Environment="DATA_SOURCE_NAME=PLACEHOLDER_USER:PLACEHOLDER_PASSWORD@(PLACEHOLDER_HOST:PLACEHOLDER_MYSQL_PORT)/"
ExecStart=/usr/local/bin/mysqld_exporter --web.listen-address=:PLACEHOLDER_PORT
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
        gum log --level info "template.service created successfully"
    fi
}

############################### firewall functions #########################

detect_active_firewall() {
    local active_firewall=""
    
    # Check for firewalld
    if command -v firewall-cmd >/dev/null 2>&1; then
        if sudo systemctl is-active --quiet firewalld 2>/dev/null; then
            active_firewall="firewalld"
        fi
    fi
    
    # Check for UFW
    if command -v ufw >/dev/null 2>&1; then
        if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
            active_firewall="ufw"
        fi
    fi
    
    # Check for active iptables rules
    if command -v iptables >/dev/null 2>&1; then
        local rule_count=$(sudo iptables -L INPUT -n 2>/dev/null | grep -c "^ACCEPT\|^DROP\|^REJECT" || echo "0")
        if (( rule_count > 0 )) && [[ -z "${active_firewall}" ]]; then
            active_firewall="iptables"
        fi
    fi
    
    # Check for nftables
    if command -v nft >/dev/null 2>&1; then
        if sudo nft list ruleset 2>/dev/null | grep -q "type filter hook"; then
            if [[ -z "${active_firewall}" ]]; then
                active_firewall="nftables"
            fi
        fi
    fi
    
    echo "${active_firewall}"
}

configure_firewalld() {
    local port=$1
    
    gum log --level info "Configuring firewalld for port ${port}..."
    
    # Add port to firewalld
    if ! sudo firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null; then
        gum log --level error "Failed to add port to firewalld"
        return 1
    fi
    
    # Reload firewalld
    if ! sudo firewall-cmd --reload 2>/dev/null; then
        gum log --level error "Failed to reload firewalld"
        return 1
    fi
    
    # Verify the rule
    if sudo firewall-cmd --list-ports 2>/dev/null | grep -q "${port}/tcp"; then
        gum log --level info "Port ${port}/tcp successfully added to firewalld"
        return 0
    else
        gum log --level error "Failed to verify firewalld rule"
        return 1
    fi
}

configure_ufw() {
    local port=$1
    
    gum log --level info "Configuring UFW for port ${port}..."
    
    # Add port to UFW
    if ! sudo ufw allow "${port}/tcp" 2>/dev/null; then
        gum log --level error "Failed to add port to UFW"
        return 1
    fi
    
    # Verify the rule
    if sudo ufw status 2>/dev/null | grep -q "${port}/tcp"; then
        gum log --level info "Port ${port}/tcp successfully added to UFW"
        return 0
    else
        gum log --level error "Failed to verify UFW rule"
        return 1
    fi
}

configure_iptables() {
    local port=$1
    
    gum log --level info "Configuring iptables for port ${port}..."
    
    # Check if rule already exists
    if sudo iptables -C INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null; then
        gum log --level info "iptables rule for port ${port} already exists"
        return 0
    fi
    
    # Add iptables rule
    if ! sudo iptables -A INPUT -p tcp --dport "${port}" -j ACCEPT; then
        gum log --level error "Failed to add iptables rule"
        return 1
    fi
    
    gum log --level info "iptables rule added for port ${port}/tcp"
    
    # Try to save iptables rules (distribution-specific)
    if command -v iptables-save >/dev/null 2>&1; then
        if command -v netfilter-persistent >/dev/null 2>&1; then
            sudo netfilter-persistent save 2>/dev/null && \
                gum log --level info "iptables rules saved with netfilter-persistent"
        elif [[ -e /etc/sysconfig/iptables ]]; then
            sudo iptables-save | sudo tee /etc/sysconfig/iptables >/dev/null && \
                gum log --level info "iptables rules saved to /etc/sysconfig/iptables"
        elif [[ -e /etc/iptables/rules.v4 ]]; then
            sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null && \
                gum log --level info "iptables rules saved to /etc/iptables/rules.v4"
        else
            gum log --level warn "Could not persist iptables rules (no save method found)"
        fi
    fi
    
    return 0
}

configure_nftables() {
    local port=$1
    
    gum log --level info "Configuring nftables for port ${port}..."
    
    # Check if a table exists, create one if not
    if ! sudo nft list tables 2>/dev/null | grep -q "inet filter"; then
        gum log --level info "Creating nftables filter table..."
        sudo nft add table inet filter
        sudo nft add chain inet filter input { type filter hook input priority 0 \; }
    fi
    
    # Add rule to allow port
    if ! sudo nft add rule inet filter input tcp dport "${port}" accept 2>/dev/null; then
        gum log --level error "Failed to add nftables rule"
        return 1
    fi
    
    gum log --level info "nftables rule added for port ${port}/tcp"
    
    # Try to save nftables rules
    if [[ -e /etc/nftables.conf ]]; then
        sudo nft list ruleset | sudo tee /etc/nftables.conf >/dev/null && \
            gum log --level info "nftables rules saved to /etc/nftables.conf"
    else
        gum log --level warn "Could not persist nftables rules (/etc/nftables.conf not found)"
    fi
    
    return 0
}

configure_firewall() {
    if [[ ${CONFIGURE_FIREWALL} != true ]]; then
        gum log --level info "Skipping firewall configuration"
        return 0
    fi
    
    local active_firewall=$(detect_active_firewall)
    
    if [[ -z "${active_firewall}" ]]; then
        gum log --level warn "No active firewall detected"
        gum log --level info "You may need to manually configure your firewall"
        return 0
    fi
    
    gum log --level info "Detected active firewall: ${active_firewall}"
    
    case "${active_firewall}" in
        firewalld)
            configure_firewalld "${PORT}"
            ;;
        ufw)
            configure_ufw "${PORT}"
            ;;
        iptables)
            configure_iptables "${PORT}"
            ;;
        nftables)
            configure_nftables "${PORT}"
            ;;
        *)
            gum log --level warn "Unknown firewall type: ${active_firewall}"
            return 1
            ;;
    esac
}

cleanup_firewall() {
    local port=$1
    local active_firewall=$(detect_active_firewall)
    
    if [[ -z "${active_firewall}" ]]; then
        return 0
    fi
    
    gum log --level info "Removing firewall rule for port ${port}..."
    
    case "${active_firewall}" in
        firewalld)
            sudo firewall-cmd --permanent --remove-port="${port}/tcp" 2>/dev/null
            sudo firewall-cmd --reload 2>/dev/null
            ;;
        ufw)
            sudo ufw delete allow "${port}/tcp" 2>/dev/null
            ;;
        iptables)
            sudo iptables -D INPUT -p tcp --dport "${port}" -j ACCEPT 2>/dev/null
            ;;
        nftables)
            # This is complex for nftables, skip for now
            gum log --level warn "Manual nftables cleanup may be required"
            ;;
    esac
}

cleanup_on_failure() {
    local service_name=$1
    gum log --level warn "Cleaning up due to failure..."
    
    # Remove firewall rule if it was configured
    if [[ ${CONFIGURE_FIREWALL} == true ]]; then
        cleanup_firewall "${PORT}"
    fi
    
    # Remove .my.cnf file
    if [[ -e "/home/${service_name}/.my.cnf" ]]; then
        sudo rm -f "/home/${service_name}/.my.cnf"
        gum log --level info "Removed .my.cnf file"
    fi
    
    # Remove service file if it exists
    if [[ -e "/etc/systemd/system/${service_name}.service" ]]; then
        sudo rm -f "/etc/systemd/system/${service_name}.service"
        gum log --level info "Removed service file"
    fi
    
    # Remove user if it exists
    if getent passwd "${service_name}" >/dev/null 2>&1; then
        sudo userdel -r "${service_name}" 2>/dev/null
        gum log --level info "Removed service user"
    fi
    
    # Remove generated service file
    if [[ -e "${service_name}.service" ]]; then
        rm -f "${service_name}.service"
    fi
    
    sudo systemctl daemon-reload
}

manage_dependencies() {
    check_system_compatibility
    check_and_install_script_dependencies
    check_and_ask_task_dependencies
}

get_inputs() {
    ask_task
    input_service
    input_port
    input_mysql_host
    input_mysql_port
    input_mysql_user
    input_mysql_password
    
    # Test MySQL connection
    until test_mysql_connection; do
        gum log --level warn "Retrying MySQL configuration..."
        input_mysql_host
        input_mysql_port
        input_mysql_user
        input_mysql_password
    done
}

create_service_file() {
    if [[ ! -e template.service ]]; then
        gum log --level error "template.service file not found"
        exit 1
    fi
    
    gum log --level info "Creating service file for ${SERVICE}..."
    
    # Escape special characters in password for sed
    local escaped_password=$(echo "${MYSQL_PASSWORD}" | sed 's/[&/\]/\\&/g')
    
    if ! sed -e "s/PLACEHOLDER_SERVICE/${SERVICE}/g" \
             -e "s/PLACEHOLDER_PORT/${PORT}/g" \
             -e "s/PLACEHOLDER_USER/${MYSQL_USER}/g" \
             -e "s/PLACEHOLDER_PASSWORD/${escaped_password}/g" \
             -e "s/PLACEHOLDER_HOST/${MYSQL_HOST}/g" \
             -e "s/PLACEHOLDER_MYSQL_PORT/${MYSQL_PORT}/g" \
             template.service > "${SERVICE}.service"; then
        gum log --level error "Failed to create service file"
        exit 1
    fi
    
    gum log --level info "Service file created: ${SERVICE}.service"
}

install_service() {
    gum log --level info "Installing service..."
    
    # Create service user with home directory for .my.cnf
    if ! sudo useradd --system --shell /usr/sbin/nologin --create-home "${SERVICE}" 2>/dev/null; then
        gum log --level error "Failed to create service user"
        cleanup_on_failure "${SERVICE}"
        exit 1
    fi
    gum log --level info "Service user created: ${SERVICE}"
    
    # Move service file
    if ! sudo mv "${SERVICE}.service" /etc/systemd/system/; then
        gum log --level error "Failed to move service file to /etc/systemd/system/"
        cleanup_on_failure "${SERVICE}"
        exit 1
    fi
    
    # Reload systemd
    if ! sudo systemctl daemon-reload; then
        gum log --level error "Failed to reload systemd"
        cleanup_on_failure "${SERVICE}"
        exit 1
    fi
    
    # Configure firewall before starting service
    if ! configure_firewall; then
        gum log --level warn "Firewall configuration failed, but continuing..."
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
            gum log --level info "Check logs with: sudo journalctl -u ${SERVICE} -n 50"
            cleanup_on_failure "${SERVICE}"
            exit 1
        fi
        gum log --level info "Service started: ${SERVICE}"
        
        # Wait a moment for the service to initialize
        sleep 2
        
        # Show service status
        sudo systemctl status "${SERVICE}" --no-pager
        
        # Test if metrics endpoint is responding
        if command -v curl >/dev/null 2>&1; then
            gum log --level info "Testing metrics endpoint..."
            if curl -s "http://localhost:${PORT}/metrics" | head -n 5; then
                gum log --level info "Metrics endpoint is responding"
            else
                gum log --level warn "Could not reach metrics endpoint"
            fi
        fi
    else
        gum log --level info "Service installed but not started"
        gum log --level info "To start: sudo systemctl start ${SERVICE}"
        gum log --level info "To enable: sudo systemctl enable ${SERVICE}"
    fi
}

setup_service() {
    create_service_file
    install_service
}

################################ perform tasks #########################################

perform_task() {
    manage_dependencies
    get_inputs
    install_task_dependencies
    setup_service
    gum log --level info "✓ MySQL Exporter service installation completed successfully!"
    gum log --level info "Metrics available at: http://localhost:${PORT}/metrics"
}

########################## calls #########################################################
perform_task