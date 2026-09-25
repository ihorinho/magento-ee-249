#!/usr/bin/env bash
# Generates a local CA and a TLS certificate for the dev domain.
# Both live outside git (see .gitignore), so run this once per clone:
#
#   ./docker/nginx/generate-certs.sh
#
# Trust the CA in the browser/OS by importing docker/nginx/ca/magento-local-ca.pem,
# or on Debian/Ubuntu:
#
#   sudo cp docker/nginx/ca/magento-local-ca.pem \
#           /usr/local/share/ca-certificates/magento-local-ca.crt
#   sudo update-ca-certificates
set -euo pipefail

DOMAIN="${DOMAIN:-magento.test}"
DAYS="${DAYS:-825}"          # max accepted by Chrome/Safari for leaf certs
CA_DAYS="${CA_DAYS:-3650}"

cd "$(dirname "$0")"
mkdir -p ca certs

CA_KEY="ca/magento-local-ca-key.pem"
CA_CRT="ca/magento-local-ca.pem"

# Reuse an existing CA so already-trusted browsers stay happy.
if [[ ! -f "$CA_KEY" || ! -f "$CA_CRT" ]]; then
    echo "==> Creating local CA"
    openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
        -keyout "$CA_KEY" -out "$CA_CRT" -days "$CA_DAYS" \
        -subj "/O=Magento Local Development/CN=Magento Local CA" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign"
    chmod 600 "$CA_KEY"
else
    echo "==> Reusing existing CA ($CA_CRT)"
fi

echo "==> Issuing certificate for $DOMAIN"
openssl req -newkey rsa:2048 -sha256 -nodes \
    -keyout "certs/${DOMAIN}-key.pem" -out "certs/${DOMAIN}.csr" \
    -subj "/O=Magento Local Development/CN=${DOMAIN}"

openssl x509 -req -sha256 -days "$DAYS" \
    -in "certs/${DOMAIN}.csr" \
    -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
    -out "certs/${DOMAIN}.pem" \
    -extfile <(cat <<EXT
basicConstraints = CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = DNS:${DOMAIN},DNS:*.${DOMAIN},DNS:localhost,IP:127.0.0.1,IP:::1
EXT
)

rm -f "certs/${DOMAIN}.csr"
# nginx runs as a non-root user inside the container and mounts certs read-only.
chmod 644 "certs/${DOMAIN}.pem"
chmod 644 "certs/${DOMAIN}-key.pem"

echo "==> Done:"
openssl x509 -in "certs/${DOMAIN}.pem" -noout -subject -issuer -dates -ext subjectAltName
