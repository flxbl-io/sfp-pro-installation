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

Examples:
    $0                        # Full installation with latest version
    $0 --update              # Update SFP CLI to latest version
    $0 --version 1.2.3       # Full installation with specific version
    $0 -u -v 1.2.3          # Update only SFP CLI to version 1.2.3
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

# Update the install_sfp function to handle specific versions
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

# Update main function to handle version flag
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
            export FLXBL_NPM_REGISTRY_KEY="$github_token"  # Set it in environment for npm commands
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
    else
        # Full installation
        apt-get update
        apt-get install -y curl wget jq git

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
    fi
}
