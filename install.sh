#!/bin/bash

# Set strict error handling
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

# Global cleanup function
cleanup_script() {
    log_info "Performing final cleanup..."
    find /tmp -name 'npm.*.rc' -type f -mmin -5 -exec rm -f {} \;
    log_success "Cleanup completed"
}

# Set up script-level cleanup trap
trap cleanup_script EXIT SIGINT SIGTERM ERR

# Detect if system is Fedora-based (RHEL, CentOS, Amazon Linux) or Debian-based
detect_os_family() {
    if [ -f /etc/redhat-release ] || [ -f /etc/system-release ]; then
        echo "fedora"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Package manager wrapper
pkg_install() {
    local os_family=$1
    shift
    local packages=("$@")
    
    case "$os_family" in
        "fedora")
            yum install -y "${packages[@]}"
            ;;
        "debian")
            apt-get install -y "${packages[@]}"
            ;;
        *)
            log_error "Unsupported OS family"
            exit 1
            ;;
    esac
}

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
    
    local response=$(curl -s -H "Authorization: Bearer $token" \
                        -H "Accept: application/vnd.github+json" \
                        https://api.github.com/user)
    
    if echo "$response" | grep -q '"login"'; then
        local pkg_response=$(curl -s -H "Authorization: Bearer $token" \
                               -H "Accept: application/vnd.github+json" \
                               "https://api.github.com/orgs/flxbl-io/packages?package_type=npm")
        
        if echo "$pkg_response" | grep -q "sfp"; then
            log_success "GitHub token verified - Has package access"
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
    local os_family=$1
    log_info "Installing Node.js 20..."
    
    # Check if we're on ARM64 Amazon Linux 2
    local is_arm64_al2=false
    if [ "$os_family" = "fedora" ] && grep -q "Amazon Linux release 2" /etc/system-release 2>/dev/null; then
        if [ "$(uname -m)" = "aarch64" ]; then
            is_arm64_al2=true
        fi
    fi
    
    if [ "$is_arm64_al2" = true ]; then
        log_info "Detected ARM64 Amazon Linux 2, using nvm for installation..."
        
        # Install nvm
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        
        # Load nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        # Install Node.js 20
        nvm install 20
        nvm use 20
        
        # Make it available system-wide
        local node_path=$(which node)
        local npm_path=$(which npm)
        
        if [ -n "$node_path" ] && [ -n "$npm_path" ]; then
            ln -sf "$node_path" /usr/local/bin/node
            ln -sf "$npm_path" /usr/local/bin/npm
            log_success "Node.js $(node --version) installed via nvm"
        else
            log_error "Failed to install Node.js via nvm"
            return 1
        fi
    else
        if ! command -v node &> /dev/null; then
            case "$os_family" in
                "fedora")
                    curl -sL https://rpm.nodesource.com/setup_20.x | bash -
                    yum install -y nodejs
                    ;;
                "debian")
                    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                    apt-get install -y nodejs
                    ;;
            esac
            log_success "Node.js $(node --version) installed"
        else
            local version=$(node --version)
            if [[ ${version:1:2} -ge 20 ]]; then
                log_success "Node.js $version already installed"
            else
                log_warn "Updating Node.js to version 20..."
                case "$os_family" in
                    "fedora")
                        curl -sL https://rpm.nodesource.com/setup_20.x | bash -
                        yum install -y nodejs
                        ;;
                    "debian")
                        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                        apt-get install -y nodejs
                        ;;
                esac
                log_success "Node.js $(node --version) installed"
            fi
        fi
    fi
}

# Install Docker
install_docker() {
    local os_family=$1
    log_info "Installing Docker..."
    
    if ! command -v docker &> /dev/null; then
        case "$os_family" in
            "fedora")
                if grep -q "Amazon Linux" /etc/system-release 2>/dev/null; then
                    amazon-linux-extras install docker -y
                else
                    yum install -y docker
                fi
                systemctl start docker
                systemctl enable docker
                # Install Docker Compose
                mkdir -p /usr/local/lib/docker/cli-plugins/
                curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
                chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
                ;;
            "debian")
                apt-get update
                apt-get install -y ca-certificates curl gnupg
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
                chmod a+r /etc/apt/keyrings/docker.asc
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
        esac
        log_success "Docker installed"
    else
        log_success "Docker already installed"
    fi
}

