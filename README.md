# Proxmox Cloud-Init VM Template Creator

A bash script to automate the creation of cloud-init enabled VM templates on Proxmox VE. This script downloads Ubuntu cloud images, customizes them with qemu-guest-agent, and configures cloud-init settings for easy VM deployment.

## Features

- 🚀 **Automated Template Creation**: Downloads and configures Ubuntu cloud images (20.04, 22.04, 24.04 LTS)
- 🔐 **Cloud-Init Configuration**: Sets up default users, passwords, and SSH keys
- 🎯 **Interactive & Non-Interactive Modes**: Use interactively or via command-line flags
- 🔄 **Idempotent**: Safely re-run to update existing templates without recreating them
- 🛠️ **Auto-Installation**: Automatically installs required tools (libguestfs-tools)
- 📦 **Storage Selection**: Interactive storage pool picker with usage statistics
- 🔍 **VMID Management**: Smart handling of existing VMs/templates with conflict resolution
- ⚡ **UEFI Boot**: Configures modern UEFI boot with secure boot support
- 🤖 **QEMU Guest Agent**: Pre-installs and enables qemu-guest-agent in the image

## Requirements

- Proxmox VE host (script must be run directly on the Proxmox node)
- Root or sudo access
- Internet connection (for downloading cloud images, unless using `--image`)
- `wget` (usually pre-installed)
- `openssl` (for password hashing)

The script will automatically install `libguestfs-tools` if not present.

## Installation

### For Users

1. Clone or download this repository:
   ```bash
   git clone <repository-url>
   cd proxmox_create-cloud-template
   ```

2. Make the script executable:
   ```bash
   chmod +x create-cloud-template.sh
   ```

3. Run the script (must be executed on a Proxmox host):
   ```bash
   sudo ./create-cloud-template.sh
   ```

### For Developers

#### Prerequisites

