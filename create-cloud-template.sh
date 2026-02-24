#!/bin/bash

set -euo pipefail

# Defaults (overridable via environment)
TEMPLATE_VMID="${TEMPLATE_VMID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-ubuntu-cloud}"
NETWORK_BRIDGE="${NETWORK_BRIDGE:-vmbr0}"
CI_USER="${CI_USER:-ubuntu}"
CI_PASSWORD=""
SSH_PUBKEY=""
SSH_PUBKEY_FILE=""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"; }
error() {
  echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
  exit 1
}

usage() {
  cat << EOF
Usage: $(basename "$0") [OPTIONS]

Create a cloud-init VM template on a Proxmox host.

Options:
  --vmid ID          VM ID for the template (default: ${TEMPLATE_VMID})
  --name NAME        Template name (default: auto-generated from image)
  --bridge BRIDGE    Network bridge (default: ${NETWORK_BRIDGE})
  --storage POOL     Storage pool (skips interactive picker)
  --image PATH       Path to an existing cloud image (skips download)
  --user USER        Default cloud-init username (default: ${CI_USER})
  --password PASS    Password for the default user (skips interactive prompt)
  --sshkey PATH      Path to SSH public key file (skips interactive prompt)
  --yes              Skip confirmation prompt
  -h, --help         Show this help message

Environment variables:
  TEMPLATE_VMID      Same as --vmid
  TEMPLATE_NAME      Same as --name
  NETWORK_BRIDGE     Same as --bridge
  STORAGE_POOL       Same as --storage
  CI_USER            Same as --user
  CI_PASSWORD        Same as --password

Examples:
  $(basename "$0")                          # Interactive mode
  $(basename "$0") --storage local-lvm      # Skip storage picker
  $(basename "$0") --vmid 9010 --name my-template --storage ceph-pool
  $(basename "$0") --user admin --sshkey ~/.ssh/id_ed25519.pub
EOF
  exit 0
}

# ── Parse arguments ──────────────────────────────────────────────────
SKIP_CONFIRM=false
CUSTOM_IMAGE=""
VMID_FROM_FLAG=false
TEMPLATE_ALREADY_EXISTS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --vmid)
      TEMPLATE_VMID="$2"
      VMID_FROM_FLAG=true
      shift 2
      ;;
    --name)
      TEMPLATE_NAME="$2"
      shift 2
      ;;
    --bridge)
      NETWORK_BRIDGE="$2"
      shift 2
      ;;
    --storage)
      STORAGE_POOL="$2"
      shift 2
      ;;
    --image)
      CUSTOM_IMAGE="$2"
      shift 2
      ;;
    --user)
      CI_USER="$2"
      shift 2
      ;;
    --password)
      CI_PASSWORD="$2"
      shift 2
      ;;
    --sshkey)
      SSH_PUBKEY_FILE="$2"
      shift 2
      ;;
    --yes)
      SKIP_CONFIRM=true
      shift
      ;;
    -h | --help) usage ;;
    *) error "Unknown option: $1" ;;
  esac
done

# ── Proxmox check ───────────────────────────────────────────────────
check_proxmox() {
  if ! command -v qm &> /dev/null; then
    error "This script must be run on a Proxmox host (qm not found)"
  fi
  if ! command -v pvesm &> /dev/null; then
    error "This script must be run on a Proxmox host (pvesm not found)"
  fi
  log "Detected Proxmox host: $(hostname)"
}

# ── VMID picker ──────────────────────────────────────────────────────
# Returns: sets TEMPLATE_VMID and TEMPLATE_ALREADY_EXISTS
check_vmid_exists() {
  local vmid=$1
  if qm status "$vmid" &> /dev/null; then
    # Check if it's already a template
    if qm config "$vmid" 2> /dev/null | grep -q "^template: 1"; then
      return 0 # exists as template
    fi
    return 1 # exists but not a template
  fi
  return 2 # does not exist
}

