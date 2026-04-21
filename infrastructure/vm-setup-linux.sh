#!/bin/bash
# Run on each Linux VM after SSH in.
# ssh azureuser@<VM_PUBLIC_IP> 'bash -s' < infrastructure/vm-setup-linux.sh

set -e

echo "▶ Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y

echo "▶ Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
sudo systemctl enable docker
sudo systemctl start docker

echo "▶ Installing Docker Compose plugin..."
sudo apt-get install -y docker-compose-plugin
docker compose version

echo "▶ Installing Microsoft ODBC Driver 18 (Ubuntu 22.04 compatible)..."
sudo apt-get install -y curl gnupg2
curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
  https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
  | sudo tee /etc/apt/sources.list.d/mssql-release.list
sudo apt-get update
sudo ACCEPT_EULA=Y apt-get install -y msodbcsql18 mssql-tools18

echo "▶ Installing Git and Python 3.11..."
sudo apt-get install -y git python3.11 python3-pip python3.11-venv

echo ""
echo "════════════════════════════════════════"
echo "✅ VM setup complete"
echo "════════════════════════════════════════"
docker --version
echo ""
echo "NOTE: Log out and back in for Docker group to take effect."
echo "Next: Clone your repo and run: bash deploy/deploy.sh backend"
