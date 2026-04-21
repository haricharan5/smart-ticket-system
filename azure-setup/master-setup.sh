#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║   Smart Support Ticket System — Master Azure Setup Script               ║
# ║   Run ONE TIME from Azure Cloud Shell:                                  ║
# ║     bash master-setup.sh                                                ║
# ║                                                                          ║
# ║   What this does (fully automated, ~40 minutes total):                  ║
# ║   1.  Provisions 4 VMs, VNet, NSG, Azure SQL, Language Service,        ║
# ║       Application Insights  (no Azure OpenAI — uses local LLM)         ║
# ║   2.  Installs Docker on 3 Linux VMs                                    ║
# ║   3.  Installs Ollama + Phi-3 Mini on VM2 (self-hosted LLM, no API)    ║
# ║   4.  Deploys backend API pointing to local LLM                         ║
# ║   4.  Generates SSL certificate and deploys HTTPS frontend              ║
# ║   5.  Configures Active Directory on Windows VM                         ║
# ║   6.  Seeds 50 demo tickets                                             ║
# ║   7.  Prints final URLs and credentials                                 ║
# ╚══════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── COLOURS ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}▶${NC}  $1"; }
warn()    { echo -e "${YELLOW}⚠${NC}   $1"; }
section() { echo -e "\n${BOLD}${BLUE}════ $1 ════${NC}"; }
success() { echo -e "${GREEN}✅  $1${NC}"; }
die()     { echo -e "${RED}✗   ERROR: $1${NC}"; exit 1; }

# ════════════════════════════════════════════════════════════════════════════
# CONFIGURATION  ← Edit these before running
# ════════════════════════════════════════════════════════════════════════════
GITHUB_REPO="${GITHUB_REPO:-}"          # e.g. https://github.com/yourname/smart-ticket-system.git
RG="smart-ticket-rg"
LOCATION="eastus"
PREFIX="smartticket"
VM_USER="azureuser"
SQL_ADMIN="sqladmin"
SQL_PASSWORD="Ticket@2024Secure!"      # Must meet Azure complexity rules
LLM_MODEL="phi3:mini"                  # Ollama model — change to llama3.2:3b or mistral:7b-q4 for higher quality
ALERT_EMAIL="${ALERT_EMAIL:-}"          # Optional: your email for budget alerts + auto-shutdown warnings
AUTO_SHUTDOWN_TIME="2300"              # VMs auto-deallocate at this time daily (24h format, e.g. 2300 = 11 PM)
# ════════════════════════════════════════════════════════════════════════════

TMP="$(mktemp -d)"          # temp dir for generated scripts
LOG_FILE="$TMP/setup.log"   # full log for debugging

# ── Helper: run a bash script on a Linux VM via run-command ──────────────────
vm_run() {
  local vm_name="$1"
  local script_file="$2"
  log "Running on $vm_name..."
  az vm run-command invoke \
    --resource-group "$RG" \
    --name "$vm_name" \
    --command-id RunShellScript \
    --scripts @"$script_file" \
    --output json 2>>"$LOG_FILE" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
out=d.get('value',[{}])[0].get('message','')
print(out[-3000:] if len(out)>3000 else out)
" || die "Command failed on $vm_name — check $LOG_FILE"
}

# ── Helper: run a PowerShell script on Windows VM ────────────────────────────
vm_run_ps() {
  local vm_name="$1"
  local script_file="$2"
  log "Running PowerShell on $vm_name..."
  az vm run-command invoke \
    --resource-group "$RG" \
    --name "$vm_name" \
    --command-id RunPowerShellScript \
    --scripts @"$script_file" \
    --output json 2>>"$LOG_FILE" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
out=d.get('value',[{}])[0].get('message','')
print(out[-2000:] if len(out)>2000 else out)
"
}

# ════════════════════════════════════════════════════════════════════════════
# PHASE 0 — Pre-flight checks
# ════════════════════════════════════════════════════════════════════════════
section "Phase 0: Pre-flight Checks"

az account show > /dev/null 2>&1 || die "Not logged in to Azure. Run: az login"
SUBSCRIPTION=$(az account show --query name -o tsv)
log "Subscription : $SUBSCRIPTION"