pick_vmid() {
  if [[ "$VMID_FROM_FLAG" == true ]]; then
    # Provided via --vmid, just validate
    check_vmid_exists "$TEMPLATE_VMID" && rc=$? || rc=$?
    case $rc in
      0)
        local existing_name
        existing_name=$(qm config "$TEMPLATE_VMID" 2> /dev/null | grep "^name:" | awk '{print $2}')
        warn "VM ID ${TEMPLATE_VMID} already exists as template '${existing_name}'"
        log "Re-running will update credentials and skip creation (idempotent)"
        TEMPLATE_ALREADY_EXISTS=true
        ;;
      1)
        error "VM ID ${TEMPLATE_VMID} exists but is NOT a template. Remove it first or pick a different ID."
        ;;
    esac
    log "Using VMID: $TEMPLATE_VMID"
    return
  fi

  echo ""
  echo -e "${BOLD}VM template ID:${NC}"
  echo ""

  while true; do
    read -rp "  Enter VMID (default: ${TEMPLATE_VMID}): " input_vmid
    input_vmid="${input_vmid:-$TEMPLATE_VMID}"

    # Validate numeric
    if [[ ! "$input_vmid" =~ ^[0-9]+$ ]]; then
      echo -e "  ${RED}VMID must be a number.${NC}"
      continue
    fi

    # Check range (Proxmox valid range: 100-999999999)
    if ((input_vmid < 100)); then
      echo -e "  ${RED}VMID must be >= 100 (Proxmox reserves 0-99).${NC}"
      continue
    fi

    check_vmid_exists "$input_vmid" && rc=$? || rc=$?
    case $rc in
      0)
        local existing_name
        existing_name=$(qm config "$input_vmid" 2> /dev/null | grep "^name:" | awk '{print $2}')
        warn "VM ID ${input_vmid} already exists as template '${existing_name}'"
        echo ""
        echo "  1) Keep it — skip creation (idempotent re-run)"
        echo "  2) Destroy and recreate"
        echo "  3) Pick a different VMID"
        echo ""
        local action
        read -rp "  Select [1-3] (default: 1): " action
        action="${action:-1}"
        case $action in
          1)
            TEMPLATE_VMID="$input_vmid"
            TEMPLATE_ALREADY_EXISTS=true
            log "Will keep existing template ${TEMPLATE_VMID}"
            return
            ;;
          2)
            log "Will destroy VM ${input_vmid} and recreate"
            qm destroy "$input_vmid" --purge
            log "VM ${input_vmid} destroyed"
            TEMPLATE_VMID="$input_vmid"
            return
            ;;
          3)
            continue
            ;;
          *)
            echo -e "  ${RED}Invalid selection.${NC}"
            continue
            ;;
        esac
        ;;
      1)
        warn "VM ID ${input_vmid} exists but is NOT a template (it's a regular VM)"
        echo ""
        echo "  1) Pick a different VMID"
        echo "  2) Destroy it and use this VMID"
        echo ""
        local action
        read -rp "  Select [1-2] (default: 1): " action
        action="${action:-1}"
        case $action in
          1) continue ;;
          2)
            log "Will destroy VM ${input_vmid} and recreate"
            qm stop "$input_vmid" --skiplock 2> /dev/null || true
            qm destroy "$input_vmid" --purge
            log "VM ${input_vmid} destroyed"
            TEMPLATE_VMID="$input_vmid"
            return
            ;;
          *)
            echo -e "  ${RED}Invalid selection.${NC}"
            continue
            ;;
        esac
        ;;
      2)
        # Does not exist — good to go
        TEMPLATE_VMID="$input_vmid"
        return
        ;;
    esac
  done

  log "Using VMID: $TEMPLATE_VMID"
}

