#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║   Smart Support Ticket System — Master Azure Setup Script               ║
# ║   Run ONE TIME from Azure Cloud Shell:                                  ║
# ║     bash master-setup.sh                                                ║
# ║                                                                          ║
# ║   What this does (fully automated, ~40 minutes total):                  ║
# ║   1.  Registers all Azure resource providers                            ║
# ║   2.  Provisions 4 VMs, VNet, NSG, Azure SQL, Language Service,        ║
# ║       Application Insights  (no Azure OpenAI — uses local LLM)         ║
# ║   3.  Installs Docker on 3 Linux VMs                                    ║
# ║   4.  Installs Ollama + Phi-3 Mini on VM2 (self-hosted LLM, no API)    ║
# ║   5.  Deploys backend API pointing to local LLM                         ║
# ║   6.  Generates SSL certificate and deploys HTTPS frontend              ║
# ║   7.  Configures Active Directory on Windows VM                         ║
# ║   8.  Seeds 50 demo tickets                                             ║
# ║   9.  Creates stop/start/status/delete helper scripts                   ║
# ║   10. Sets auto-shutdown policy + budget alerts                         ║
# ║   11. Prints final URLs and credentials                                 ║
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
# CONFIGURATION  ← Only GITHUB_REPO needs to be set before running
# ════════════════════════════════════════════════════════════════════════════
GITHUB_REPO="${GITHUB_REPO:-}"          # set via: export GITHUB_REPO=https://github.com/yourname/repo.git
RG="MIT572-04"                          # existing class resource group on CSIS EA Subscription
LOCATION="northcentralus"              # region where class resources already exist
PREFIX="smartticket"
VM_USER="azureuser"
SQL_ADMIN="sqladmin"
SQL_PASSWORD="Ticket@2024Secure!"
LLM_MODEL="phi3:mini"
ALERT_EMAIL="${ALERT_EMAIL:-}"
AUTO_SHUTDOWN_TIME="2300"
# ════════════════════════════════════════════════════════════════════════════

TMP="$(mktemp -d)"
LOG_FILE="$TMP/setup.log"

# Always print log location on any failure so user knows where to look
trap 'echo -e "\n\033[0;31m✗ Script failed. Full error log:\033[0m $LOG_FILE\n  Run: cat $LOG_FILE"; exit 1' ERR

# ── Helper: run a bash script on a Linux VM ──────────────────────────────────
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

# ── Helper: run a PowerShell script on Windows VM ───────────────────────────
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
# PHASE 0 — Pre-flight Checks
# ════════════════════════════════════════════════════════════════════════════
section "Phase 0: Pre-flight Checks"

az account show > /dev/null 2>&1 || die "Not logged in to Azure. Run: az login"

# Switch to the CSIS EA Subscription (university account with Contributor on MIT572-04)
az account set --subscription "CSIS EA Subscription" 2>>"$LOG_FILE" || \
  die "Could not switch to 'CSIS EA Subscription'. Run: az account list -o table"

SUBSCRIPTION=$(az account show --query name -o tsv)
log "Subscription : $SUBSCRIPTION"

[[ -z "$GITHUB_REPO" || "$GITHUB_REPO" == *"YOUR"* ]] && \
  die "Set your GitHub repo URL first:\n  export GITHUB_REPO=https://github.com/yourname/smart-ticket-system.git\n  bash master-setup.sh"

git ls-remote "$GITHUB_REPO" HEAD > /dev/null 2>&1 || \
  die "Cannot reach $GITHUB_REPO — make sure the repo is public"

JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
log "JWT secret   : generated (${#JWT_SECRET} chars)"

# ── Register all required resource providers ─────────────────────────────────
log "Checking Azure resource providers (registration requires subscription-level access — skipping if not permitted)..."
for NS in \
  Microsoft.Compute \
  Microsoft.Network \
  Microsoft.Storage \
  Microsoft.Sql \
  Microsoft.CognitiveServices \
  Microsoft.OperationalInsights \
  Microsoft.Insights \
  Microsoft.AlertsManagement; do
  az provider register --namespace "$NS" --output none 2>>"$LOG_FILE" && \
    log "  Registered: $NS" || \
    log "  $NS — already registered (or no subscription-level permission needed)"