# Install Infisical CLI
install_infisical() {
    local os_family=$1
    log_info "Installing Infisical CLI..."
    
    if ! command -v infisical &> /dev/null; then
        case "$os_family" in
            "fedora")
                curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.rpm.sh' | bash
                yum install -y infisical
                ;;
            "debian")
                curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.deb.sh' | bash
                apt-get update
                apt-get install -y infisical
                ;;
        esac
        log_success "Infisical CLI installed"
    else
        log_success "Infisical CLI already installed"
    fi
}

# Install Supabase CLI
install_supabase() {
    local os_family=$1
    log_info "Installing Supabase CLI..."
    
    if ! command -v supabase &> /dev/null; then
        local version="2.0.0"
        case "$os_family" in
            "fedora")
                wget -O /tmp/supabase.rpm \
                    "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_linux_amd64.rpm"
                rpm -i /tmp/supabase.rpm
                rm /tmp/supabase.rpm
                ;;
            "debian")
                wget -O /tmp/supabase.deb \
                    "https://github.com/supabase/cli/releases/download/v${version}/supabase_${version}_linux_amd64.deb"
                dpkg -i /tmp/supabase.deb || apt-get install -f -y
                rm /tmp/supabase.deb
                ;;
        esac
        log_success "Supabase CLI installed"
    else
        log_success "Supabase CLI already installed"
    fi
}

# Function to run npm commands with authentication
npm_install_authenticated() {
    local package=$1
    local version=$2
    local token=${FLXBL_NPM_REGISTRY_KEY:-$3}
    local temp_npmrc=""
    
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
    temp_npmrc=$(mktemp)
    
    {
        echo "@flxbl-io:registry=https://npm.pkg.github.com/"
        echo "//npm.pkg.github.com/:_authToken=${token}"
        echo "registry=https://registry.npmjs.org/"
    } > "$temp_npmrc"
    
    if NPM_CONFIG_USERCONFIG="$temp_npmrc" npm install -g "${full_package}"; then
        log_success "Successfully installed ${full_package}"
        rm -f "$temp_npmrc"
        return 0
    else
        log_error "Failed to install ${full_package}"
        rm -f "$temp_npmrc"
        return 1
    fi
}

# Install SFP function
install_sfp() {
    local version=$1
    log_info "Installing/Updating SFP CLI..."
    
    local current_version=""
    if command -v sfp &> /dev/null; then
        current_version=$(sfp --version 2>/dev/null || echo "unknown")
        log_info "Current SFP CLI version: ${current_version}"
    fi
    
    if [ -z "$version" ] || [ "$version" = "@web" ]; then
        log_info "Target: latest version (@web)"
    else
        log_info "Target: version ${version}"
    fi
    
    if ! npm_install_authenticated "@flxbl-io/sfp" "$version" "$FLXBL_NPM_REGISTRY_KEY"; then
        log_error "Failed to install/update SFP CLI"
        return 1
    fi
    
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
    echo "
╔═══════════════════════════════════════╗
║           SFP Prerequisites           ║
║         Installation Script           ║
╚═══════════════════════════════════════╝
"
    
    # Check if running as root
    check_root

    # Detect OS family
    local os_family=$(detect_os_family)
    log_info "Detected OS family: $os_family"
    
    if [ "$os_family" = "unknown" ]; then
        log_error "Unsupported operating system"
        exit 1
    fi

    # Update package manager and install basic tools
    case "$os_family" in
        "fedora")
            yum update -y
            yum install -y curl wget jq git
            ;;
        "debian")
            apt-get update
            apt-get install -y curl wget jq git
            ;;
    esac

    # Check GitHub token
    if ! check_github_token "$FLXBL_NPM_REGISTRY_KEY"; then
        log_error "Invalid or missing GitHub token"
        exit 1
    fi

    # Install all prerequisites
    install_node "$os_family"
    install_docker "$os_family"
    install_infisical "$os_family"
    install_supabase "$os_family"
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

# Execute main
main