# ── Interactive storage picker ───────────────────────────────────────
pick_storage() {
  # If already set via flag or env, validate and return
  if [[ -n "${STORAGE_POOL:-}" ]]; then
    if ! pvesm status | awk 'NR>1 {print $1}' | grep -qx "$STORAGE_POOL"; then
      error "Storage '$STORAGE_POOL' not found on this host"
    fi
    log "Using storage: $STORAGE_POOL"
    return
  fi

  echo ""
  echo -e "${BOLD}Available storage pools:${NC}"
  echo ""

  local -a storages=()
  local -a types=()
  local -a statuses=()
  local -a totals=()
  local -a used_pcts=()

  while IFS= read -r line; do
    local name type status total_raw used_raw pct
    name=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $2}')
    status=$(echo "$line" | awk '{print $3}')
    total_raw=$(echo "$line" | awk '{print $4}')
    used_raw=$(echo "$line" | awk '{print $5}')

    # Convert KiB to human-readable
    if [[ "$total_raw" =~ ^[0-9]+$ ]] && ((total_raw > 0)); then
      total=$(awk "BEGIN {printf \"%.1f GiB\", $total_raw / 1048576}")
      pct=$(awk "BEGIN {printf \"%.0f%%\", ($used_raw / $total_raw) * 100}")
    else
      total="N/A"
      pct="N/A"
    fi

    storages+=("$name")
    types+=("$type")
    statuses+=("$status")
    totals+=("$total")
    used_pcts+=("$pct")
  done < <(pvesm status 2> /dev/null | awk 'NR>1')

  if [[ ${#storages[@]} -eq 0 ]]; then
    error "No storage pools found on this host"
  fi

  printf "  ${BOLD}%-4s %-20s %-12s %-10s %-12s %s${NC}\n" "#" "NAME" "TYPE" "STATUS" "SIZE" "USED"
  echo "  ─────────────────────────────────────────────────────────────────"
  for i in "${!storages[@]}"; do
    local color="$NC"
    if [[ "${statuses[$i]}" == "active" ]]; then
      color="$GREEN"
    else
      color="$RED"
    fi
    printf "  ${CYAN}%-4s${NC} %-20s %-12s ${color}%-10s${NC} %-12s %s\n" \
      "$((i + 1))" "${storages[$i]}" "${types[$i]}" "${statuses[$i]}" "${totals[$i]}" "${used_pcts[$i]}"
  done

  echo ""
  while true; do
    read -rp "Select storage pool [1-${#storages[@]}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#storages[@]})); then
      STORAGE_POOL="${storages[$((choice - 1))]}"
      if [[ "${statuses[$((choice - 1))]}" != "active" ]]; then
        warn "Storage '${STORAGE_POOL}' is not active — proceed with caution"
      fi
      break
    fi
    echo -e "${RED}Invalid selection. Enter a number between 1 and ${#storages[@]}.${NC}"
  done

  log "Selected storage: $STORAGE_POOL"
}

# ── Ubuntu version picker ────────────────────────────────────────────
pick_ubuntu_version() {
  if [[ -n "$CUSTOM_IMAGE" ]]; then
    if [[ ! -f "$CUSTOM_IMAGE" ]]; then
      error "Custom image not found: $CUSTOM_IMAGE"
    fi
    IMAGE_PATH="$CUSTOM_IMAGE"
    log "Using custom image: $IMAGE_PATH"
    return
  fi

  echo ""
  echo -e "${BOLD}Available Ubuntu cloud images:${NC}"
  echo ""
  echo "  1) Ubuntu 24.04 LTS (Noble Numbat)"
  echo "  2) Ubuntu 22.04 LTS (Jammy Jellyfish)"
  echo "  3) Ubuntu 20.04 LTS (Focal Fossa)"
  echo ""

  local choice
  while true; do
    read -rp "Select Ubuntu version [1-3] (default: 1): " choice
    choice="${choice:-1}"
    case $choice in
      1)
        UBUNTU_CODENAME="noble"
        UBUNTU_LABEL="24.04"
        break
        ;;
      2)
        UBUNTU_CODENAME="jammy"
        UBUNTU_LABEL="22.04"
        break
        ;;
      3)
        UBUNTU_CODENAME="focal"
        UBUNTU_LABEL="20.04"
        break
        ;;
      *) echo -e "${RED}Invalid selection.${NC}" ;;
    esac
  done

  IMAGE_FILE="ubuntu-${UBUNTU_LABEL}-cloud.img"
  IMAGE_PATH="/var/lib/vz/template/iso/${IMAGE_FILE}"

  # Auto-set template name if still at default
  if [[ "$TEMPLATE_NAME" == "ubuntu-cloud" ]]; then
    TEMPLATE_NAME="ubuntu-${UBUNTU_LABEL}-cloud"
  fi

  log "Selected Ubuntu ${UBUNTU_LABEL} (${UBUNTU_CODENAME})"
}