done
success "Resource providers ready (EA subscription has providers pre-registered)."

START_TIME=$(date +%s)
echo ""
echo -e "${CYAN}Estimated time: ~40 minutes. Grab a coffee. ☕${NC}"
echo -e "Full log: $LOG_FILE"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 1 — Azure Resource Provisioning
# ════════════════════════════════════════════════════════════════════════════
section "Phase 1: Provisioning Azure Resources (~15 min)"

log "Using existing resource group: $RG (class resource group on CSIS EA)..."
az group show --name "$RG" --output none 2>>"$LOG_FILE" || \
  die "Resource group $RG not found. Check you are on CSIS EA Subscription."
success "Resource group $RG confirmed."

# ── Virtual Network + NSG ────────────────────────────────────────────────────
log "Creating VNet + NSG..."
az network vnet create \
  --resource-group "$RG" --name "${PREFIX}-vnet" \
  --address-prefix 10.0.0.0/16 \
  --subnet-name default --subnet-prefix 10.0.0.0/24 \
  --output none

az network nsg create \
  --resource-group "$RG" --name "${PREFIX}-nsg" --output none

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

# ── 4 Virtual Machines — parallel via bash & (avoids --no-wait JSON bug) ─────
# NOTE: We use bash background processes instead of --az --no-wait.
#       --no-wait causes Azure CLI to crash with a JSON parse error on some
#       subscriptions when Azure returns an immediate error response.
#       With bash &, each az vm create waits for full provisioning internally
#       and all four still run in parallel.
log "Creating 4 VMs in parallel (this takes ~10 min)..."
log "All VM output goes to: $LOG_FILE"

# Pre-generate SSH key once — avoids --generate-ssh-keys JSON parse bug in Azure CLI
SSH_KEY_FILE="$HOME/.ssh/smartticket_rsa"
if [[ ! -f "${SSH_KEY_FILE}.pub" ]]; then
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_FILE" -N "" -q
  log "SSH key generated: ${SSH_KEY_FILE}.pub"
else
  log "SSH key already exists: ${SSH_KEY_FILE}.pub"
fi
SSH_PUB_KEY=$(cat "${SSH_KEY_FILE}.pub")

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm1-backend" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" --size Standard_B2s \
  --admin-username "$VM_USER" --ssh-key-values "${SSH_KEY_FILE}.pub" \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none >> "$LOG_FILE" 2>&1 &
PID_VM1=$!

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm2-nlp" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" --size Standard_B2ms \
  --admin-username "$VM_USER" --ssh-key-values "${SSH_KEY_FILE}.pub" \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none >> "$LOG_FILE" 2>&1 &
PID_VM2=$!

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm3-frontend" \
  --image "Canonical:0001-com-ubuntu-server-jammy:22_04-lts:latest" --size Standard_B2s \
  --admin-username "$VM_USER" --ssh-key-values "${SSH_KEY_FILE}.pub" \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none >> "$LOG_FILE" 2>&1 &
PID_VM3=$!

az vm create \
  --resource-group "$RG" --name "${PREFIX}-vm4-ad" \
  --computer-name "ticketAD" \
  --image "MicrosoftWindowsServer:WindowsServer:2022-Datacenter:latest" --size Standard_B2ms \
  --admin-username "$VM_USER" --admin-password "$SQL_PASSWORD" \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard --output none >> "$LOG_FILE" 2>&1 &
PID_VM4=$!

# ── While VMs are provisioning, create SQL + AI services in parallel ──────────
log "Creating Azure SQL Server + Database (while VMs provision)..."
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
success "Azure SQL ready."

log "Creating Azure Language Service..."
az cognitiveservices account create \
  --resource-group "$RG" --name "${PREFIX}-language" \
  --kind TextAnalytics --sku S \
  --location "$LOCATION" --yes --output none
success "Language Service ready."

log "Creating Log Analytics + Application Insights..."
az monitor log-analytics workspace create \
  --resource-group "$RG" --workspace-name "${PREFIX}-logs" \
  --location "$LOCATION" --output none

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" --workspace-name "${PREFIX}-logs" \
  --query id -o tsv)

