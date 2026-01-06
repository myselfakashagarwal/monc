#!/bin/bash

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
    
    # checking for config files for script if not found create it 
    if [[ ! -d ~/.config/monc ]]; then
        mkdir -p ~/.config/monc/exports/databases
        mkdir -p ~/.config/monc/exports/databases/mysql
        mkdir -p ~/.config/monc/exports/systems
        mkdir -p ~/.config/monc/exports/systems/node
        mkdir -p ~/.config/monc/exports/endpoints
        mkdir -p ~/.config/monc/stores
        mkdir -p ~/.config/monc/stores/prometheus
        mkdir -p ~/.config/monc/visualizations
        mkdir -p ~/.config/monc/visualizations/grafana
    fi
    
}

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
          exit 0
      shift 2
      ;;
      --help)
          echo "

          $> dstroman [OPTION] [ARGUMENT]

          OPTION/FLAG         ARGUMENT        USECASE   
          --init              <none>          To install dependencies & initialize configuration   

          "
          exit 0;
      shift 2;
      ;;
      --list-exports)
            DATABASES_EXPORTS=$(ls ~/.config/monc/exports/databases/mysql 2>/dev/null || true)
            SYSTEMS_EXPORTS=$(ls ~/.config/monc/exports/systems/node 2>/dev/null || true)
            ENDPOINTS_EXPORTS=$(ls ~/.config/monc/exports/endpoints 2>/dev/null || true)
      ;;
      *)
        echo "Unknown option: $1"
      shift 
      ;;
    esac
  done
fi