# ── Credential configuration ─────────────────────────────────────────
configure_credentials() {
  echo ""
  echo -e "${BOLD}Cloud-init default user configuration:${NC}"
  echo ""

  # ── Username ──
  echo -e "  Default username: ${CYAN}${CI_USER}${NC}"
  read -rp "  Change username? (enter new name, or press Enter to keep '${CI_USER}'): " new_user
  if [[ -n "$new_user" ]]; then
    CI_USER="$new_user"
  fi
  log "Default user: ${CI_USER}"

  # ── Password ──
  if [[ -z "$CI_PASSWORD" ]]; then
    echo ""
    echo -e "  Set a password for user ${CYAN}${CI_USER}${NC}."
    echo -e "  ${YELLOW}(Leave blank to skip — SSH key auth is recommended)${NC}"
    while true; do
      read -rsp "  Password: " pw1
      echo ""
      if [[ -z "$pw1" ]]; then
        warn "No password set — VMs will require SSH key authentication"
        break
      fi
      read -rsp "  Confirm password: " pw2
      echo ""
      if [[ "$pw1" == "$pw2" ]]; then
        CI_PASSWORD="$pw1"
        log "Password set for user '${CI_USER}'"
        break
      else
        echo -e "  ${RED}Passwords do not match. Try again.${NC}"
      fi
    done
  else
    log "Password provided via --password flag"
  fi

  # ── SSH public key ──
  echo ""
  if [[ -n "$SSH_PUBKEY_FILE" ]]; then
    # Provided via --sshkey flag
    if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
      error "SSH key file not found: $SSH_PUBKEY_FILE"
    fi
    SSH_PUBKEY=$(cat "$SSH_PUBKEY_FILE")
    log "SSH key loaded from: $SSH_PUBKEY_FILE"
  else
    echo -e "${BOLD}  SSH public key for user ${CYAN}${CI_USER}${NC}${BOLD}:${NC}"
    echo "  1) Paste a public key"
    echo "  2) Read from a file path"
    echo "  3) Skip (no SSH key)"
    echo ""
    local ssh_choice
    while true; do
      read -rp "  Select [1-3] (default: 3): " ssh_choice
      ssh_choice="${ssh_choice:-3}"
      case $ssh_choice in
        1)
          echo ""
          read -rp "  Paste your public key: " SSH_PUBKEY
          if [[ -z "$SSH_PUBKEY" ]]; then
            warn "Empty key — skipping SSH key configuration"
            SSH_PUBKEY=""
          elif [[ ! "$SSH_PUBKEY" =~ ^ssh- ]]; then
            echo -e "  ${RED}That doesn't look like a valid SSH public key (should start with ssh-).${NC}"
            SSH_PUBKEY=""
            continue
          else
            log "SSH public key accepted"
          fi
          break
          ;;
        2)
          echo ""
          read -rp "  Path to public key file: " SSH_PUBKEY_FILE
          # Expand ~ manually
          SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE/#\~/$HOME}"
          if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
            echo -e "  ${RED}File not found: ${SSH_PUBKEY_FILE}${NC}"
            continue
          fi
          SSH_PUBKEY=$(cat "$SSH_PUBKEY_FILE")
          log "SSH key loaded from: $SSH_PUBKEY_FILE"
          break
          ;;
        3)
          warn "No SSH key configured"
          break
          ;;
        *)
          echo -e "  ${RED}Invalid selection.${NC}"
          ;;
      esac
    done
  fi

  # Warn if neither password nor key is set
  if [[ -z "$CI_PASSWORD" && -z "$SSH_PUBKEY" ]]; then
    echo ""
    warn "Neither password nor SSH key configured — VMs cloned from this template will be inaccessible!"
    read -rp "Continue anyway? (y/N): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi
}

# ── Download cloud image ────────────────────────────────────────────
download_cloud_image() {
  [[ -n "$CUSTOM_IMAGE" ]] && return

  mkdir -p /var/lib/vz/template/iso/

  if [[ -f "$IMAGE_PATH" ]]; then
    warn "Image already exists: $IMAGE_PATH"
    read -rp "Re-download? (y/N): " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      return
    fi
    rm -f "$IMAGE_PATH"
  fi

  local url="https://cloud-images.ubuntu.com/${UBUNTU_CODENAME}/current/${UBUNTU_CODENAME}-server-cloudimg-amd64.img"
  log "Downloading from: $url"
  wget -q --show-progress "$url" -O "$IMAGE_PATH"
  log "Download complete: $IMAGE_PATH"
}

