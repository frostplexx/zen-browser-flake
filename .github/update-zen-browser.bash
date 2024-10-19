#!/usr/bin/env bash

script_dir="$(dirname -- "$0")"

upstream="null"

max_attempts=10
attempts=1

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
    return 1
fi

echo "Updating to $upstream"

base_url="https://github.com/zen-browser/desktop/releases/download/$upstream"

# Modify with sed the nix file
sed -i "s/version = \".*\"/version = \"$upstream\"/" ./flake.nix

# Update the hash specific.sha256
specific=$(nix-prefetch-url --type sha256 --unpack "$base_url/zen.linux-specific.tar.bz2")
sed -i "s/specific.sha256 = \".*\"/specific.sha256 = \"$specific\"/" ./flake.nix

# Update the hash generic.sha256
generic=$(nix-prefetch-url --type sha256 --unpack "$base_url/zen.linux-generic.tar.bz2")
sed -i "s/generic.sha256 = \".*\"/generic.sha256 = \"$generic\"/" ./flake.nix

nix flake update
nix build