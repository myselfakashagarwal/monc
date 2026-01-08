#!/bin/bash

# global variables
PACKAGE_MANAGER=""
ARCHITECTURE=""
KERNEL="linux"
GUM_VERSION="0.16.1"
declare -a TOOLS_TO_INSTALL=()
CONTEXT=""
BLACKBOX_EXPORTER_PORT=""
BCONMAN_PORT=""
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
    if command -v git > /dev/null 2>&1; then
        gum log --level info "git is already installed"
    else
        if gum confirm "Install 'git'?" --default=yes; then
            INSTALL_GIT=true
            gum log --level info "git will be installed"
        else
            gum log --level warn "git not installed, its required for the task"
        fi
    fi
    if command -v docker > /dev/null 2>&1; then
        gum log --level info "docker is already installed"
    else
        if gum confirm "Install 'docker'?" --default=yes; then
            INSTALL_DOCKER=true
            gum log --level info "docker will be installed"
        else
            gum log --level fatal "docker not installed, its required for the task"
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
    if [[ ${INSTALL_GIT} == true ]]; then
        gum log --level info "Installing Git"
        if [[ $PACKAGE_MANAGER == "yum" ]]; then
            sudo yum install -y git > /dev/null 2>&1
        else
            sudo apt install -y git > /dev/null 2>&1
        fi
        if command -v git > /dev/null 2>&1; then
            gum log --level info "Git installed successfully"
        else
            gum log --level error "Git installation failed"
            exit 1
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

input_blackbox_exporter_port() {
    BLACKBOX_EXPORTER_PORT=$(gum input --prompt "Input Blackbox Exporter port: ")
    until validate_port "${BLACKBOX_EXPORTER_PORT}" "Blackbox Exporter port"; do
        BLACKBOX_EXPORTER_PORT=$(gum input --prompt "Input Blackbox Exporter port: ")
    done
    gum log --level info "Blackbox Exporter Port: ${BLACKBOX_EXPORTER_PORT}"
}

input_bconman_port() {
    BCONMAN_PORT=$(gum input --prompt "Input Bconman port: ")
    until validate_port "${BCONMAN_PORT}" "Bconman port"; do
        BCONMAN_PORT=$(gum input --prompt "Input Bconman port: ")
    done
    gum log --level info "Bconman Port: ${BCONMAN_PORT}"
}

ask_task() {
    if gum confirm "Create context ?" --default=yes; then
        gum log --level info "context will be created"
    else
        gum log --level fatal "Context creation is required for the task"
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
    input_blackbox_exporter_port
    input_bconman_port
}


setup_compose_and_start() {
    # get the exporter code repo 
    gum log --level info "Cloning repository..."
    git clone https://github.com/hackctl/bman.git ~/.config/monc/export/endpoints/blackbox/$CONTEXT
    
    # setup the env file
    cd ~/.config/monc/export/endpoints/blackbox/$CONTEXT
    
    gum log --level info "Setting up environment configuration..."
    
    # Update specific variables in .env file, preserving other content
    if [[ -f .env ]]; then
        # Update existing variables or add if not present
        sed -i "s/^BLACKBOX_EXPORTER_PORT=.*/BLACKBOX_EXPORTER_PORT=${BLACKBOX_EXPORTER_PORT}/" .env
        sed -i "s/^BLACKBOX_EXPORTER_CONTAINER_NAME=.*/BLACKBOX_EXPORTER_CONTAINER_NAME=${CONTEXT}_blackbox/" .env
        sed -i "s/^BCONMAN_PORT=.*/BCONMAN_PORT=${BCONMAN_PORT}/" .env
        sed -i "s/^BCONMAN_CONTAINER_NAME=.*/BCONMAN_CONTAINER_NAME=${CONTEXT}_bconman/" .env
        
        # Add variables if they don't exist
        grep -q "^BLACKBOX_EXPORTER_PORT=" .env || echo "BLACKBOX_EXPORTER_PORT=${BLACKBOX_EXPORTER_PORT}" >> .env
        grep -q "^BLACKBOX_EXPORTER_CONTAINER_NAME=" .env || echo "BLACKBOX_EXPORTER_CONTAINER_NAME=${CONTEXT}_blackbox" >> .env
        grep -q "^BCONMAN_PORT=" .env || echo "BCONMAN_PORT=${BCONMAN_PORT}" >> .env
        grep -q "^BCONMAN_CONTAINER_NAME=" .env || echo "BCONMAN_CONTAINER_NAME=${CONTEXT}_bconman" >> .env
    else
        # Create new .env file if it doesn't exist
        cat > .env << EOF
BLACKBOX_EXPORTER_PORT=${BLACKBOX_EXPORTER_PORT}
BLACKBOX_EXPORTER_CONTAINER_NAME=${CONTEXT}_blackbox
BCONMAN_PORT=${BCONMAN_PORT}
BCONMAN_CONTAINER_NAME=${CONTEXT}_bconman
EOF
    fi
    
    gum log --level info "Creating and configuring Docker context..."
    
    # setup docker context and start compose
    sudo docker context use default > /dev/null 2>&1
    sudo docker context create $CONTEXT > /dev/null 2>&1
    sudo docker context use $CONTEXT > /dev/null 2>&1
    
    gum log --level info "Starting containers..."
    sudo docker compose -f bman.yml up -d
    
    gum log --level info "Setup completed successfully!"
}

perform_task() {
    create_monc_config
    manage_dependencies
    get_inputs
    setup_compose_and_start
}

########################## calls ################################
perform_task