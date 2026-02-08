#!/bin/bash
# Generate secrets for Artifact Keeper

echo "=== Artifact Keeper Secret Generation ==="
echo ""

echo "Database Username:"
DB_USER=$(openssl rand -hex 8 | tr '[:upper:]' '[:lower:]')
echo "$DB_USER"
echo ""

echo "Database Password:"
DB_PASS=$(openssl rand -base64 32)
echo "$DB_PASS"
echo ""

echo "JWT Secret (64 bytes):"
JWT_SECRET=$(openssl rand -base64 64)
echo "$JWT_SECRET"
echo ""

echo "Admin Password:"
ADMIN_PASS=$(openssl rand -base64 32)
echo "$ADMIN_PASS"
echo ""

echo "Meilisearch Master Key:"
MEILI_KEY=$(openssl rand -base64 32)
echo "$MEILI_KEY"
echo ""

echo "=== Copy these values into your secret files ==="

