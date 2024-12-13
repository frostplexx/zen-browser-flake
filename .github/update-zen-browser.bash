#!/usr/bin/env bash
set -euo pipefail

script_dir="$(dirname -- "$0")"
upstream="null"
max_attempts=10
attempts=1

# Function to fetch hash for a given URL
fetch_hash() {
    local url="$1"
    local is_dmg="${2:-false}"
    
    if [ "$is_dmg" = "true" ]; then
        # For DMG files, we don't use --unpack
        nix-prefetch-url --type sha256 "$url"
    else
        nix-prefetch-url --type sha256 --unpack "$url"
    fi
}

# Function to update hash in flake.nix
update_hash() {
    local variant="$1"
    local system="$2"
    local hash="$3"
    local search_pattern="\"${system}\" = {[^}]*sha256 = \"[^\"]*\"[^}]*}"
    local replacement="\"${system}\" = { url = \"\${downloadUrl.${variant}.${system}.url}\"; sha256 = \"${hash}\" }"
    sed -i "s|$search_pattern|$replacement|" ./flake.nix
}

# Try to get the new version
while [ "$upstream" == "null" ]; do
    upstream=$("$script_dir/new-version.sh")
    if [ "$upstream" != "null" ]; then
        break
    elif [ $attempts -ge $max_attempts ]; then
        echo "Unable to determine new upstream version"
        exit 1
    fi
    echo "[attempt #${attempts}] Unable to determine new upstream version, retrying in 5 seconds..."
    attempts=$((attempts + 1))
    sleep 5
done

upstream=$("$script_dir/new-version.sh" | cat -)
if [ "$upstream" == "null" ]; then
    echo "Unable to determine new upstream version"
    exit 1
fi

echo "Updating to $upstream"
base_url="https://github.com/zen-browser/desktop/releases/download/$upstream"

# Update version in flake.nix
sed -i "s/version = \".*\"/version = \"$upstream\"/" ./flake.nix

# Array of download configurations
# Format: "variant:system:filename:is_dmg"
downloads=(
    "specific:x86_64-linux:zen.linux-specific.tar.bz2:false"
    "specific:aarch64-linux:zen.linux-aarch64.tar.bz2:false"
    "specific:aarch64-darwin:zen.macos-aarch64.dmg:true"
    "specific:x86_64-darwin:zen.macos-x86_64.dmg:true"
    "generic:x86_64-linux:zen.linux-generic.tar.bz2:false"
    "generic:aarch64-linux:zen.linux-aarch64.tar.bz2:false"
    "generic:aarch64-darwin:zen.macos-aarch64.dmg:true"
    "generic:x86_64-darwin:zen.macos-x86_64.dmg:true"
)

# Fetch hashes and update flake.nix
for config in "${downloads[@]}"; do
    IFS=':' read -r variant system filename is_dmg <<< "$config"
    echo "Fetching hash for $variant $system ($filename)..."
    
    url="$base_url/$filename"
    hash=$(fetch_hash "$url" "$is_dmg")
    
    echo "Updating hash for $variant $system..."
    update_hash "$variant" "$system" "$hash"
done

# Update flake and build
echo "Updating flake..."
nix flake update

echo "Building..."
nix build
