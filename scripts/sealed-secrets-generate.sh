#!/bin/bash

check_existing_files() {
  if [[ -f "keys/sealed-secret.crt" || -f "keys/sealed-secret.key" ]]; then
    echo "Error: keys/sealed-secret.crt or keys/sealed-secret.key already exist."
    echo "We don't want to overwrite existing keys. That is a bad idea."
    exit 1
  fi
}

# This script generates a self-signed certificate and private key for use with Sealed Secrets.
# It checks if the keys already exist and if so, it exits with an error message.
# Usage: ./scripts/sealed-secrets-generate.sh

# Ensure the keys directory exists
mkdir -p keys

# Check if the keys already exist
check_existing_files

# Generate a self-signed certificate and private key
openssl req -x509 -days 400 \
  -nodes -newkey rsa:4096 \
  -keyout keys/sealed-secret.key \
  -out keys/sealed-secret.crt \
  -subj "/CN=sealed-secret/O=sealed-secret" \
  >/dev/null 2>&1