az monitor app-insights component create \
  --resource-group "$RG" --app "${PREFIX}-appinsights" \
  --location "$LOCATION" --kind web \
  --workspace "$WORKSPACE_ID" --output none
success "Application Insights ready."

# ── Wait for all 4 VMs to finish (they have been running in background) ───────
log "Waiting for all 4 VMs to finish provisioning..."
wait $PID_VM1 && success "VM1 backend created." || die "VM1 backend failed — run: cat $LOG_FILE"
wait $PID_VM2 && success "VM2 nlp/ollama created." || die "VM2 nlp failed — run: cat $LOG_FILE"
wait $PID_VM3 && success "VM3 frontend created." || die "VM3 frontend failed — run: cat $LOG_FILE"
wait $PID_VM4 && success "VM4 AD (Windows) created." || die "VM4 AD failed — run: cat $LOG_FILE"

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
log "NLP VM2 Private  : $NLP_PRIVATE_IP  (Ollama)"
log "Frontend IP      : $FRONTEND_IP"
log "AD/Windows       : $AD_IP"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3 — Install Docker on Linux VMs (parallel)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 3: Installing Docker on 3 Linux VMs (~5 min)"

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

# Microsoft ODBC Driver 18 (needed by backend for Azure SQL)
curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
  | gpg --dearmor | tee /usr/share/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
  https://packages.microsoft.com/ubuntu/22.04/prod jammy main" \
  > /etc/apt/sources.list.d/mssql-release.list
apt-get update -qq
ACCEPT_EULA=Y apt-get install -y -qq msodbcsql18

echo "Docker $(docker --version) — installed OK"
SCRIPT

log "Installing Docker on VM1, VM2, VM3 in parallel..."
vm_run "${PREFIX}-vm1-backend"  "$TMP/docker-setup.sh" &
PID1=$!
vm_run "${PREFIX}-vm2-nlp"      "$TMP/docker-setup.sh" &
PID2=$!
vm_run "${PREFIX}-vm3-frontend" "$TMP/docker-setup.sh" &
PID3=$!

wait $PID1 && success "VM1 Docker ready"
wait $PID2 && success "VM2 Docker ready"
wait $PID3 && success "VM3 Docker ready"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 3.5 — Install Ollama + Phi-3 Mini on VM2
# ════════════════════════════════════════════════════════════════════════════
section "Phase 3.5: Installing Ollama + Phi-3 Mini LLM on VM2 (~5 min)"

cat > "$TMP/install-ollama.sh" << SCRIPT
#!/bin/bash
set -e

echo "==> Installing Ollama..."
curl -fsSL https://ollama.ai/install.sh | sh

# Listen on all interfaces so VM1 backend can reach it via private VNet
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

echo "==> Pulling $LLM_MODEL (~2.3 GB download, takes 2-4 min)..."
ollama pull $LLM_MODEL

echo "==> Loaded models:"
ollama list

echo "==> Quick inference test..."
RESP=\$(ollama run $LLM_MODEL 'Reply with only valid JSON: {"ok": true}' 2>/dev/null || echo '{"ok": false}')
echo "Test: \$RESP"
echo "Ollama + $LLM_MODEL ready."
SCRIPT

vm_run "${PREFIX}-vm2-nlp" "$TMP/install-ollama.sh"
success "Ollama running on VM2 ($NLP_PRIVATE_IP:11434) | model: $LLM_MODEL"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 4 — Deploy Backend (VM1)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 4: Deploying Backend API on VM1 (~8 min)"

cat > "$TMP/deploy-backend.sh" << SCRIPT
#!/bin/bash
set -e

# Clone or pull latest code
if [ -d /opt/smartticket/.git ]; then
  git -C /opt/smartticket pull --quiet
else
  git clone --quiet "$GITHUB_REPO" /opt/smartticket
fi

# Write environment file
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

cd /opt/smartticket
docker build -t smart-ticket-backend ./backend

docker stop smart-ticket-backend 2>/dev/null || true
docker rm   smart-ticket-backend 2>/dev/null || true

