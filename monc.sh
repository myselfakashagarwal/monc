#!/bin/bash

# Define GUM_VERSION at the top
GUM_VERSION="0.14.0"  # Set appropriate version

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
        echo "INFO: wget is installed" > /dev/null
    else
        echo "INFO: Installing wget..." > /dev/null
        if sudo $PACKAGE_MANAGER install wget -y > /dev/null 2>&1; then
            echo "INFO: wget installed successfully" > /dev/null
        else
            echo "FATAL: 'wget' installation failed" > /dev/null
            exit 1
        fi
    fi
    
    # install gum 
    if command -v gum > /dev/null 2>&1; then
        echo "INFO: gum is installed" > /dev/null
    else
        echo "INFO: Installing gum..." > /dev/null
        local gum_arch="${ARCHITECTURE}"
        if [[ ${ARCHITECTURE} == "amd64" ]]; then
            gum_arch="x86_64"
        fi
        
        local gum_tarball="gum_${GUM_VERSION}_Linux_${gum_arch}.tar.gz"
        local gum_folder="gum_${GUM_VERSION}_Linux_${gum_arch}"
        local gum_url="https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/${gum_tarball}"
        
        if ! wget -q "${gum_url}"; then
            echo "ERROR: Failed to download gum" > /dev/null
            exit 1
        fi
            
        if ! tar -xzf "${gum_tarball}" 2>/dev/null; then
            echo "ERROR: Failed to extract gum" > /dev/null
            rm -f "${gum_tarball}"
            exit 1
        fi
        
        sudo mv "${gum_folder}"/gum /usr/local/bin/gum 2>/dev/null || {
            echo "ERROR: Failed to move gum to /usr/local/bin" > /dev/null
            rm -f "${gum_tarball}"
            exit 1
        }
        
        sudo chmod +x /usr/local/bin/gum
        rm -f "${gum_tarball}"
        rm -rf "${gum_folder}"
        
        if command -v gum > /dev/null 2>&1; then
            gum log --level info "gum installed successfully" > /dev/null
        else
            echo "ERROR: 'gum' installation failed" > /dev/null
            exit 1
        fi
    fi
    
    if command -v git > /dev/null 2>&1; then
        echo "git is already installed"
    else
        sudo $PACKAGE_MANAGER install -y git
        gum log --level info "git installed successfully" > /dev/null
    fi
    
    # checking for config files for script if not found create it 
        mkdir -p ~/.config/monc/export/databases/mysql > /dev/null
        mkdir -p ~/.config/monc/export/systems/node > /dev/null
        mkdir -p ~/.config/monc/export/endpoints/blackbox > /dev/null
        mkdir -p ~/.config/monc/store/prometheus > /dev/null
        mkdir -p ~/.config/monc/visualize/grafana > /dev/null
    
    if [[ ! -e ~/monc ]]; then 
        git clone https://github.com/myselfakashagarwal/monc.git ~/monc
    fi
    
}

check_system_compatibility
check_and_install_script_dependencies

# Evaluating all options and arguments 
NUMBER_OF_ARGUMENTS=$#
if [[ $NUMBER_OF_ARGUMENTS -eq 0 ]]; then
  echo "NO ARGUMENT PASSED...."
  exit 0
else
  while [[ $# -gt 0 ]]; do
    case "$1" in
        --init)
            gum log --level info "You are ready to go!"
            shift
            exit 0
        ;;
        --help)
            shift
        ;;
        --create-export)
            export_type=$(gum choose "mysql" "node" "blackbox")
            if [[ $export_type == "mysql" ]]; then
                bash ~/monc/export/databases/mysql/mysql_exporter.sh
            elif [[ $export_type == "node" ]]; then
                bash ~/monc/export/systems/node/node_exporter.sh
            elif [[ $export_type == "blackbox" ]]; then
                bash ~/monc/export/endpoints/blackbox/blackbox_exporter.sh
            else 
                gum log --level error "Invalid selection"
            fi
            shift
        ;;
        --remove-export)
            export_type=$(gum choose "mysql" "node" "blackbox")
            if [[ $export_type == "mysql" ]]; then
                if [[ -z $(ls ~/.config/monc/export/databases/mysql) ]]; then
                    gum log --level error "No MySQL exports found"
                else
                    export=$(gum choose $(ls ~/.config/monc/export/databases/mysql))
                    if [[ -z $export ]]; then
                        gum log --level error "No MySQL exports found"
                    else
                        gum confirm  "Are you sure you want to remove ${export}?" && {
                            sudo systemctl stop "${export}" 2>/dev/null || true
                            sudo systemctl disable "${export}" 2>/dev/null || true
                            sudo rm -f "/etc/systemd/system/${export}.service"
                            sudo systemctl daemon-reload
                            sudo userdel -r "${export}" 2>/dev/null || true
                            gum log --level info "Export removed: ${export}"
                        }
                    fi
                fi
            elif [[ $export_type == "node" ]]; then
                if [[ -z $(ls ~/.config/monc/export/systems/node) ]]; then
                    gum log --level error "No Node exports found"
                else
                    export=$(gum choose $(ls ~/.config/monc/export/systems/node))
                    if [[ -z $export ]]; then
                        gum log --level error "No Node exports found"
                    else
                        gum confirm  "Are you sure you want to remove ${export}?" && {
                            sudo systemctl stop "${export}" 2>/dev/null || true
                            sudo systemctl disable "${export}" 2>/dev/null || true
                            sudo rm -f "/etc/systemd/system/${export}.service"
                            sudo systemctl daemon-reload
                            sudo userdel -r "${export}" 2>/dev/null || true
                            gum log --level info "Export removed: ${export}"
                        }
                    fi
                fi
            elif [[ $export_type == "blackbox" ]]; then
                if [[ -z $(ls ~/.config/monc/export/endpoints/blackbox) ]]; then
                    gum log --level error "No Blackbox exports found"
                else
                    export=$(gum choose $(ls ~/.config/monc/export/endpoints/blackbox))
                    if [[ -z $export ]]; then
                        gum log --level error "No Blackbox exports found"
                    else
                        gum confirm "Are you sure you want to remove ${export}?" && {
                            docker context use default
                            docker kill "${export}_blackbox" 2>/dev/null || true
                            docker kill "${export}_bconman" 2>/dev/null || true 
                            docker rm "${export}_blackbox" 2>/dev/null || true
                            docker rm "${export}_bconman" 2>/dev/null || true
                            docker network rm "${export}_default" 2>/dev/null || true
                            docker context rm "${export}" 2>/dev/null || true
                            gum log --level info "Export removed: ${export}"
                            sudo rm -r ~/.config/monc/export/endpoints/blackbox/${export}
                        }
                    fi
                fi
            else 
                gum log --level error "Invalid selection"
            fi
            shift
        ;;
        --list-exports)
            gum log --level info "mysql"
            ls ~/.config/monc/export/databases/mysql | xargs echo 
            gum log --level info "node"
            ls ~/.config/monc/export/systems/node | xargs echo
            gum log --level info "systems"
            ls ~/.config/monc/export/endpoints/blackbox | xargs echo
            exit 0;
        ;;
        *)
            echo "Unknown option: $1"
            shift 
        ;;
    esac
  done
fi