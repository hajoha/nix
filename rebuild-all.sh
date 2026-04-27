#!/usr/bin/env bash

# Define your build host
BUILD_HOST="home-nix-build"

# List of LXC names from your flake
# You can comment out ones you want to skip
LXCS=(
  "nix-adguard"
  "nix-grafana"
  "nix-headscale"
  "nix-hedgedoc"
  "nix-homeassistant"
  "nix-immich"
  "nix-influx"
  "nix-keycloak"
  "nix-listmonk"
  "nix-loki"
  "nix-netbox"
  "nix-nginx"
  "nix-opencloud"
  "nix-paperless"
  "nix-postgres"
  "nix-unifi-controller"
)

echo "🚀 Starting mass rebuild of ${#LXCS[@]} LXC containers..."

for LXC in "${LXCS[@]}"; do
  # We assume the target host matches the LXC name or follows a pattern
  # In your provided command, you used 'home-nix-nginx' for 'nix-nginx'
  # Mapping: nix-nginx -> home-nix-nginx
  TARGET_HOST="home-${LXC}"

  echo "----------------------------------------------------"
  echo "📦 Rebuilding: $LXC"
  echo "🎯 Target: $TARGET_HOST"
  echo "🏗️  Build Host: $BUILD_HOST"
  echo "----------------------------------------------------"

  nixos-rebuild switch \
    --flake ".#${LXC}" \
    --build-host "$BUILD_HOST" \
    --target-host "$TARGET_HOST" \
    --sudo \
    || echo "❌ Failed to rebuild $LXC"

done

echo "✅ All rebuild processes completed."