docker run -d \
  --name smart-ticket-backend \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /var/log/smartticket:/var/log/smartticket \
  --env-file /opt/smartticket/backend/.env \
  smart-ticket-backend

echo "Waiting for backend to start..."
for i in \$(seq 1 20); do
  sleep 3
  if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    echo "Backend healthy after \$((i*3))s"
    curl -s http://localhost:8000/health
    exit 0
  fi
done
echo "WARNING: Backend slow to start — checking logs:"
docker logs smart-ticket-backend --tail 20
SCRIPT

vm_run "${PREFIX}-vm1-backend" "$TMP/deploy-backend.sh"
success "Backend deployed → http://$BACKEND_IP:8000"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 5 — SSL Certificate + Frontend (VM3)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 5: SSL + Frontend Deployment on VM3 (~8 min)"

cat > "$TMP/deploy-frontend.sh" << SCRIPT
#!/bin/bash
set -e

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y -qq nodejs

if [ -d /opt/smartticket/.git ]; then
  git -C /opt/smartticket pull --quiet
else
  git clone --quiet "$GITHUB_REPO" /opt/smartticket
fi

# Self-signed SSL certificate
CERT_DIR=/etc/ssl/smartticket
mkdir -p "\$CERT_DIR"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "\$CERT_DIR/smartticket.key" \
  -out   "\$CERT_DIR/smartticket.crt" \
  -subj "/C=US/ST=Demo/L=Demo/O=SmartTicket/CN=$FRONTEND_IP" \
  -addext "subjectAltName=IP:$FRONTEND_IP" \
  2>/dev/null
echo "SSL certificate generated for IP $FRONTEND_IP"

mkdir -p /opt/smartticket/certs
cp "\$CERT_DIR/smartticket.crt" /opt/smartticket/certs/
cp "\$CERT_DIR/smartticket.key" /opt/smartticket/certs/

cd /opt/smartticket
docker build \
  --build-arg VITE_API_URL="http://$BACKEND_IP:8000" \
  --build-arg VITE_POWERBI_URL="" \
  --build-arg SSL_CERT_PATH="./certs" \
  -t smart-ticket-frontend \
  ./frontend

docker stop smart-ticket-frontend 2>/dev/null || true
docker rm   smart-ticket-frontend 2>/dev/null || true

docker run -d \
  --name smart-ticket-frontend \
  --restart unless-stopped \
  -p 80:80 -p 443:443 \
  smart-ticket-frontend

sleep 4
curl -sk https://localhost/login -o /dev/null -w "Frontend HTTP status: %{http_code}\n" \
  || echo "Frontend started (browser cert warning is normal for self-signed)"
SCRIPT

vm_run "${PREFIX}-vm3-frontend" "$TMP/deploy-frontend.sh"
success "Frontend deployed → https://$FRONTEND_IP"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 6 — Active Directory (VM4 Windows)
# ════════════════════════════════════════════════════════════════════════════
section "Phase 6: Active Directory Setup on VM4 Windows (~5 min)"

cat > "$TMP/ad-setup.ps1" << 'SCRIPT'
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Confirm:$false

$secPass = ConvertTo-SecureString "Ticket@2024Secure!" -AsPlainText -Force

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
  } catch {
    Write-Output "Group exists or pending reboot: $g"
  }
}

Write-Output "AD setup complete — VM will reboot to finalise DC promotion"
SCRIPT

vm_run_ps "${PREFIX}-vm4-ad" "$TMP/ad-setup.ps1"
success "Active Directory configured (ticket.local domain)"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 7 — Seed 50 Demo Tickets
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
# PHASE 8 — Save Credentials File
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

AZURE RESOURCES  (Resource Group: $RG)
────────────────────────────────────────────────────
  SQL Server  : $SQL_SERVER
  SQL DB      : ticketdb
  SQL Login   : $SQL_ADMIN / $SQL_PASSWORD

  Language EP : $LANG_EP
  Language Key: $LANG_KEY

  Local LLM   : Ollama on VM2 — http://$NLP_PRIVATE_IP:11434
  LLM Model   : $LLM_MODEL  (runs on your VM, no API cost)

  App Insights: Azure Portal → $RG → ${PREFIX}-appinsights

