# SFP Installation Script

This script handles the installation and updates of SFP CLI and its prerequisites.

## Quick Start

### Basic Installation
Install the latest version of SFP and all prerequisites:
```bash
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash
```

### Installation with Pre-configured Token
```bash
export FLXBL_NPM_REGISTRY_KEY="your-github-token"
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash
```

## Update Options

### Update SFP CLI Only
Update to the latest version:
```bash
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- --update
```

### Install/Update to Specific Version
```bash
# Full installation with specific version
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- --version 1.2.3

# Update only to specific version
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- --update --version 1.2.3
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `-u, --update` | Update only the SFP CLI, skip other installations |
| `-v, --version VERSION` | Install/update to a specific version |
| `-h, --help` | Show help message |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `FLXBL_NPM_REGISTRY_KEY` | GitHub token for npm registry authentication |

## Important Notes

1. The script requires sudo access to install system-wide packages.
2. The `-E` flag with sudo preserves environment variables (including `FLXBL_NPM_REGISTRY_KEY`).
3. If `FLXBL_NPM_REGISTRY_KEY` is not set, the script will prompt for it.
4. Use `-s --` when passing arguments through curl pipe to bash.

## Prerequisites Installed

When running a full installation (without `--update`), the script installs:

- Node.js 20
- Docker & Docker Compose
- Infisical CLI
- Supabase CLI
- SFP CLI

## Examples

### Basic Usage
```bash
# Full installation
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash

# Show help
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- --help
```

### Version Management
```bash
# Update to specific version
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- -u -v 1.2.3

# Update to latest version
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- --update
```

### With Pre-configured Token
```bash
# Set token and install
export FLXBL_NPM_REGISTRY_KEY="your-github-token"
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash

# Set token and update to specific version
export FLXBL_NPM_REGISTRY_KEY="your-github-token"
curl -fsSL https://raw.githubusercontent.com/flxbl-io/sfp-pro-installation/main/install.sh | sudo -E bash -s -- --update --version 1.2.3
```

## Troubleshooting

1. **Token Authentication Failed**
   - Ensure your GitHub token has the required permissions (read:packages)
   - Verify the token has access to the flxbl-io organization's packages

2. **Command Line Arguments Not Working**
   - When using curl with pipe to bash, ensure you're using `-s --` before your arguments
   - Example: `| sudo -E bash -s -- --update`

3. **Environment Variables Not Preserved**
   - Make sure you're using `sudo -E` to preserve environment variables
   - Set the token in the same session where you run the script
