#!/bin/bash

# install.sh - SFP Prerequisites Installation Script

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
TICK="✓"
CROSS="✗"

# Print colored messages
log_success() { printf "${GREEN}${TICK} %s${NC}\n" "$1"; }
log_error() { printf "${RED}${CROSS} %s${NC}\n" "$1" >&2; }
log_warn() { printf "${YELLOW}! %s${NC}\n" "$1"; }
log_info() { printf "• %s\n" "$1"; }

# Check if running with sudo/root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Function to check GitHub token
check_github_token() {
    local token=$1
    log_info "Verifying GitHub token..."
    
    # Check token with GitHub API
    local response=$(curl -s -H "Authorization: Bearer $token" \
                        -H "Accept: application/vnd.github+json" \
                        https://api.github.com/user)
    
    if echo "$response" | grep -q '"login"'; then
        # Verify package access
        local pkg_response=$(curl -s -H "Authorization: Bearer $token" \
                               -H "Accept: application/vnd.github+json" \
                               https://api.github.com/orgs/flxbl-io/packages)
        
        if echo "$pkg_response" | grep -q "sfp-pro"; then
            log_success "GitHub token verified - Has package access"
            # Configure npm for GitHub packages
            echo "//npm.pkg.github.com/:_authToken=$token" > ~/.npmrc
            echo "@flxbl-io:registry=https://npm.pkg.github.com" >> ~/.npmrc
            # Configure Docker for GitHub packages
            echo "$token" | docker login ghcr.io -u USERNAME --password-stdin
            return 0
        else
            log_error "GitHub token lacks package access permissions"
            return 1
        fi
    else
        log_error "Invalid GitHub token"
        return 1
    fi
}

# Install Node.js 20
install_node() {
    log_info "Installing Node.js 20..."
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
        log_success "Node.js $(node --version) installed"
    else
        local version=$(node --version)
        if [[ ${version:1:2} -ge 20 ]]; then
            log_success "Node.js $version already installed"
        else
            log_warn "Updating Node.js to version 20..."
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
            apt-get install -y nodejs
            log_success "Node.js $(node --version) installed"
        fi
    fi
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."
    if ! command -v docker &> /dev/null; then
        # Install Docker's prerequisites
        apt-get update
        apt-get install -y ca-certificates curl gnupg

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        # Add the repository to Apt sources
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

        # Start and enable Docker
        systemctl start docker
        systemctl enable docker

        log_success "Docker installed"
    else
        log_success "Docker already installed"
    fi
}

# Install Infisical CLI
install_infisical() {
    log_info "Installing Infisical CLI..."
    if ! command -v infisical &> /dev/null; then
        curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | bash
        apt-get update
        apt-get install -y infisical
        log_success "Infisical CLI installed"
    else
        log_success "Infisical CLI already installed"
    fi
}

# Install Supabase CLI
install_supabase() {
    log_info "Installing Supabase CLI..."
    if ! command -v supabase &> /dev/null; then
        local version="1.127.3"  # Update this version as needed
        wget -O /tmp/supabase.deb \
            "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_linux_amd64.deb"
        dpkg -i /tmp/supabase.deb || apt-get install -f -y
        rm /tmp/supabase.deb
        log_success "Supabase CLI installed"
    else
        log_success "Supabase CLI already installed"
    fi
}

# Install SFP CLI
install_sfp() {
    log_info "Installing SFP CLI..."
    npm install -g @flxbl-io/sfp@web
    log_success "SFP CLI installed"
}

# Main installation process
main() {
    echo "
╔═══════════════════════════════════════╗
║           SFP Prerequisites           ║
║         Installation Script          ║
╚═══════════════════════════════════════╝
"
    
    # Check if running as root
    check_root

    # Check if GITHUB_TOKEN is provided in environment
    local github_token=${GITHUB_TOKEN:-""}
    
    # If no token in environment, prompt for it
    if [ -z "$github_token" ]; then
        while true; do
            read -p "Enter your GitHub Personal Access Token: " github_token
            if check_github_token "$github_token"; then
                break
            else
                log_error "Please ensure your token has package read access"
                read -p "Would you like to try another token? (y/n) " retry
                if [[ $retry != "y" ]]; then
                    exit 1
                fi
            fi
        done
    else
        if ! check_github_token "$github_token"; then
            log_error "Provided GITHUB_TOKEN is invalid or lacks required permissions"
            exit 1
        fi
    fi

    # Install prerequisites
    apt-get update
    apt-get install -y curl wget jq git

    install_node
    install_docker
    install_infisical
    install_supabase
    install_sfp

    # Final verification
    echo "
Verifying installations:
"
    node --version && log_success "Node.js"
    docker --version && log_success "Docker"
    docker compose version && log_success "Docker Compose"
    infisical --version && log_success "Infisical CLI"
    supabase --version && log_success "Supabase CLI"
    sfp --version && log_success "SFP CLI"

    echo "
╔═══════════════════════════════════════╗
║       Installation Complete! 🎉       ║
╚═══════════════════════════════════════╝

You can now use the 'sfp' command to manage your SFP installation.
Get started with: sfp server init --help
"
}

# Run main function
main "$@"