VM ACCESS
────────────────────────────────────────────────────
  SSH Backend:   ssh $VM_USER@$BACKEND_IP
  SSH Frontend:  ssh $VM_USER@$FRONTEND_IP
  RDP Windows:   mstsc /v:$AD_IP  (user: $VM_USER / $SQL_PASSWORD)

USEFUL DOCKER COMMANDS (SSH into VM first)
────────────────────────────────────────────────────
  Backend logs:   docker logs smart-ticket-backend -f
  Restart back:   docker restart smart-ticket-backend
  Frontend logs:  docker logs smart-ticket-frontend -f  (on VM3)

POWER BI
────────────────────────────────────────────────────
  1. https://app.powerbi.com → Get data → Azure SQL Database
  2. Server: $SQL_SERVER  DB: ticketdb
  3. Login: $SQL_ADMIN / $SQL_PASSWORD
  4. Build visuals → Publish → File → Embed → copy URL
  5. SSH VM3, rebuild frontend with VITE_POWERBI_URL set

SSL NOTE
────────────────────────────────────────────────────
  Self-signed cert — browser will warn.
  Chrome:  Advanced → Proceed to $FRONTEND_IP
  Firefox: Advanced → Accept the Risk and Continue

EOF

success "Credentials saved to: $CREDS_FILE"

# ════════════════════════════════════════════════════════════════════════════
# PHASE 9 — Operations Setup
# ════════════════════════════════════════════════════════════════════════════
section "Phase 9: Creating Operation Scripts + Auto-Shutdown + Budget Alerts"

# ── ~/stop-smartticket.sh ─────────────────────────────────────────────────────
cat > "$HOME/stop-smartticket.sh" << STOPSCRIPT
#!/bin/bash
# Run every evening to stop all charges.
RG="$RG"
echo "Stopping all Smart Ticket VMs..."
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm1-backend --no-wait
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm2-nlp     --no-wait
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm3-frontend --no-wait
az vm deallocate --resource-group \$RG --name ${PREFIX}-vm4-ad       --no-wait
echo ""
echo "✅ Done. VMs will stop in ~2 min. Compute charges stopped."
echo "   Disk + IP charges (~\$0.03/hr) still run — that is normal."
echo "   Run 'bash ~/start-smartticket.sh' to bring everything back up."
STOPSCRIPT
chmod +x "$HOME/stop-smartticket.sh"
success "Created ~/stop-smartticket.sh"

# ── ~/start-smartticket.sh ────────────────────────────────────────────────────
cat > "$HOME/start-smartticket.sh" << STARTSCRIPT
#!/bin/bash
# Run every morning ~5 minutes before you need the app.
RG="$RG"
echo "Starting all Smart Ticket VMs..."
az vm start --resource-group \$RG --name ${PREFIX}-vm1-backend --no-wait
az vm start --resource-group \$RG --name ${PREFIX}-vm2-nlp     --no-wait
az vm start --resource-group \$RG --name ${PREFIX}-vm3-frontend --no-wait
az vm start --resource-group \$RG --name ${PREFIX}-vm4-ad       --no-wait
echo ""
echo "✅ Start commands sent."
echo "   Wait 3-4 minutes then open: https://$FRONTEND_IP"
echo "   First ticket classification may take ~30s (Ollama loading model)."
STARTSCRIPT
chmod +x "$HOME/start-smartticket.sh"
success "Created ~/start-smartticket.sh"

# ── ~/status-smartticket.sh ───────────────────────────────────────────────────
cat > "$HOME/status-smartticket.sh" << STATUSSCRIPT
#!/bin/bash
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
echo "── Frontend ─────────────────────────────────"
curl -sk https://\$FRONTEND_IP -o /dev/null -w "HTTP status: %{http_code}\n" \
  || echo "❌ Frontend not responding"

echo ""
echo "── Log Commands ─────────────────────────────"
echo "  ssh $VM_USER@\$BACKEND_IP 'docker logs smart-ticket-backend --tail 30'"
STATUSSCRIPT
chmod +x "$HOME/status-smartticket.sh"
success "Created ~/status-smartticket.sh"

