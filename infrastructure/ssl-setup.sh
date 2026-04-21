#!/bin/bash
# SSL Certificate Setup Script
# Run on VM3 (Frontend) BEFORE building the frontend Docker image.
# Generates a self-signed certificate for demo use.
# For a real domain: see the Let's Encrypt section below.

set -e

CERT_DIR="/etc/ssl/smartticket"
DOMAIN="${1:-smartticket.local}"

sudo mkdir -p "$CERT_DIR"

# ── OPTION A: Self-Signed Certificate (for demo / no domain) ─────────────────
echo "▶ Generating self-signed certificate for: $DOMAIN"
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/smartticket.key" \
  -out "$CERT_DIR/smartticket.crt" \
  -subj "/C=US/ST=Demo/L=Demo/O=SmartTicket/CN=$DOMAIN" \
  -addext "subjectAltName=IP:$(curl -s ifconfig.me),DNS:$DOMAIN"

sudo chmod 600 "$CERT_DIR/smartticket.key"
sudo chmod 644 "$CERT_DIR/smartticket.crt"

echo ""
echo "✅ Self-signed certificate created:"
echo "   Cert: $CERT_DIR/smartticket.crt"
echo "   Key:  $CERT_DIR/smartticket.key"
echo ""
echo "NOTE: Browsers will show a security warning for self-signed certs."
echo "For the demo: click Advanced → Proceed to <IP> (unsafe) in Chrome."
echo "Or import the .crt into your OS trust store to dismiss the warning."
echo ""

# ── OPTION B: Let's Encrypt (for real domain only) ───────────────────────────
# Uncomment and replace YOUR_DOMAIN and YOUR_EMAIL if you have a real domain:
#
# sudo apt-get install -y certbot
# sudo certbot certonly --standalone \
#   --non-interactive \
#   --agree-tos \
#   --email YOUR_EMAIL@example.com \
#   --domains YOUR_DOMAIN
#
# Then copy certs:
# sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem $CERT_DIR/smartticket.crt
# sudo cp /etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem   $CERT_DIR/smartticket.key
#
# Auto-renewal (add to cron):
# 0 3 * * * certbot renew --quiet && docker restart smart-ticket-frontend

# ── Copy certs to project for Docker build ───────────────────────────────────
REPO_DIR="${REPO_DIR:-$HOME/smart-ticket-system}"
CERTS_BUILD_DIR="$REPO_DIR/certs"
mkdir -p "$CERTS_BUILD_DIR"
sudo cp "$CERT_DIR/smartticket.crt" "$CERTS_BUILD_DIR/"
sudo cp "$CERT_DIR/smartticket.key" "$CERTS_BUILD_DIR/"
sudo chown "$USER:$USER" "$CERTS_BUILD_DIR/"*
echo "✅ Certs copied to $CERTS_BUILD_DIR/ for Docker build."
echo "▶ Next: bash deploy/deploy.sh frontend"
