#!/bin/bash

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
    log_info "Checking user access..."
    local response=$(curl -s -H "Authorization: Bearer $token" \
                        -H "Accept: application/vnd.github+json" \
                        https://api.github.com/user)
    
    if echo "$response" | grep -q '"login"'; then
        # Verify package access specifically for npm packages
        log_info "Checking package access..."
        local pkg_response=$(curl -s -H "Authorization: Bearer $token" \
                               -H "Accept: application/vnd.github+json" \
                               "https://api.github.com/orgs/flxbl-io/packages?package_type=npm")
        
        if echo "$pkg_response" | grep -q "sfp"; then
            log_success "GitHub token verified - Has package access"
            return 0
        else
            log_error "GitHub token lacks package access permissions"
            log_error "Make sure your token has read:packages scope"
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

# Function to show usage/help
show_usage() {
    echo "
Usage: $0 [options]

Options:
    -u, --update              Update only the SFP CLI, skip other installations
    -v, --version VERSION     Install/update to a specific version of SFP CLI
                             (e.g., --version 1.2.3 or @web for latest)
    -h, --help               Show this help message

Environment variables:
    FLXBL_NPM_REGISTRY_KEY    GitHub token for npm registry authentication
"
}

# Function to run npm commands with authentication
npm_install_authenticated() {
    local package=$1
    local version=$2
    local token=${FLXBL_NPM_REGISTRY_KEY:-$3}
    
    if [ -z "$token" ]; then
        log_error "No npm registry token provided. Please set FLXBL_NPM_REGISTRY_KEY"
        return 1
    fi

    local full_package
    if [ -z "$version" ] || [ "$version" = "@web" ]; then
        full_package="${package}@web"
    else
        full_package="${package}@${version}"
    fi

    log_info "Installing ${full_package}..."

    # Use --auth-token flag directly with npm command
    if NPM_CONFIG_REGISTRY=https://npm.pkg.github.com \
       npm install -g --auth-token="${token}" "${full_package}"; then
        log_success "Successfully installed ${full_package}"
        return 0
    else
        log_error "Failed to install ${full_package}"
        return 1
    fi
}

# Install SFP function
install_sfp() {
    local version=$1
    log_info "Installing/Updating SFP CLI..."
    
    # Check if sfp is already installed
    local current_version=""
    if command -v sfp &> /dev/null; then
        current_version=$(sfp --version 2>/dev/null || echo "unknown")
        log_info "Current SFP CLI version: ${current_version}"
    fi
    
    # Show target version
    if [ -z "$version" ] || [ "$version" = "@web" ]; then
        log_info "Target: latest version (@web)"
    else
        log_info "Target: version ${version}"
    fi
    
    if ! npm_install_authenticated "@flxbl-io/sfp" "$version" "$FLXBL_NPM_REGISTRY_KEY"; then
        log_error "Failed to install/update SFP CLI"
        return 1
    fi
    
    # Show new version after update
    if command -v sfp &> /dev/null; then
        local new_version=$(sfp --version 2>/dev/null || echo "unknown")
        if [ "$current_version" != "$new_version" ]; then
            log_success "SFP CLI updated from ${current_version} to ${new_version}"
        else
            log_success "SFP CLI version ${new_version} is current"
        fi
    fi
}

# Main function
main() {
    local update_only=false
    local target_version=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--update)
                update_only=true
                shift
                ;;
            -v|--version)
                if [ -z "$2" ]; then
                    log_error "Version argument is required for -v|--version"
                    show_usage
                    exit 1
                fi
                target_version="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    if [ "$update_only" = true ]; then
        echo "
╔═══════════════════════════════════════╗
║           SFP CLI Updater            ║
╚═══════════════════════════════════════╝
"
        if [ ! -z "$target_version" ]; then
            echo "Target Version: $target_version"
        fi
    else
        echo "
╔═══════════════════════════════════════╗
║           SFP Prerequisites           ║
║         Installation Script          ║
╚═══════════════════════════════════════╝
"
        if [ ! -z "$target_version" ]; then
            echo "Target SFP Version: $target_version"
        fi
    fi
    
    # Check if running as root
    check_root

    # Check if FLXBL_NPM_REGISTRY_KEY is provided in environment
    local github_token=${FLXBL_NPM_REGISTRY_KEY:-""}
    
    # If no token in environment, prompt for it
    if [ -z "$github_token" ]; then
        log_warn "FLXBL_NPM_REGISTRY_KEY not set"
        while true; do
            read -p "Enter your GitHub Personal Access Token: " github_token
            export FLXBL_NPM_REGISTRY_KEY="$github_token"
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
            log_error "Provided FLXBL_NPM_REGISTRY_KEY is invalid or lacks required permissions"
            exit 1
        fi
    fi

    if [ "$update_only" = true ]; then
        # Only update SFP CLI
        install_sfp "$target_version"
        
        echo "
╔═══════════════════════════════════════╗
║         Update Complete! 🎉          ║
╚═══════════════════════════════════════╝
"
        exit 0
    fi

    # Full installation
    apt-get update
    apt-get install -y curl wget jq git

    # Install all prerequisites
    install_node
    install_docker
    install_infisical
    install_supabase
    install_sfp "$target_version"

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

# Execute main with all arguments
main "$@"