- Python 3.6+ (for pre-commit hooks)
- [pre-commit](https://pre-commit.com/) framework
- [Docker](https://www.docker.com/) (required for linting, formatting, and security scanning)
  - All development tools run in Docker containers for consistency
  - No need to install ShellCheck, shfmt, Gitleaks, or detect-secrets locally

#### Setup Development Environment

1. Install pre-commit:
   ```bash
   pip install pre-commit
   ```

2. Install pre-commit hooks:
   ```bash
   make init
   # or manually:
   pre-commit install
   pre-commit install --hook-type commit-msg
   ```

#### Development Workflow

1. **Make changes** to the script
2. **Commit with conventional commit messages**:
   ```bash
   git commit -m "feat: add support for custom cloud images"
   git commit -m "fix: resolve storage pool selection issue"
   git commit -m "docs: update README with new examples"
   ```

   Conventional commit format: `<type>(<scope>): <description>`

   Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

3. **Pre-commit hooks will automatically**:
   - Check commit message format
   - Run security scans (Gitleaks, detect-secrets)
   - Run ShellCheck for linting
   - Format shell scripts
   - Check for common issues

4. **Push to a branch** and create a Pull Request

5. **CI will automatically**:
   - Run security scans (Gitleaks, detect-secrets)
   - Run linting checks
   - Test script syntax
   - Validate script functionality

6. **Merge to main** will automatically:
   - Create a new versioned release
   - Generate release notes
   - Create a downloadable release with the script

#### Manual Checks

Run checks manually using the Makefile (all tools run in Docker containers):

```bash
# Show all available commands
make help

# Run all checks (security + lint + format)
make check

# Individual commands
make init          # Install pre-commit hooks
make security      # Run security scans (Gitleaks + detect-secrets)
make lint          # Run ShellCheck linting (via Docker)
make format        # Check shell script formatting (via Docker)
make format-fix    # Auto-fix shell script formatting (via Docker)
make clean         # Remove temporary files
```

**Additional targets** (not shown in help, but available):
```bash
make test          # Run syntax and basic tests
make pre-commit    # Run all pre-commit hooks
make setup         # Set up development environment (alias for make init)
make ci            # Run CI checks (for GitHub Actions)
make all           # Run all checks, validations, and security scans
```

**Note:** All linting, formatting, and security tools run in Docker containers. You only need Docker installed - no need to install ShellCheck, shfmt, Gitleaks, or detect-secrets locally.

#### Versioning

Versions are automatically determined from commit messages:
- `feat:` commits → minor version bump
- `fix:` commits → patch version bump
- Other commits → patch version bump

To skip a release, include `[skip release]` in your commit message.

## Usage

### Interactive Mode

Run the script without arguments for an interactive guided setup:

```bash
sudo ./create-cloud-template.sh
```

The script will prompt you for:
- VM template ID (default: 9000)
- Storage pool selection
- Ubuntu version (20.04, 22.04, or 24.04 LTS)
- Default username (default: ubuntu)
- Password (optional, recommended to use SSH keys instead)
- SSH public key (optional but recommended)

### Non-Interactive Mode

Use command-line flags to skip prompts:

```bash
sudo ./create-cloud-template.sh \
  --vmid 9000 \
  --name ubuntu-24.04-cloud \
  --storage local-lvm \
  --bridge vmbr0 \
  --user admin \
  # pragma: allowlist secret
  --password "SecurePassword123" \
  --sshkey ~/.ssh/id_ed25519.pub \
  --yes
```

### Command-Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--vmid ID` | VM ID for the template | `9000` |
| `--name NAME` | Template name | Auto-generated from image |
| `--bridge BRIDGE` | Network bridge | `vmbr0` |
| `--storage POOL` | Storage pool name | Interactive picker |
| `--image PATH` | Path to existing cloud image | Downloads from Ubuntu |
| `--user USER` | Default cloud-init username | `ubuntu` |
| `--password PASS` | Password for default user | Interactive prompt |
| `--sshkey PATH` | Path to SSH public key file | Interactive prompt |
| `--yes` | Skip confirmation prompt | `false` |
| `-h, --help` | Show help message | - |

### Environment Variables

All options can also be set via environment variables:

```bash
export TEMPLATE_VMID=9000
export TEMPLATE_NAME=ubuntu-24.04-cloud
export NETWORK_BRIDGE=vmbr0
export STORAGE_POOL=local-lvm
export CI_USER=admin
export CI_PASSWORD="SecurePassword123"  # pragma: allowlist secret
export SSH_PUBKEY_FILE=~/.ssh/id_ed25519.pub

sudo ./create-cloud-template.sh
```

## Examples

### Basic Template Creation

Create a template with default settings (interactive):

```bash
sudo ./create-cloud-template.sh
```

### Quick Template with SSH Key

Create a template using your default SSH key:

```bash
sudo ./create-cloud-template.sh \
  --storage local-lvm \
  --sshkey ~/.ssh/id_ed25519.pub \
  --yes
```

### Custom Ubuntu Version

Create a template for Ubuntu 22.04:

```bash
# Interactive selection will show Ubuntu 22.04 as option 2
sudo ./create-cloud-template.sh --storage local-lvm
```

### Using a Custom Cloud Image

Use your own pre-downloaded cloud image:

```bash
sudo ./create-cloud-template.sh \
  --image /path/to/custom-cloud-image.img \
  --storage local-lvm \
  --yes
```

### Update Existing Template

The script is idempotent. Re-run it to update credentials on an existing template:

```bash
sudo ./create-cloud-template.sh \
  --vmid 9000 \
  --sshkey ~/.ssh/id_ed25519.pub \
  --yes
```

This will update the SSH key and other cloud-init settings without recreating the template.

## Using the Template

After creating the template, you can clone it to create new VMs:

### Clone and Configure a VM

```bash
# Clone the template (ID 9000) to a new VM (ID 100)
qm clone 9000 100 --name my-new-vm --full

# Configure network (static IP)
qm set 100 --ipconfig0 ip=192.168.1.100/24,gw=192.168.1.1

# Configure resources
qm set 100 --cores 4 --memory 4096

# Start the VM
qm start 100
```

### Clone with DHCP

```bash
qm clone 9000 100 --name my-new-vm --full
qm set 100 --ipconfig0 ip=dhcp
qm start 100
```

### Via Proxmox Web UI

1. Go to **Datacenter** → **Your Node** → **VM Templates**
2. Right-click your template → **Clone**
3. Set the new VM ID and name
4. Configure network settings in **Hardware** → **Network Device**
5. Start the VM

## Template Configuration

The script creates templates with the following default settings:

- **Memory**: 2048 MB (adjustable after cloning)
- **CPU Cores**: 2 (adjustable after cloning)
- **Disk Size**: 20 GB (resizable after cloning)
- **Network**: virtio on specified bridge (default: vmbr0)
- **Boot**: UEFI with secure boot support
- **Machine Type**: q35
- **QEMU Guest Agent**: Pre-installed and enabled
- **Serial Console**: Enabled

All of these can be modified after cloning the template.

## Troubleshooting

### Script Fails: "qm not found"

The script must be run on a Proxmox VE host. It cannot be run from a remote machine.

### Template Already Exists

If a template with the same VMID already exists, the script will:
- Detect it and offer to keep it (idempotent update)
- Destroy and recreate it
- Let you pick a different VMID

### Storage Pool Not Found

Ensure the storage pool name is correct. List available pools:

```bash
pvesm status
```

### Image Download Fails

Check your internet connection. You can also download the image manually and use `--image`:

```bash
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
sudo ./create-cloud-template.sh --image ./noble-server-cloudimg-amd64.img
```

### Cannot SSH into Cloned VM

Ensure you've configured either:
- A password via `--password` or interactive prompt
- An SSH public key via `--sshkey` or interactive prompt

Check cloud-init logs in the VM:

```bash
# From within the VM
sudo cloud-init status
sudo journalctl -u cloud-init
```

### VM Won't Boot

Ensure the storage pool has enough space and is active:

```bash
pvesm status
```

Check VM configuration:

```bash
qm config <VMID>
```

## Security Considerations

- **SSH Keys vs Passwords**: SSH key authentication is more secure than passwords. Consider using `--sshkey` instead of `--password`.
- **Password Storage**: Passwords are hashed using `openssl passwd -6` (SHA-512) before being stored in Proxmox.
- **Template Access**: Templates are read-only and cannot be started directly, which is the expected behavior.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and [SETUP.md](SETUP.md) for development setup instructions.

## Author

Matthew Mellor using [bmad-method](https://github.com/bmad-code-org/BMAD-METHOD) and [Claude CLI](https://docs.claude.com/en/docs/claude-code/cli-reference)

---

**Note**: This script is designed for Proxmox VE and must be run directly on a Proxmox host with appropriate permissions.
