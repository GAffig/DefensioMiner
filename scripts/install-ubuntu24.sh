#!/usr/bin/env bash

# install-ubuntu24.sh — quick installer for DefensioMiner on Ubuntu 24.04 LTS
#
# This script automates the setup of DefensioMiner on systems where `sudo` is unavailable (for
# example, in restricted cloud environments).  It installs required packages, installs
# Node.js 20 and the Rust toolchain, clones the DefensioMiner repository, builds the solver
# binaries, generates and registers a default set of wallets, configures a simple donation
# range, and finally starts the miner using all available CPU cores.
#
# Usage:
#   chmod +x install-ubuntu24.sh
#   ./install-ubuntu24.sh
#
# Feel free to customise the wallet counts, ID ranges, or donation settings by editing
# the variables in the “Configuration” section below.

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Number of wallets to generate on first run
WALLET_COUNT=100
# Cardano network for wallet generation (mainnet, preprod, preview, sanchonet)
CARDANO_NETWORK="mainnet"

# Donation configuration
# The following settings donate wallets in the range [DONATE_START, DONATE_END] to
# the wallet with ID DONATE_START.  If you don’t want to set up a donation range,
# set DONATE_START and DONATE_END to zero.
DONATE_START=10
DONATE_END=20

# Repository URL
REPO_URL="https://github.com/Aervue/DefensioMiner.git"

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------

log() {
  echo "[DefensioMiner] $1"
}

# Install package if not already installed
ensure_package() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    log "Installing $pkg..."
    apt-get install -y "$pkg"
  fi
}

# -----------------------------------------------------------------------------
# Main installation steps
# -----------------------------------------------------------------------------

log "Updating package lists and upgrading existing packages..."
apt-get update -y
apt-get upgrade -y

log "Installing base dependencies..."
ensure_package git
ensure_package build-essential
ensure_package curl

# Install Node.js 20 and npm if not present
if ! command -v node >/dev/null 2>&1 || ! node -v | grep -q "^v20"; then
  log "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  ensure_package nodejs
fi

# Install Rust toolchain if cargo is missing
if ! command -v cargo >/dev/null 2>&1; then
  log "Installing Rust toolchain (via rustup)..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  # shellcheck disable=SC1090
  source "$HOME/.cargo/env"
fi

# Clone repository if it doesn’t exist
REPO_DIR="$(pwd)/DefensioMiner"
if [ ! -d "$REPO_DIR" ]; then
  log "Cloning DefensioMiner repository..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

log "Installing Node.js dependencies..."
npm install

log "Building Rust solver..."
pushd solver >/dev/null
cargo build --release
popd >/dev/null

# Generate wallets if not already generated
if [ ! -d "wallets/generated" ]; then
  log "Generating $WALLET_COUNT wallets on network $CARDANO_NETWORK..."
  npm run generate -- --count "$WALLET_COUNT" --network "$CARDANO_NETWORK"
  log "Registering wallets (1–$WALLET_COUNT)..."
  npm run register -- --from 1 --to "$WALLET_COUNT"
  # Configure donation range if enabled
  if [ "$DONATE_START" -gt 0 ] && [ "$DONATE_END" -ge "$DONATE_START" ]; then
    log "Setting up donation from wallets $DONATE_START–$DONATE_END to wallet $DONATE_START..."
    npm run donate -- --from "$DONATE_START" --to "$DONATE_END"
  fi
fi

# Start mining
THREADS=$(nproc)
log "Starting miner using $THREADS threads..."
export ASHMAIZE_THREADS="$THREADS"
npm run start -- --from 1 --to "$WALLET_COUNT" --batch 5

log "Miner started.  Press Ctrl+C to stop."