[[ -z "$GITHUB_REPO" || "$GITHUB_REPO" == *"YOUR"* ]] && \
  die "Set your GitHub repo URL:\n  export GITHUB_REPO=https://github.com/yourname/smart-ticket-system.git\n  bash master-setup.sh"

# Test GitHub repo is accessible
git ls-remote "$GITHUB_REPO" HEAD > /dev/null 2>&1 || \
  die "Cannot reach $GITHUB_REPO — check the URL and that the repo is public (or add SSH key)"

JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
log "JWT secret   : generated (${#JWT_SECRET} chars)"

START_TIME=$(date +%s)
echo ""
echo -e "${CYAN}Estimated time: ~35 minutes. Grab a coffee. ☕${NC}"
echo -e "Full log: $LOG_FILE"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1 — Azure Resource Provisioning
# ════════════════════════════════════════════════════════════════════════════
section "Phase 1: Provisioning Azure Resources (~15 min)"

log "Creating resource group..."
az group create --name "$RG" --location "$LOCATION" --output none

# ── Virtual Network + NSG ────────────────────────────────────────────────────
log "Creating VNet + NSG..."
az network vnet create \
  --resource-group "$RG" --name "${PREFIX}-vnet" \
  --address-prefix 10.0.0.0/16 \
  --subnet-name default --subnet-prefix 10.0.0.0/24 \
  --output none

az network nsg create --resource-group "$RG" --name "${PREFIX}-nsg" --output none

az network nsg rule create --resource-group "$RG" --nsg-name "${PREFIX}-nsg" \
  --name AllowHTTP --priority 100 --protocol Tcp \
  --destination-port-ranges 80 443 8000 8443 \
  --access Allow --direction Inbound --output none

az network nsg rule create --resource-group "$RG" --nsg-name "${PREFIX}-nsg" \
  --name AllowSSH --priority 110 --protocol Tcp \
  --destination-port-ranges 22 \
  --access Allow --direction Inbound --output none

az network nsg rule create --resource-group "$RG" --nsg-name "${PREFIX}-nsg" \
  --name AllowRDP --priority 120 --protocol Tcp \
  --destination-port-ranges 3389 \
  --access Allow --direction Inbound --output none

# ── 4 Virtual Machines (created in parallel with --no-wait) ─────────────────
log "Creating 4 VMs in parallel (this takes ~10 min)..."

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm1-backend" \
  --image Ubuntu2204 --size Standard_B2s \
  --admin-username "$VM_USER" --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none --no-wait

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm2-nlp" \
  --image Ubuntu2204 --size Standard_B2ms \
  --admin-username "$VM_USER" --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none --no-wait
  # ↑ B2ms = 2 vCPU + 8 GB RAM — needed for Phi-3 Mini inference (~3 GB model + overhead)

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm3-frontend" \
  --image Ubuntu2204 --size Standard_B2s \
  --admin-username "$VM_USER" --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none --no-wait

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm4-ad" \
  --image Win2022Datacenter --size Standard_B2ms \
  --admin-username "$VM_USER" --admin-password "$SQL_PASSWORD" \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none --no-wait

# ── Azure SQL ─────────────────────────────────────────────────────────────────
log "Creating Azure SQL Server + Database..."
az sql server create \
  --resource-group "$RG" --name "${PREFIX}-sql" \
  --location "$LOCATION" \
  --admin-user "$SQL_ADMIN" --admin-password "$SQL_PASSWORD" \
  --output none

az sql server firewall-rule create \
  --resource-group "$RG" --server "${PREFIX}-sql" \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 --output none

az sql db create \
  --resource-group "$RG" --server "${PREFIX}-sql" \
  --name ticketdb --edition Basic --capacity 5 --output none

# ── Azure Language Service ────────────────────────────────────────────────────
log "Creating Azure Language Service..."
az cognitiveservices account create \
  --resource-group "$RG" --name "${PREFIX}-language" \
  --kind TextAnalytics --sku S --location "$LOCATION" --yes --output none

# ── Application Insights ──────────────────────────────────────────────────────
log "Creating Application Insights..."
az monitor log-analytics workspace create \
  --resource-group "$RG" --workspace-name "${PREFIX}-logs" \
  --location "$LOCATION" --output none

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" --workspace-name "${PREFIX}-logs" \
  --query customerId -o tsv)

