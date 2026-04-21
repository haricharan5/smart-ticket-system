#!/bin/bash
# Full Deployment Script
# Usage: bash deploy.sh [backend|frontend|seed|all]
# Required env vars: REPO_URL, BACKEND_VM_IP, FRONTEND_VM_IP
# Or set them below before running.

set -e

REPO_URL="${REPO_URL:-https://github.com/YOUR_USERNAME/smart-ticket-system.git}"
BACKEND_VM_IP="${BACKEND_VM_IP:-YOUR_VM1_IP}"
FRONTEND_VM_IP="${FRONTEND_VM_IP:-YOUR_VM3_IP}"
REPO_DIR="$HOME/smart-ticket-system"

check_placeholders() {
  if [[ "$REPO_URL" == *"YOUR_USERNAME"* ]]; then
    echo "ERROR: Set REPO_URL before running. Example:"
    echo "  export REPO_URL=https://github.com/yourname/smart-ticket-system.git"
    exit 1
  fi
  if [[ "$BACKEND_VM_IP" == "YOUR_VM1_IP" || "$FRONTEND_VM_IP" == "YOUR_VM3_IP" ]]; then
    echo "ERROR: Set BACKEND_VM_IP and FRONTEND_VM_IP before running. Example:"
    echo "  export BACKEND_VM_IP=10.0.0.4"
    echo "  export FRONTEND_VM_IP=10.0.0.6"
    exit 1
  fi
}

clone_or_pull() {
  if [ -d "$REPO_DIR/.git" ]; then
    echo "▶ Pulling latest code..."
    git -C "$REPO_DIR" pull
  else
    echo "▶ Cloning repo..."
    git clone "$REPO_URL" "$REPO_DIR"
  fi
}

deploy_backend() {
  check_placeholders
  clone_or_pull

  if [ ! -f "$REPO_DIR/backend/.env" ]; then
    echo "ERROR: $REPO_DIR/backend/.env not found."
    echo "Copy backend/.env.example and fill in your Azure keys."
    exit 1
  fi

  echo "▶ Building backend Docker image..."
  docker build -t smart-ticket-backend "$REPO_DIR/backend"

  docker stop smart-ticket-backend 2>/dev/null || true
  docker rm smart-ticket-backend 2>/dev/null || true

  echo "▶ Starting backend container..."
  docker run -d \
    --name smart-ticket-backend \
    --restart unless-stopped \
    -p 8000:8000 \
    --env-file "$REPO_DIR/backend/.env" \
    smart-ticket-backend

  echo "▶ Waiting for backend to be healthy..."
  for i in $(seq 1 15); do
    if curl -sf "http://localhost:8000/health" > /dev/null 2>&1; then
      echo "✅ Backend healthy at http://${BACKEND_VM_IP}:8000"
      return 0
    fi
    sleep 2
  done
  echo "⚠ Backend did not respond in time — check: docker logs smart-ticket-backend"
}

deploy_frontend() {
  check_placeholders
  clone_or_pull

  # Ensure SSL certs exist before building
  if [ ! -f "$REPO_DIR/certs/smartticket.crt" ]; then
    echo "⚠ SSL certs not found at $REPO_DIR/certs/"
    echo "  Run: bash infrastructure/ssl-setup.sh"
    echo "  Then retry: bash deploy.sh frontend"
    exit 1
  fi

  echo "▶ Building frontend Docker image (HTTPS enabled)..."
  docker build \
    --build-arg "VITE_API_URL=https://${BACKEND_VM_IP}:8443" \
    --build-arg "VITE_POWERBI_URL=${VITE_POWERBI_URL:-}" \
    --build-arg "SSL_CERT_PATH=./certs" \
    -t smart-ticket-frontend \
    "$REPO_DIR/frontend"

  docker stop smart-ticket-frontend 2>/dev/null || true
  docker rm smart-ticket-frontend 2>/dev/null || true

  echo "▶ Starting frontend container..."
  docker run -d \
    --name smart-ticket-frontend \
    --restart unless-stopped \
    -p 80:80 \
    smart-ticket-frontend

  sleep 3
  if curl -sf "http://localhost:80" -o /dev/null; then
    echo "✅ Frontend live at http://${FRONTEND_VM_IP}"
  else
    echo "⚠ Frontend check failed — check: docker logs smart-ticket-frontend"
  fi
}

seed_data() {
  check_placeholders
  cd "$REPO_DIR/data"
  echo "▶ Generating synthetic tickets..."
  python3 generate_dataset.py
  echo "▶ Seeding 50 demo tickets via API..."
  python3 seed.py --url "http://${BACKEND_VM_IP}:8000" --count 50
  echo "✅ Seeding complete."
}

case "${1:-all}" in
  backend)  deploy_backend ;;
  frontend) deploy_frontend ;;
  seed)     seed_data ;;
  all)
    deploy_backend
    deploy_frontend
    echo ""
    echo "════════════════════════════════════════"
    echo "✅ FULL DEPLOYMENT COMPLETE"
    echo "════════════════════════════════════════"
    echo "Backend API:  http://${BACKEND_VM_IP}:8000"
    echo "API Docs:     http://${BACKEND_VM_IP}:8000/docs"
    echo "Frontend:     http://${FRONTEND_VM_IP}"
    echo ""
    echo "Next: bash deploy.sh seed   (load 50 demo tickets)"
    ;;
  *) echo "Usage: deploy.sh [backend|frontend|seed|all]" ;;
esac