# ── Create VM template ──────────────────────────────────────────────
create_vm_template() {
  # ── Idempotent: template already exists ──
  if [[ "$TEMPLATE_ALREADY_EXISTS" == true ]]; then
    log "Template ${TEMPLATE_VMID} already exists — updating cloud-init credentials only"

    # Update cloud-init user
    qm set "$TEMPLATE_VMID" --ciuser "$CI_USER"
    log "Cloud-init user set to '${CI_USER}'"

    # Keep cloud-init networking defaulted to DHCP
    qm set "$TEMPLATE_VMID" --ipconfig0 ip=dhcp,ip6=dhcp

    # Update password
    if [[ -n "$CI_PASSWORD" ]]; then
      qm set "$TEMPLATE_VMID" --cipassword "$(openssl passwd -6 "$CI_PASSWORD")"
      log "Password updated for user '${CI_USER}'"
    fi

    # Update SSH key
    if [[ -n "$SSH_PUBKEY" ]]; then
      local tmpkey
      tmpkey=$(mktemp)
      echo "$SSH_PUBKEY" > "$tmpkey"
      qm set "$TEMPLATE_VMID" --sshkeys "$tmpkey"
      rm -f "$tmpkey"
      log "SSH public key updated for user '${CI_USER}'"
    fi

    log "Existing template ${TEMPLATE_VMID} updated successfully"
    return
  fi

  # ── Fresh creation ──
  log "Creating VM template '${TEMPLATE_NAME}' (ID: ${TEMPLATE_VMID})..."

  # Install virt-customize if needed
  if ! command -v virt-customize &> /dev/null; then
    log "Installing libguestfs-tools for image customization..."
    apt-get update -qq
    apt-get install -y -qq libguestfs-tools
  fi

  # Pre-install qemu-guest-agent + sanitize guest identity/state
  log "Customizing cloud image (installing qemu-guest-agent + template cleanup)..."
  virt-customize -a "$IMAGE_PATH" \
    --install qemu-guest-agent \
    --run-command "systemctl enable qemu-guest-agent" \
    --run-command "cloud-init clean --logs --seed || true" \
    --run-command "truncate -s 0 /etc/machine-id" \
    --run-command "rm -f /var/lib/dbus/machine-id" \
    --run-command "rm -f /etc/netplan/50-cloud-init.yaml" \
    --run-command "rm -f /var/lib/dhcp/*.leases" \
    --run-command "rm -rf /var/lib/cloud/*"

  # Create VM
  qm create "$TEMPLATE_VMID" \
    --name "$TEMPLATE_NAME" \
    --memory 2048 \
    --cores 2 \
    --net0 "virtio,bridge=${NETWORK_BRIDGE}" \
    --scsihw virtio-scsi-pci

  # Import disk
  qm importdisk "$TEMPLATE_VMID" "$IMAGE_PATH" "$STORAGE_POOL"

  # Attach disk
  qm set "$TEMPLATE_VMID" --scsi0 "${STORAGE_POOL}:vm-${TEMPLATE_VMID}-disk-0"

  # Cloud-init drive
  qm set "$TEMPLATE_VMID" --ide2 "${STORAGE_POOL}:cloudinit"

  # Boot from scsi0
  qm set "$TEMPLATE_VMID" --boot c --bootdisk scsi0

  # Serial console
  qm set "$TEMPLATE_VMID" --serial0 socket --vga serial0

  # QEMU guest agent
  qm set "$TEMPLATE_VMID" --agent enabled=1

  # q35 machine type
  qm set "$TEMPLATE_VMID" --machine q35

  # UEFI boot
  qm set "$TEMPLATE_VMID" --bios ovmf \
    --efidisk0 "${STORAGE_POOL}:1,efitype=4m,pre-enrolled-keys=1"

  # Default cloud-init user
  qm set "$TEMPLATE_VMID" --ciuser "$CI_USER"

  # Default networking: DHCP via cloud-init
  qm set "$TEMPLATE_VMID" --ipconfig0 ip=dhcp,ip6=dhcp

  # Cloud-init password
  if [[ -n "$CI_PASSWORD" ]]; then
    qm set "$TEMPLATE_VMID" --cipassword "$(openssl passwd -6 "$CI_PASSWORD")"
    log "Password set for user '${CI_USER}'"
  fi

  # SSH public key
  if [[ -n "$SSH_PUBKEY" ]]; then
    local tmpkey
    tmpkey=$(mktemp)
    echo "$SSH_PUBKEY" > "$tmpkey"
    qm set "$TEMPLATE_VMID" --sshkeys "$tmpkey"
    rm -f "$tmpkey"
    log "SSH public key added for user '${CI_USER}'"
  fi

  # Resize disk to 20 GB
  qm resize "$TEMPLATE_VMID" scsi0 20G

  # Convert to template
  qm template "$TEMPLATE_VMID"

  log "Template '${TEMPLATE_NAME}' (ID: ${TEMPLATE_VMID}) created successfully on storage '${STORAGE_POOL}'"
}