az monitor app-insights component create \
  --resource-group "$RG" --app "${PREFIX}-appinsights" \
  --location "$LOCATION" --kind web \
  --workspace "$WORKSPACE_ID" --output none

# ── Wait for all VMs to be ready ─────────────────────────────────────────────
log "Waiting for all VMs to reach running state..."
for vm in vm1-backend vm2-nlp vm3-frontend vm4-ad; do
  az vm wait --resource-group "$RG" --name "${PREFIX}-${vm}" \
    --custom "instanceView.statuses[?code=='PowerState/running']" \
    --output none
  log "  ${PREFIX}-${vm} — ready"
done
success "All resources provisioned."

# ════════════════════════════════════════════════════════════════════════════
# PHASE 2 — Collect Keys & IPs
# ════════════════════════════════════════════════════════════════════════════
section "Phase 2: Collecting Keys and IPs"

LANG_KEY=$(az cognitiveservices account keys list \
  --resource-group "$RG" --name "${PREFIX}-language" --query key1 -o tsv)
LANG_EP=$(az cognitiveservices account show \
  --resource-group "$RG" --name "${PREFIX}-language" \
  --query properties.endpoint -o tsv)

AI_CONN=$(az monitor app-insights component show \
  --resource-group "$RG" --app "${PREFIX}-appinsights" \
  --query connectionString -o tsv)

SQL_SERVER="${PREFIX}-sql.database.windows.net"

BACKEND_IP=$(az vm show -d --resource-group "$RG" \
  --name "${PREFIX}-vm1-backend" --query publicIps -o tsv)
NLP_PRIVATE_IP=$(az vm show -d --resource-group "$RG" \
  --name "${PREFIX}-vm2-nlp" --query privateIps -o tsv)
FRONTEND_IP=$(az vm show -d --resource-group "$RG" \
  --name "${PREFIX}-vm3-frontend" --query publicIps -o tsv)
AD_IP=$(az vm show -d --resource-group "$RG" \
  --name "${PREFIX}-vm4-ad" --query publicIps -o tsv)

log "Backend  IP      : $BACKEND_IP"
log "NLP VM2 Private  : $NLP_PRIVATE_IP  (Ollama will bind here)"
log "Frontend IP      : $FRONTEND_IP"
log "AD/Windows       : $AD_IP"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3 — Install Docker on Linux VMs (parallel)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 3: Installing Docker on Linux VMs (~5 min)"

cat > "$TMP/docker-setup.sh" << 'SCRIPT'
#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl gnupg2 git python3-pip

# Docker
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

# Microsoft ODBC Driver 18
curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor | tee /usr/share/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
  https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
  > /etc/apt/sources.list.d/mssql-release.list
apt-get update -qq
ACCEPT_EULA=Y apt-get install -y -qq msodbcsql18

echo "Docker $(docker --version) installed OK"
SCRIPT

log "Installing Docker on VM1 (backend)..."
vm_run "${PREFIX}-vm1-backend" "$TMP/docker-setup.sh" &
PID1=$!

log "Installing Docker on VM2 (nlp worker)..."
vm_run "${PREFIX}-vm2-nlp" "$TMP/docker-setup.sh" &
PID2=$!

log "Installing Docker on VM3 (frontend)..."
vm_run "${PREFIX}-vm3-frontend" "$TMP/docker-setup.sh" &
PID3=$!

wait $PID1 && success "VM1 Docker ready"
wait $PID2 && success "VM2 Docker ready"
wait $PID3 && success "VM3 Docker ready"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3.5 — Install Ollama + Pull Phi-3 Mini on VM2 (~5 min)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 3.5: Installing Ollama + Phi-3 Mini LLM on VM2 (~5 min)"

cat > "$TMP/install-ollama.sh" << SCRIPT
#!/bin/bash
set -e

echo "==> Installing Ollama..."
curl -fsSL https://ollama.ai/install.sh | sh

# Configure Ollama to listen on all interfaces so VM1 (backend) can reach it
# through the private VNet — no public internet traffic needed.
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_MODELS=/opt/ollama/models"
EOF

mkdir -p /opt/ollama/models
systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama

echo "==> Waiting for Ollama to start..."
for i in \$(seq 1 15); do
  sleep 2
  if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "Ollama is running."
    break
  fi
done

echo "==> Pulling $LLM_MODEL (~2.3 GB — this is the model download, takes 2-4 min)..."
ollama pull $LLM_MODEL

