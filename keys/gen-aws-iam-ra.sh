#!/bin/bash
set -e
# Set variables
CA_KEY_NAME="ca.key"
CA_CERT_NAME="ca.crt"
CSR_NAME="cert.csr"
CSR_KEY_NAME="cert.key"
CSR_CERT_NAME="cert.crt"
CA_VALIDITY_DAYS=3650
CSR_VALIDITY_DAYS=365
KEY_SIZE=4096
CSR_SUBJECT="/OU=palworld-backups"

# # Generate CA private key
# openssl genrsa -out $CA_KEY_NAME $KEY_SIZE
openssl ecparam -genkey -name secp384r1 -out $CA_KEY_NAME
echo "Generated CA private key: $CA_KEY_NAME"

# # Create CA certificate
openssl req -new -x509 -nodes -sha256 -key $CA_KEY_NAME \
    -out $CA_CERT_NAME -days $CA_VALIDITY_DAYS \
    -subj "/CN=CA Certificate Authority/OU=IAM Roles Anywhere/O=GoodMannersHosting" \
    -addext="keyUsage=keyCertSign,cRLSign,digitalSignature" \
    -addext="basicConstraints=CA:TRUE" \
    -addext="subjectKeyIdentifier=hash" \
    -addext="authorityKeyIdentifier=keyid:always"
echo "Generated CA certificate: $CA_CERT_NAME"

# Generate CSR for trust anchor
openssl req -new -sha512 -nodes -keyout $CSR_KEY_NAME \
    -out $CSR_NAME -subj "$CSR_SUBJECT" \
    -addext="keyUsage=critical,digitalSignature" \
    -addext="basicConstraints=critical,CA:FALSE"
echo "Generated CSR for trust anchor: $CSR_NAME"

# Sign CSR with CA
openssl x509 -req -in $CSR_NAME -CA $CA_CERT_NAME \
    -CAkey $CA_KEY_NAME -out $CSR_CERT_NAME \
    -days $CSR_VALIDITY_DAYS \
    -extfile <(echo -e "keyUsage = critical,digitalSignature\nbasicConstraints = critical,CA:FALSE")
echo "Signed CSR with CA to generate trust anchor certificate: $CSR_CERT_NAME"

# Output instructions
echo "Trust anchor configuration complete:"
echo "CA private key: $CA_KEY_NAME"
echo "CA certificate: $CA_CERT_NAME"
echo "CSR: $CSR_NAME"
echo "Trust anchor certificate: $CSR_CERT_NAME"