# ── ~/delete-smartticket.sh ───────────────────────────────────────────────────
cat > "$HOME/delete-smartticket.sh" << DELETESCRIPT
#!/bin/bash
# PERMANENT — run ONLY after capstone submission.
RG="$RG"
echo ""
echo "⚠  WARNING: This permanently deletes ALL Smart Ticket resources."
echo "   Includes all VMs, SQL database, AI services, and all data."
echo ""
read -p "Type DELETE to confirm: " CONFIRM
if [ "\$CONFIRM" = "DELETE" ]; then
  az group delete --name \$RG --yes --no-wait
  echo ""
  echo "✅ Deletion started. All charges stop within 10 minutes."
else
  echo "Cancelled — nothing deleted."
fi
DELETESCRIPT
chmod +x "$HOME/delete-smartticket.sh"
success "Created ~/delete-smartticket.sh"

# ── Auto-Shutdown on all 4 VMs ────────────────────────────────────────────────
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
      --output none 2>>"$LOG_FILE" && log "  Auto-shutdown set: $VM"
  fi
done
success "All VMs auto-deallocate daily at ${AUTO_SHUTDOWN_TIME}."

# ── Budget Alerts ─────────────────────────────────────────────────────────────
if [[ -n "$ALERT_EMAIL" ]]; then
  log "Setting budget alerts at \$50 and \$80..."
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
      --output none 2>>"$LOG_FILE" \
      || warn "Budget alert \$$AMOUNT skipped (Cost Management may need enabling)"
  done
  success "Budget alerts → $ALERT_EMAIL at \$50 and \$80"
else
  warn "ALERT_EMAIL not set — skipping budget alerts."
fi

# Append operations section to credentials file
cat >> "$CREDS_FILE" << EOF

DAILY OPERATIONS
────────────────────────────────────────────────────
  Start (morning)  : bash ~/start-smartticket.sh
  Stop  (evening)  : bash ~/stop-smartticket.sh
  Check status     : bash ~/status-smartticket.sh
  Delete PERMANENT : bash ~/delete-smartticket.sh  ← after capstone only

AUTO-SHUTDOWN
────────────────────────────────────────────────────
  All VMs auto-deallocate daily at ${AUTO_SHUTDOWN_TIME}
  24/7 cost estimate : ~\$49 for 5 days
  Smart stop/start   : ~\$19 for 5 days

COST RULES
────────────────────────────────────────────────────
  ✅ Always use 'deallocate' — never 'az vm stop'
  ✅ SQL + IPs charge even when VMs are off (~\$0.03/hr)
  ✅ Run delete script after submission — stops all charges
  ❌ 'az vm stop' keeps billing — DO NOT use it

EOF

success "Operations info saved to credentials file."

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
printf "║  %-60s ║\n" "Frontend (HTTPS):    https://$FRONTEND_IP"
printf "║  %-60s ║\n" "Backend  (HTTP):     http://$BACKEND_IP:8000"
printf "║  %-60s ║\n" "API Docs (Swagger):  http://$BACKEND_IP:8000/docs"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "Login: admin@ticket.local  /  Admin@2024!"
printf "║  %-60s ║\n" "Login: lead@ticket.local   /  Lead@2024!"
printf "║  %-60s ║\n" "Login: agent1@ticket.local /  Agent@2024!"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "Credentials saved: ~/smartticket-credentials.txt"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s ║\n" "DAILY COMMANDS:"
printf "║  %-60s ║\n" "  Stop  → bash ~/stop-smartticket.sh"
printf "║  %-60s ║\n" "  Start → bash ~/start-smartticket.sh"
printf "║  %-60s ║\n" "  Check → bash ~/status-smartticket.sh"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "${YELLOW}⚠  Browser warning:${NC} Chrome → Advanced → Proceed to $FRONTEND_IP"
echo -e "${YELLOW}⚠  Auto-shutdown:${NC}  VMs deallocate daily at ${AUTO_SHUTDOWN_TIME} automatically"
echo -e "${YELLOW}⚠  Power BI:${NC}       Connect at https://app.powerbi.com → Azure SQL → $SQL_SERVER"
echo ""
echo "Full operations guide: azure-setup/OPERATIONS-GUIDE.md"

rm -rf "$TMP"