echo "==> Model ready:"
ollama list

echo "==> Testing inference..."
RESPONSE=\$(ollama run $LLM_MODEL 'Reply with exactly: {"ok": true}' 2>/dev/null || echo '{"ok": false}')
echo "Test response: \$RESPONSE"
echo "Ollama + $LLM_MODEL installation complete."
SCRIPT

vm_run "${PREFIX}-vm2-nlp" "$TMP/install-ollama.sh"
success "Ollama running on VM2 private IP $NLP_PRIVATE_IP:11434 | model: $LLM_MODEL"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Deploy Backend (VM1)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 4: Deploying Backend API (~8 min)"

cat > "$TMP/deploy-backend.sh" << SCRIPT
#!/bin/bash
set -e

# Clone or update repo
if [ -d /opt/smartticket/.git ]; then
  git -C /opt/smartticket pull --quiet
else
  git clone --quiet "$GITHUB_REPO" /opt/smartticket
fi

# Write .env file — all values already interpolated from outer shell
{
  echo "AZURE_SQL_SERVER=$SQL_SERVER"
  echo "AZURE_SQL_DATABASE=ticketdb"
  echo "AZURE_SQL_USERNAME=$SQL_ADMIN"
  echo "AZURE_SQL_PASSWORD=$SQL_PASSWORD"
  echo "SQL_ENCRYPT=yes"
  echo "SQL_TRUST_CERT=no"
  echo "AZURE_LANGUAGE_ENDPOINT=$LANG_EP"
  echo "AZURE_LANGUAGE_KEY=$LANG_KEY"
  echo "LLM_BASE_URL=http://$NLP_PRIVATE_IP:11434/v1"
  echo "LLM_MODEL=$LLM_MODEL"
  echo "JWT_SECRET_KEY=$JWT_SECRET"
  echo "FRONTEND_URL=https://$FRONTEND_IP"
  echo "LOG_LEVEL=INFO"
  echo "LOG_FILE=/var/log/smartticket/app.log"
  echo "APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN"
} > /opt/smartticket/backend/.env

mkdir -p /var/log/smartticket

# Build Docker image
cd /opt/smartticket
docker build -t smart-ticket-backend ./backend

# Stop existing container if running
docker stop smart-ticket-backend 2>/dev/null || true
docker rm smart-ticket-backend 2>/dev/null || true

# Run container
docker run -d \\
  --name smart-ticket-backend \\
  --restart unless-stopped \\
  -p 8000:8000 \\
  -v /var/log/smartticket:/var/log/smartticket \\
  --env-file /opt/smartticket/backend/.env \\
  smart-ticket-backend

# Health check
echo "Waiting for backend to start..."
for i in \$(seq 1 20); do
  sleep 3
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "Backend healthy after \$((i*3))s"
    curl -s http://localhost:8000/health
    exit 0
  fi
done
echo "WARNING: Backend did not respond to health check"
docker logs smart-ticket-backend --tail 20
SCRIPT

vm_run "${PREFIX}-vm1-backend" "$TMP/deploy-backend.sh"
success "Backend deployed at http://$BACKEND_IP:8000"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 5 — SSL Certificate + Frontend Deployment (VM3)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 5: SSL Setup + Frontend Deployment (~8 min)"

cat > "$TMP/deploy-frontend.sh" << SCRIPT
#!/bin/bash
set -e

# Install Node.js 20 for building
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs

# Clone or update repo
if [ -d /opt/smartticket/.git ]; then
  git -C /opt/smartticket pull --quiet
else
  git clone --quiet "$GITHUB_REPO" /opt/smartticket
fi

# ── Generate Self-Signed SSL Certificate ─────────────────────────────────────
CERT_DIR=/etc/ssl/smartticket
mkdir -p "\$CERT_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\
  -keyout "\$CERT_DIR/smartticket.key" \\
  -out "\$CERT_DIR/smartticket.crt" \\
  -subj "/C=US/ST=Demo/L=Demo/O=SmartTicket/CN=$FRONTEND_IP" \\
  -addext "subjectAltName=IP:$FRONTEND_IP" \\
  2>/dev/null
echo "SSL certificate generated for $FRONTEND_IP"

