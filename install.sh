#!/usr/bin/env bash
#
# Remote installer for this flake, meant to be run from a booted NixOS live ISO.
# It lets you pick which host to install (dream / framework) and which whole disk
# to install onto, confirms the destructive wipe, then hands off to disko-install
# (partition + format + mount + nixos-install, all in one).
#
# Run it straight from GitHub — nothing to clone:
#
#   curl -sSL https://raw.githubusercontent.com/lcleveland/itera.personal/main/install.sh | sudo bash
#
# Skip either prompt by passing host and/or device as arguments:
#
#   curl -sSL .../install.sh | sudo bash -s -- dream
#   curl -sSL .../install.sh | sudo bash -s -- dream /dev/nvme0n1
#
# Install from a different flake (e.g. a local clone or a branch) with FLAKE:
#
#   curl -sSL .../install.sh | sudo FLAKE=. bash -s -- dream /dev/nvme0n1

set -euo pipefail

# The live ISO ships with flakes disabled, and disko-install shells out to more
# `nix` commands — export the features so every child nix process inherits them
# (extra-* appends, so any existing NIX_CONFIG is preserved). accept-flake-config
# takes the flake's substituters/caches without an interactive prompt.
export NIX_CONFIG="extra-experimental-features = nix-command flakes
accept-flake-config = true
${NIX_CONFIG:-}"

FLAKE="${FLAKE:-github:lcleveland/itera.personal}"
DISK_NAME="main"                 # the disk key in itera.disko (see hosts/*.nix)
HOSTS=(dream framework)          # available nixosConfigurations

# Read interactive answers from the controlling terminal, not stdin: when this is
# reached through `curl … | sudo bash`, stdin is the piped script, so a plain
# `read` would hit EOF instead of the keyboard.
if [ -r /dev/tty ]; then
  TTY=/dev/tty
else
  TTY=/dev/stdin
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root — this partitions and installs to a disk." >&2
  echo "       pipe it into 'sudo bash', e.g.:" >&2
  echo "         curl -sSL .../install.sh | sudo bash" >&2
  exit 1
fi

# ---- host ------------------------------------------------------------------
# First non-flag argument is the host; validate it against HOSTS.
host=""
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  host="$1"
  shift
fi

host_is_known() {
  local h
  for h in "${HOSTS[@]}"; do
    [ "$h" = "$1" ] && return 0
  done
  return 1
}

if [ -n "$host" ] && ! host_is_known "$host"; then
  echo "error: unknown host '$host' (known: ${HOSTS[*]})." >&2
  exit 1
fi

if [ -z "$host" ]; then
  echo "Select the host to install:"
  echo
  i=1
  for h in "${HOSTS[@]}"; do
    printf "  %2d) %s\n" "$i" "$h"
    i=$((i + 1))
  done
  echo
  printf "Enter a number [1-%d]: " "${#HOSTS[@]}"
  read -r choice <"$TTY"
  case "$choice" in
    '' | *[!0-9]*)
      echo "error: '$choice' is not a number." >&2
      exit 1
      ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#HOSTS[@]}" ]; then
    echo "error: choice out of range." >&2
    exit 1
  fi
  host="${HOSTS[$((choice - 1))]}"
fi

# ---- disk ------------------------------------------------------------------
# Second non-flag argument is the device; anything after it goes to disko-install.
device=""
if [ "$#" -gt 0 ] && [ "${1#-}" = "$1" ]; then
  device="$1"
  shift
fi

if [ -z "$device" ]; then
  # Collect whole disks only (TYPE=disk excludes partitions, loop and CD-ROM
  # devices). `model` soaks up the rest of the line, so spaces in it are fine.
  names=()
  labels=()
  while read -r name type size model; do
    [ "$type" = "disk" ] || continue
    # zram/ram are RAM-backed block devices that report TYPE=disk but are never
    # valid install targets — drop them so they can't be picked by accident.
    case "$name" in
      /dev/zram* | /dev/ram*) continue ;;
    esac
    names+=("$name")
    labels+=("$name  ($size)  ${model:-unknown model}")
  done < <(lsblk -dpno NAME,TYPE,SIZE,MODEL)

  if [ "${#names[@]}" -eq 0 ]; then
    echo "error: no disks found (lsblk reported no TYPE=disk devices)." >&2
    exit 1
  fi

  echo
  echo "Select the disk to install '$host' onto:"
  echo
  i=1
  for label in "${labels[@]}"; do
    printf "  %2d) %s\n" "$i" "$label"
    i=$((i + 1))
  done
  echo
  printf "Enter a number [1-%d]: " "${#names[@]}"
  read -r choice <"$TTY"
  case "$choice" in
    '' | *[!0-9]*)
      echo "error: '$choice' is not a number." >&2
      exit 1
      ;;
  esac
  if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
    echo "error: choice out of range." >&2
    exit 1
  fi
  device="${names[$((choice - 1))]}"
fi

# ---- confirm + install -----------------------------------------------------
echo
echo "About to WIPE and install '$host' onto: $device"
lsblk -pno NAME,SIZE,TYPE,MOUNTPOINTS "$device" 2>/dev/null || true
echo
echo "This ERASES ALL DATA on $device. There is no undo."
printf "Type the device path exactly to confirm (%s): " "$device"
read -r confirm <"$TTY"
if [ "$confirm" != "$device" ]; then
  echo "aborted: confirmation did not match." >&2
  exit 1
fi

echo
echo "Installing ${FLAKE}#${host} onto ${device} ..."
# disko-install isn't on the live ISO's PATH, so fetch and run it via `nix run`.
# `--disk main <device>` overrides the placeholder device in the config.
exec nix run 'github:nix-community/disko/latest#disko-install' -- \
  --flake "${FLAKE}#${host}" --disk "${DISK_NAME}" "$device" "$@"