# ── Summary ──────────────────────────────────────────────────────────
show_summary() {
  local action="Created"
  [[ "$TEMPLATE_ALREADY_EXISTS" == true ]] && action="Updated"

  local tmpl_name
  tmpl_name=$(qm config "$TEMPLATE_VMID" 2> /dev/null | grep "^name:" | awk '{print $2}')
  tmpl_name="${tmpl_name:-${TEMPLATE_NAME}}"

  cat << EOF

${GREEN}════════════════════════════════════════${NC}
${BOLD}  Cloud-Init VM Template ${action}${NC}
${GREEN}════════════════════════════════════════${NC}

  Template ID:    ${TEMPLATE_VMID}
  Template Name:  ${tmpl_name}
  Default User:   ${CI_USER}
  Password Auth:  $(if [[ -n "$CI_PASSWORD" ]]; then echo "Yes"; else echo "No"; fi)
  SSH Key Auth:   $(if [[ -n "$SSH_PUBKEY" ]]; then echo "Yes"; else echo "No"; fi)
  Proxmox Host:   $(hostname)

${YELLOW}Clone example:${NC}
  qm clone ${TEMPLATE_VMID} <NEW_VMID> --name <VM_NAME> --full
  qm set <NEW_VMID> --ipconfig0 ip=dhcp,ip6=dhcp --cores 4 --memory 4096
  qm start <NEW_VMID>

EOF
}

# ── Main ─────────────────────────────────────────────────────────────
main() {
  check_proxmox
  pick_vmid
  pick_storage

  # Skip image selection/download if template already exists (idempotent re-run)
  if [[ "$TEMPLATE_ALREADY_EXISTS" != true ]]; then
    pick_ubuntu_version
  fi

  configure_credentials

  if [[ "$SKIP_CONFIRM" != true ]]; then
    echo ""
    if [[ "$TEMPLATE_ALREADY_EXISTS" == true ]]; then
      echo -e "${BOLD}Ready to update existing template:${NC}"
    else
      echo -e "${BOLD}Ready to create template:${NC}"
    fi
    echo "  VMID:    ${TEMPLATE_VMID}"
    if [[ "$TEMPLATE_ALREADY_EXISTS" != true ]]; then
      echo "  Name:    ${TEMPLATE_NAME}"
      echo "  Storage: ${STORAGE_POOL}"
      echo "  Bridge:  ${NETWORK_BRIDGE}"
      echo "  Image:   ${IMAGE_PATH}"
    fi
    echo "  User:    ${CI_USER}"
    echo "  Password:$(if [[ -n "$CI_PASSWORD" ]]; then echo " ****"; else echo " (none)"; fi)"
    echo "  SSH Key: $(if [[ -n "$SSH_PUBKEY" ]]; then echo " ${SSH_PUBKEY:0:40}..."; else echo " (none)"; fi)"
    echo ""
    read -rp "Continue? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  if [[ "$TEMPLATE_ALREADY_EXISTS" != true ]]; then
    download_cloud_image
  fi
  create_vm_template
  show_summary
}

main