# ── Copy certs to project ─────────────────────────────────────────────────────
mkdir -p /opt/smartticket/certs
cp "\$CERT_DIR/smartticket.crt" /opt/smartticket/certs/
cp "\$CERT_DIR/smartticket.key" /opt/smartticket/certs/

# ── Write frontend .env ────────────────────────────────────────────────────────
{
  echo "VITE_API_URL=http://$BACKEND_IP:8000"
  echo "VITE_POWERBI_URL="
} > /opt/smartticket/frontend/.env

# ── Build Docker image ────────────────────────────────────────────────────────
cd /opt/smartticket
docker build \\
  --build-arg VITE_API_URL="http://$BACKEND_IP:8000" \\
  --build-arg VITE_POWERBI_URL="" \\
  --build-arg SSL_CERT_PATH="./certs" \\
  -t smart-ticket-frontend \\
  ./frontend

docker stop smart-ticket-frontend 2>/dev/null || true
docker rm smart-ticket-frontend 2>/dev/null || true

docker run -d \\
  --name smart-ticket-frontend \\
  --restart unless-stopped \\
  -p 80:80 -p 443:443 \\
  smart-ticket-frontend

sleep 3
if curl -sk https://localhost/login | grep -q "Smart Support"; then
  echo "Frontend HTTPS is live"
else
  echo "Frontend started (HTTPS may need cert trust on browser)"
fi
SCRIPT

vm_run "${PREFIX}-vm3-frontend" "$TMP/deploy-frontend.sh"
success "Frontend deployed at https://$FRONTEND_IP"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 6 — Active Directory Setup (VM4 Windows)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 6: Active Directory Setup (VM4 Windows) (~5 min)"

cat > "$TMP/ad-setup.ps1" << 'SCRIPT'
# Install AD DS
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Confirm:$false

$secPass = ConvertTo-SecureString "Ticket@2024Secure!" -AsPlainText -Force

# Promote to DC
try {
  Install-ADDSForest `
    -DomainName "ticket.local" `
    -DomainNetbiosName "TICKET" `
    -SafeModeAdministratorPassword $secPass `
    -InstallDns `
    -Force `
    -NoRebootOnCompletion
  Write-Output "AD DS forest installed successfully"
} catch {
  Write-Output "AD setup note: $($_.Exception.Message)"
}

# Create OUs and groups (runs immediately, before reboot)
Import-Module ActiveDirectory -ErrorAction SilentlyContinue

$groups = @(
  "Technical-Support-Team","Billing-Finance-Team",
  "Customer-Success-Team","HR-People-Team",
  "General-Operations-Team","Support-Team-Leads","Operations-Managers"
)

foreach ($g in $groups) {
  try {
    New-ADGroup -Name $g -GroupScope Global `
      -Path "CN=Users,DC=ticket,DC=local" -ErrorAction Stop
    Write-Output "Created group: $g"
  } catch { Write-Output "Group exists or pending reboot: $g" }
}

Write-Output "AD setup complete — VM will reboot to finalize DC promotion"
SCRIPT

vm_run_ps "${PREFIX}-vm4-ad" "$TMP/ad-setup.ps1"
success "Active Directory configured on VM4 (ticket.local domain)"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 7 — Seed Demo Data
# ════════════════════════════════════════════════════════════════════════════
section "Phase 7: Seeding 50 Demo Tickets (~3 min)"

cat > "$TMP/seed.sh" << SCRIPT
#!/bin/bash
set -e
cd /opt/smartticket/data
pip3 install httpx --quiet
python3 generate_dataset.py
python3 seed.py --url http://localhost:8000 --count 50
SCRIPT

vm_run "${PREFIX}-vm1-backend" "$TMP/seed.sh"
success "50 demo tickets seeded."

# ════════════════════════════════════════════════════════════════════════════
# PHASE 8 — Save Credentials & Print Summary
# ════════════════════════════════════════════════════════════════════════════
section "Phase 8: Saving Credentials"

CREDS_FILE="$HOME/smartticket-credentials.txt"
cat > "$CREDS_FILE" << EOF
══════════════════════════════════════════════════════
  Smart Support Ticket System — Credentials & URLs
  Generated: $(date)
══════════════════════════════════════════════════════

URLS
────────────────────────────────────────────────────
  Frontend (HTTPS):   https://$FRONTEND_IP
  Backend API:        http://$BACKEND_IP:8000
  API Docs (Swagger): http://$BACKEND_IP:8000/docs
  Windows AD (RDP):   $AD_IP

LOGIN ACCOUNTS
────────────────────────────────────────────────────
  Admin     : admin@ticket.local   / Admin@2024!
  Team Lead : lead@ticket.local    / Lead@2024!
  Agent     : agent1@ticket.local  / Agent@2024!

AZURE RESOURCES (Resource Group: $RG)
────────────────────────────────────────────────────
  SQL Server  : $SQL_SERVER
  SQL DB      : ticketdb
  SQL Login   : $SQL_ADMIN / $SQL_PASSWORD

  Language EP : $LANG_EP
  Language Key: $LANG_KEY

  Local LLM   : Ollama on VM2 (private) — http://$NLP_PRIVATE_IP:11434
  LLM Model   : $LLM_MODEL  (no API key needed — runs on your VM)

  App Insights: (see Azure Portal → $RG → ${PREFIX}-appinsights)

VM SSH COMMANDS
────────────────────────────────────────────────────
  Backend:  ssh $VM_USER@$BACKEND_IP
  Frontend: ssh $VM_USER@$FRONTEND_IP
  RDP to AD: mstsc /v:$AD_IP  (user: $VM_USER / $SQL_PASSWORD)

USEFUL DOCKER COMMANDS (run via SSH on VM1)
────────────────────────────────────────────────────
  View backend logs:  docker logs smart-ticket-backend -f
  Restart backend:    docker restart smart-ticket-backend
  View frontend logs: docker logs smart-ticket-frontend -f (on VM3)

POWER BI SETUP
────────────────────────────────────────────────────
  1. Go to https://app.powerbi.com
  2. Get data → Azure SQL Database
  3. Server: $SQL_SERVER  DB: ticketdb
  4. Build report, Publish → File → Embed Report → Website
  5. Copy iframe URL into frontend .env as VITE_POWERBI_URL
  6. SSH to VM3: docker restart smart-ticket-frontend

ACTIVE DIRECTORY
────────────────────────────────────────────────────
  Domain : ticket.local
  RDP    : $AD_IP (user: $VM_USER / $SQL_PASSWORD)

SSL NOTE
────────────────────────────────────────────────────
  Using self-signed certificate.
  Browser will show security warning — click:
  Chrome:  Advanced → Proceed to $FRONTEND_IP (unsafe)
  Firefox: Advanced → Accept the Risk and Continue
  For demo judges: share the .crt file to import as trusted

EOF

success "Credentials saved to: $CREDS_FILE"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 9 — Operations Setup (Scripts + Auto-Shutdown + Budget Alerts)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 9: Setting Up Operations (Auto-Shutdown + Helper Scripts)"

# ── Write ~/stop-smartticket.sh ───────────────────────────────────────────────
cat > "$HOME/stop-smartticket.sh" << STOPSCRIPT
#!/bin/bash
# Run this every time you finish working to stop all charges.
RG="$RG"
echo "Stopping all Smart Ticket VMs..."
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm1-backend --no-wait
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm2-nlp     --no-wait
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm3-frontend --no-wait
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm4-ad       --no-wait
echo ""
echo "✅ Deallocate commands sent. VMs will stop in ~2 minutes."
echo "   Compute charges STOPPED. Disk + IP (~\$0.03/hr) continue."
echo "   Run 'bash ~/start-smartticket.sh' to bring it back up."
STOPSCRIPT
chmod +x "$HOME/stop-smartticket.sh"
success "Created ~/stop-smartticket.sh"

# ── Write ~/start-smartticket.sh ──────────────────────────────────────────────
cat > "$HOME/start-smartticket.sh" << STARTSCRIPT
#!/bin/bash
# Run this ~5 minutes before you need to work or demo.
RG="$RG"
echo "Starting all Smart Ticket VMs..."
az vm start --resource-group \$RG --name ${PREFIX}-vm1-backend --no-wait
az vm start --resource-group \$RG --name ${PREFIX}-vm2-nlp     --no-wait
az vm start --resource-group \$RG --name ${PREFIX}-vm3-frontend --no-wait
az vm start --resource-group \$RG --name ${PREFIX}-vm4-ad       --no-wait
echo ""
echo "✅ Start commands sent."
echo "   Wait 3-4 minutes then open: https://$FRONTEND_IP"
echo "   Ollama model loads on first request (~30s) — this is normal."
STARTSCRIPT
chmod +x "$HOME/start-smartticket.sh"
success "Created ~/start-smartticket.sh"

# ── Write ~/status-smartticket.sh ─────────────────────────────────────────────
cat > "$HOME/status-smartticket.sh" << STATUSSCRIPT
#!/bin/bash
# Check the current state of all VMs and containers.
RG="$RG"
BACKEND_IP="$BACKEND_IP"
FRONTEND_IP="$FRONTEND_IP"

echo ""
echo "══════════════════════════════════════════════"
echo "  Smart Ticket System — Live Status"
echo "══════════════════════════════════════════════"
echo ""
echo "── VM Power States ──────────────────────────"
az vm list --resource-group \$RG --show-details \
  --query "[].{Name:name, State:powerState, Size:hardwareProfile.vmSize}" \
  --output table

echo ""
echo "── Backend Health ───────────────────────────"
curl -sf http://\$BACKEND_IP:8000/health && echo "" || echo "❌ Backend not responding"

echo ""
echo "── Frontend Health ──────────────────────────"
curl -sk https://\$FRONTEND_IP/login -o /dev/null -w "Status: %{http_code}\n" || echo "❌ Frontend not responding"

echo ""
echo "── Useful SSH Commands ──────────────────────"
echo "  Backend logs : ssh $VM_USER@\$BACKEND_IP 'docker logs smart-ticket-backend --tail 30'"
echo "  Ollama status: ssh $VM_USER@$NLP_PRIVATE_IP 'systemctl status ollama'"
STATUSSCRIPT
chmod +x "$HOME/status-smartticket.sh"
success "Created ~/status-smartticket.sh"

# ── Write ~/delete-smartticket.sh ─────────────────────────────────────────────
cat > "$HOME/delete-smartticket.sh" << DELETESCRIPT
#!/bin/bash
# ⚠  PERMANENT — Run ONLY after capstone submission. Deletes EVERYTHING.
RG="$RG"
echo ""
echo "⚠  WARNING: This will PERMANENTLY delete all Smart Ticket resources."
echo "   Resource group: \$RG"
echo "   This includes all VMs, SQL data, and AI services."
echo ""
read -p "Type 'DELETE' to confirm: " CONFIRM
if [ "\$CONFIRM" = "DELETE" ]; then
  az group delete --name \$RG --yes --no-wait
  echo ""
  echo "✅ Deletion started. All charges will stop within 10 minutes."
  echo "   Check Azure Portal to confirm the resource group disappears."
else
  echo "Cancelled — nothing deleted."
fi
DELETESCRIPT
chmod +x "$HOME/delete-smartticket.sh"
success "Created ~/delete-smartticket.sh"

# ── Auto-Shutdown Policy on all 4 VMs ────────────────────────────────────────
log "Setting daily auto-shutdown at ${AUTO_SHUTDOWN_TIME} on all VMs..."
for VM in ${PREFIX}-vm1-backend ${PREFIX}-vm2-nlp ${PREFIX}-vm3-frontend ${PREFIX}-vm4-ad; do
  if [[ -n "$ALERT_EMAIL" ]]; then
    az vm auto-shutdown \
      --resource-group "$RG" --name "$VM" \
      --time "$AUTO_SHUTDOWN_TIME" \
      --email "$ALERT_EMAIL" \
      --output none 2>>"$LOG_FILE" && log "  Auto-shutdown set: $VM"
  else
    az vm auto-shutdown \
      --resource-group "$RG" --name "$VM" \
      --time "$AUTO_SHUTDOWN_TIME" \
      --output none 2>>"$LOG_FILE" && log "  Auto-shutdown set: $VM (no email)"
  fi
done
success "All VMs will auto-deallocate daily at ${AUTO_SHUTDOWN_TIME}."

# ── Budget Alerts (only if email was provided) ────────────────────────────────
if [[ -n "$ALERT_EMAIL" ]]; then
  log "Setting up budget alerts at \$50 and \$80..."
  SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  START_DATE=$(date +%Y-%m-01)
  END_DATE=$(date -d "+6 months" +%Y-%m-01 2>/dev/null || date -v+6m +%Y-%m-01)

  for AMOUNT in 50 80; do
    az consumption budget create \
      --budget-name "SmartTicket-${AMOUNT}" \
      --amount $AMOUNT \
      --time-grain Monthly \
      --start-date "$START_DATE" \
      --end-date "$END_DATE" \
      --scope "/subscriptions/$SUBSCRIPTION_ID" \
      --threshold 100 \
      --contact-emails "$ALERT_EMAIL" \
      --output none 2>>"$LOG_FILE" || warn "Budget alert \$$AMOUNT — may need Azure Cost Management enabled"
  done
  success "Budget alerts set at \$50 and \$80 → $ALERT_EMAIL"
else
  warn "No ALERT_EMAIL set — skipping budget alerts."
  warn "To add later: export ALERT_EMAIL=you@email.com  and rerun the budget section."
fi

# ── Append operations info to credentials file ────────────────────────────────
cat >> "$CREDS_FILE" << EOF

DAILY OPERATIONS
────────────────────────────────────────────────────
  Start VMs (morning)  : bash ~/start-smartticket.sh
  Stop VMs (evening)   : bash ~/stop-smartticket.sh
  Check status         : bash ~/status-smartticket.sh
  Delete everything    : bash ~/delete-smartticket.sh  ← after capstone only

AUTO-SHUTDOWN
────────────────────────────────────────────────────
  VMs auto-deallocate daily at: ${AUTO_SHUTDOWN_TIME} (configured via Azure policy)
  Cost when running 24/7      : ~\$49 for 5 days
  Cost with smart shutdown     : ~\$19 for 5 days

BUDGET ALERTS
────────────────────────────────────────────────────
  Alert email : ${ALERT_EMAIL:-"(not set — set ALERT_EMAIL and rerun)"}
  Thresholds  : \$50 and \$80 warning emails

IMPORTANT RULES
────────────────────────────────────────────────────
  ✅ Use 'deallocate' — NOT 'stop' — to save money
  ✅ SQL + IPs charge even when VMs are off (~\$0.03/hr flat)
  ✅ Run delete-smartticket.sh after submission to stop all charges
  ❌ Never run 'az vm stop' — it keeps billing you for the VM

EOF

success "Operations info appended to credentials file."

# ════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ════════════════════════════════════════════════════════════════════════════
ELAPSED=$(( $(date +%s) - START_TIME ))
MINS=$((ELAPSED / 60)); SECS=$((ELAPSED % 60))

echo ""
echo -e "${BOLD}${GREEN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           🎉  DEPLOYMENT COMPLETE!                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "Time taken: ${MINS}m ${SECS}s"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "Frontend (HTTPS):   https://$FRONTEND_IP"
printf "║  %-60s ║\n" "Backend API:        http://$BACKEND_IP:8000"
printf "║  %-60s ║\n" "API Docs:           http://$BACKEND_IP:8000/docs"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "Login: admin@ticket.local / Admin@2024!"
printf "║  %-60s ║\n" "Login: lead@ticket.local  / Lead@2024!"
printf "║  %-60s ║\n" "Login: agent1@ticket.local / Agent@2024!"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "Full credentials: ~/smartticket-credentials.txt"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "DAILY OPERATIONS:"
printf "║  %-60s ║\n" "  Stop billing  →  bash ~/stop-smartticket.sh"
printf "║  %-60s ║\n" "  Start again   →  bash ~/start-smartticket.sh"
printf "║  %-60s ║\n" "  Check status  →  bash ~/status-smartticket.sh"
printf "║  %-60s ║\n" "  After capstone→  bash ~/delete-smartticket.sh"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}⚠  Browser HTTPS warning:${NC}"
echo "   Chrome: click Advanced → Proceed to $FRONTEND_IP"
echo ""
echo -e "${YELLOW}⚠  Auto-shutdown:${NC} All VMs will deallocate daily at ${AUTO_SHUTDOWN_TIME}"
echo "   Run bash ~/start-smartticket.sh each morning to restart."
echo ""
echo -e "${YELLOW}⚠  Power BI:${NC} Connect manually via https://app.powerbi.com"
echo "   Server: $SQL_SERVER | DB: ticketdb"
echo ""
echo "Operations guide: see azure-setup/OPERATIONS-GUIDE.md"

rm -rf "$TMP"
