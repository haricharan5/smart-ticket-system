# Azure Setup Guide — Smart Support Ticket System

## Two Ways to Deploy

| Method | Time | Effort |
|--------|------|--------|
| **One-command script** (recommended) | ~35 min | Run 4 commands |
| **Manual step-by-step** | ~60 min | Follow each section |

---

## METHOD 1: One-Command Script (Recommended)

### Before You Run

You need **3 things** ready:

**1. Push your code to GitHub (public repo)**
```bash
# On your local machine (not Cloud Shell)
cd "D:/NLP project"
git init
git add .
git commit -m "feat: initial project"
git remote add origin https://github.com/YOUR_USERNAME/smart-ticket-system.git
git push -u origin main
```

**2. Open Azure Cloud Shell**
- Go to https://portal.azure.com
- Click the `>_` icon in the top bar (Cloud Shell)
- Choose **Bash**

**3. Upload the setup script to Cloud Shell**

Option A — Upload file:
- Click the **Upload** button in Cloud Shell toolbar
- Upload `azure-setup/master-setup.sh`

Option B — Copy-paste via GitHub raw URL:
```bash
curl -sSL https://raw.githubusercontent.com/YOUR_USERNAME/smart-ticket-system/main/azure-setup/master-setup.sh \
  -o master-setup.sh
```

---

### Run the Script (4 commands total)

```bash
# 1. Login to Azure (skip if already logged in)
az login

# 2. Set your subscription (if you have multiple)
az account set --subscription "YOUR_SUBSCRIPTION_NAME"

# 3. Set your GitHub repo URL
export GITHUB_REPO=https://github.com/YOUR_USERNAME/smart-ticket-system.git

# 4. Run the master setup script
bash master-setup.sh
```

**That's it.** Go get coffee. Come back in 35 minutes. ☕

The script will print a live progress log. When it finishes, it outputs:
```
╔══════════════════════════════════════════════════════════════╗
║           🎉  DEPLOYMENT COMPLETE!                           ║
╠══════════════════════════════════════════════════════════════╣
║  Frontend (HTTPS):   https://YOUR_IP                         ║
║  Backend API:        http://YOUR_IP:8000                     ║
╚══════════════════════════════════════════════════════════════╝
```

All credentials are saved to `~/smartticket-credentials.txt` in Cloud Shell.

---

## METHOD 2: Manual Step-by-Step

Follow this if you want full control or if the script fails at a specific phase.

---

### STEP 1 — Open Azure Cloud Shell

1. Go to **https://portal.azure.com**
2. Click the **`>_`** terminal icon in the top navigation bar
3. Select **Bash** when prompted
4. First time: choose **Create storage** (free, needed for persistence)

You now have a Linux terminal connected to your Azure account.

---

### STEP 2 — Push Code to GitHub

```bash
# Do this on your LOCAL machine, not Cloud Shell
cd "D:/NLP project"
git init
git add .
git commit -m "feat: initial smart ticket system"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/smart-ticket-system.git
git push -u origin main
```

---

### STEP 3 — Resource Group + Network

```bash
RG="smart-ticket-rg"
LOCATION="eastus"
PREFIX="smartticket"

az group create --name $RG --location $LOCATION

az network vnet create \
  --resource-group $RG --name "${PREFIX}-vnet" \
  --address-prefix 10.0.0.0/16 \
  --subnet-name default --subnet-prefix 10.0.0.0/24

az network nsg create --resource-group $RG --name "${PREFIX}-nsg"

az network nsg rule create --resource-group $RG --nsg-name "${PREFIX}-nsg" \
  --name AllowAll --priority 100 --protocol Tcp \
  --destination-port-ranges 80 443 22 3389 8000 8443 \
  --access Allow --direction Inbound
```

---

### STEP 4 — Create 4 Virtual Machines

```bash
VM_USER="azureuser"
VM_PASS="Ticket@2024Secure!"

# VM1: Backend (Linux)
az vm create --resource-group $RG --name "${PREFIX}-vm1-backend" \
  --image Ubuntu2204 --size Standard_B2s \
  --admin-username $VM_USER --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard

# VM2: NLP Worker (Linux)
az vm create --resource-group $RG --name "${PREFIX}-vm2-nlp" \
  --image Ubuntu2204 --size Standard_B2s \
  --admin-username $VM_USER --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard

# VM3: Frontend (Linux)
az vm create --resource-group $RG --name "${PREFIX}-vm3-frontend" \
  --image Ubuntu2204 --size Standard_B2s \
  --admin-username $VM_USER --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard

# VM4: Active Directory (Windows)
az vm create --resource-group $RG --name "${PREFIX}-vm4-ad" \
  --image Win2022Datacenter --size Standard_B2ms \
  --admin-username $VM_USER --admin-password "$VM_PASS" \
  --nsg "${PREFIX}-nsg" --vnet-name "${PREFIX}-vnet" --subnet default \
  --public-ip-sku Standard
```

---

### STEP 5 — Azure SQL Database

```bash
SQL_ADMIN="sqladmin"
SQL_PASS="Ticket@2024Secure!"

az sql server create \
  --resource-group $RG --name "${PREFIX}-sql" --location $LOCATION \
  --admin-user $SQL_ADMIN --admin-password "$SQL_PASS"

az sql server firewall-rule create \
  --resource-group $RG --server "${PREFIX}-sql" \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0

az sql db create \
  --resource-group $RG --server "${PREFIX}-sql" \
  --name ticketdb --edition Basic --capacity 5
```

---

### STEP 6 — Azure AI Services

```bash
# Language Service (used for sentiment analysis → urgency mapping)
az cognitiveservices account create \
  --resource-group $RG --name "${PREFIX}-language" \
  --kind TextAnalytics --sku S --location $LOCATION --yes
```

> **No Azure OpenAI needed.** Classification and draft reply generation use
> a self-hosted Phi-3 Mini model on VM2 (see Step 6b). This eliminates
> external API costs and any per-token charges.

### STEP 6b — Install Ollama + Phi-3 Mini on VM2

SSH into VM2, or use `az vm run-command invoke`:

```bash
az vm run-command invoke --resource-group $RG \
  --name "${PREFIX}-vm2-nlp" \
  --command-id RunShellScript \
  --scripts "
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Configure to listen on all interfaces (so VM1 backend can reach it)
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment=\"OLLAMA_HOST=0.0.0.0:11434\"
Environment=\"OLLAMA_MODELS=/opt/ollama/models\"
EOF

systemctl daemon-reload
systemctl enable ollama
systemctl restart ollama
sleep 5

# Pull the model (~2.3 GB)
ollama pull phi3:mini
ollama list
"
```

Get VM2's **private** IP (stays within the VNet — no public traffic):

```bash
NLP_PRIVATE_IP=$(az vm show -d --resource-group $RG \
  --name "${PREFIX}-vm2-nlp" --query privateIps -o tsv)
echo "VM2 private IP: $NLP_PRIVATE_IP"
```

---

### STEP 7 — Application Insights

```bash
az monitor log-analytics workspace create \
  --resource-group $RG --workspace-name "${PREFIX}-logs" --location $LOCATION

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RG --workspace-name "${PREFIX}-logs" \
  --query customerId -o tsv)

az monitor app-insights component create \
  --resource-group $RG --app "${PREFIX}-appinsights" \
  --location $LOCATION --kind web --workspace "$WORKSPACE_ID"
```

---

### STEP 8 — Get All Keys and IPs

```bash
# Language Service keys
LANG_KEY=$(az cognitiveservices account keys list --resource-group $RG --name "${PREFIX}-language" --query key1 -o tsv)
LANG_EP=$(az cognitiveservices account show --resource-group $RG --name "${PREFIX}-language" --query properties.endpoint -o tsv)

# Application Insights connection string
AI_CONN=$(az monitor app-insights component show --resource-group $RG --app "${PREFIX}-appinsights" --query connectionString -o tsv)

# Public IPs (for browser access)
BACKEND_IP=$(az vm show -d --resource-group $RG --name "${PREFIX}-vm1-backend" --query publicIps -o tsv)
FRONTEND_IP=$(az vm show -d --resource-group $RG --name "${PREFIX}-vm3-frontend" --query publicIps -o tsv)

# VM2 private IP (for backend → Ollama communication within the VNet)
NLP_PRIVATE_IP=$(az vm show -d --resource-group $RG --name "${PREFIX}-vm2-nlp" --query privateIps -o tsv)

# Generate JWT secret
JWT_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")

echo "Backend IP:       $BACKEND_IP"
echo "Frontend IP:      $FRONTEND_IP"
echo "VM2 (Ollama):     $NLP_PRIVATE_IP  (private — no public exposure needed)"
```

---

### STEP 9 — Install Docker on VMs (via run-command)

```bash
DOCKER_SCRIPT='#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq curl gnupg2 git
curl -fsSL https://get.docker.com | sh
systemctl enable docker && systemctl start docker
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /usr/share/keyrings/microsoft.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/22.04/prod jammy main" > /etc/apt/sources.list.d/mssql-release.list
apt-get update -qq && ACCEPT_EULA=Y apt-get install -y -qq msodbcsql18
echo "Done: $(docker --version)"'

# Run on all 3 Linux VMs
for vm in vm1-backend vm2-nlp vm3-frontend; do
  echo "Installing Docker on $vm..."
  az vm run-command invoke --resource-group $RG --name "${PREFIX}-${vm}" \
    --command-id RunShellScript --scripts "$DOCKER_SCRIPT"
done
```

---

### STEP 10 — Deploy Backend

```bash
cat > /tmp/deploy-backend.sh << SCRIPT
#!/bin/bash
set -e
git clone "$GITHUB_REPO" /opt/smartticket 2>/dev/null || git -C /opt/smartticket pull
{
  echo "AZURE_SQL_SERVER=${PREFIX}-sql.database.windows.net"
  echo "AZURE_SQL_DATABASE=ticketdb"
  echo "AZURE_SQL_USERNAME=$SQL_ADMIN"
  echo "AZURE_SQL_PASSWORD=$SQL_PASS"
  echo "SQL_ENCRYPT=yes"
  echo "SQL_TRUST_CERT=no"
  echo "AZURE_LANGUAGE_ENDPOINT=$LANG_EP"
  echo "AZURE_LANGUAGE_KEY=$LANG_KEY"
  echo "LLM_BASE_URL=http://$NLP_PRIVATE_IP:11434/v1"
  echo "LLM_MODEL=phi3:mini"
  echo "JWT_SECRET_KEY=$JWT_SECRET"
  echo "FRONTEND_URL=https://$FRONTEND_IP"
  echo "LOG_LEVEL=INFO"
  echo "APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN"
} > /opt/smartticket/backend/.env
cd /opt/smartticket && docker build -t smart-ticket-backend ./backend
docker stop smart-ticket-backend 2>/dev/null || true
docker rm smart-ticket-backend 2>/dev/null || true
docker run -d --name smart-ticket-backend --restart unless-stopped \
  -p 8000:8000 --env-file /opt/smartticket/backend/.env smart-ticket-backend
sleep 8 && curl -s http://localhost:8000/health
SCRIPT

az vm run-command invoke --resource-group $RG \
  --name "${PREFIX}-vm1-backend" \
  --command-id RunShellScript \
  --scripts @/tmp/deploy-backend.sh
```

---

### STEP 11 — SSL + Frontend Deployment

```bash
cat > /tmp/deploy-frontend.sh << SCRIPT
#!/bin/bash
set -e
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
git clone "$GITHUB_REPO" /opt/smartticket 2>/dev/null || git -C /opt/smartticket pull
mkdir -p /etc/ssl/smartticket /opt/smartticket/certs
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/smartticket/smartticket.key \
  -out /etc/ssl/smartticket/smartticket.crt \
  -subj "/C=US/ST=Demo/L=Demo/O=SmartTicket/CN=$FRONTEND_IP" \
  -addext "subjectAltName=IP:$FRONTEND_IP" 2>/dev/null
cp /etc/ssl/smartticket/* /opt/smartticket/certs/
cd /opt/smartticket
docker build \
  --build-arg VITE_API_URL="http://$BACKEND_IP:8000" \
  --build-arg VITE_POWERBI_URL="" \
  --build-arg SSL_CERT_PATH="./certs" \
  -t smart-ticket-frontend ./frontend
docker stop smart-ticket-frontend 2>/dev/null || true
docker rm smart-ticket-frontend 2>/dev/null || true
docker run -d --name smart-ticket-frontend --restart unless-stopped \
  -p 80:80 -p 443:443 smart-ticket-frontend
echo "Frontend live"
SCRIPT

az vm run-command invoke --resource-group $RG \
  --name "${PREFIX}-vm3-frontend" \
  --command-id RunShellScript \
  --scripts @/tmp/deploy-frontend.sh
```

---

### STEP 12 — Seed Demo Data

```bash
az vm run-command invoke --resource-group $RG \
  --name "${PREFIX}-vm1-backend" \
  --command-id RunShellScript \
  --scripts "
pip3 install httpx --quiet
cd /opt/smartticket/data
python3 generate_dataset.py
python3 seed.py --url http://localhost:8000 --count 50
"
```

---

### STEP 13 — Active Directory (Windows VM4)

1. RDP into VM4: `mstsc /v:$AD_IP`
2. User: `azureuser` | Password: `Ticket@2024Secure!`
3. Open **PowerShell as Administrator**
4. Run contents of `infrastructure/vm-setup-windows.ps1`
5. VM will reboot — reconnect and run the second half of the script

---

### STEP 14 — Power BI Setup

1. Go to **https://app.powerbi.com**
2. Click **Get data → Azure SQL Database**
3. Server: `smartticket-sql.database.windows.net` | Database: `ticketdb`
4. Mode: **Import**
5. Login with SQL credentials: `sqladmin / Ticket@2024Secure!`
6. Build these visuals:
   - Pie chart: `tickets[category]` by count
   - Bar chart: `tickets[created_at]` (day) by count
   - Card: Total tickets, open count, resolved count
7. **File → Publish to web** → Copy embed URL
8. SSH to VM3:
   ```bash
   ssh azureuser@YOUR_VM3_IP
   docker exec smart-ticket-frontend sh -c \
     "sed -i 's|VITE_POWERBI_URL=.*|VITE_POWERBI_URL=YOUR_EMBED_URL|' /app/.env"
   ```
   Or rebuild with the URL set:
   ```bash
   # On VM3
   cd /opt/smartticket
   docker stop smart-ticket-frontend && docker rm smart-ticket-frontend
   docker build --build-arg VITE_API_URL="http://BACKEND_IP:8000" \
     --build-arg VITE_POWERBI_URL="YOUR_EMBED_URL" \
     --build-arg SSL_CERT_PATH="./certs" \
     -t smart-ticket-frontend ./frontend
   docker run -d --name smart-ticket-frontend --restart unless-stopped \
     -p 80:80 -p 443:443 smart-ticket-frontend
   ```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Backend health check fails | `az vm run-command invoke ... --scripts "docker logs smart-ticket-backend --tail 30"` |
| Missing env var error | Check `.env` was written correctly: `docker exec smart-ticket-backend cat /proc/1/environ` |
| Browser HTTPS warning | Chrome: Advanced → Proceed. Or import the `.crt` as trusted cert |
| VM run-command timeout | Rerun — it's idempotent (docker stop/rm before run) |
| Seed fails 401 Unauthorized | Backend JWT not configured — check `JWT_SECRET_KEY` in .env |
| SQL connection refused | Check firewall rule: `az sql server firewall-rule list --resource-group $RG --server ${PREFIX}-sql` |
| LLM returns fallback category | Ollama unreachable — SSH to VM2: `curl http://localhost:11434/api/tags` to check status |
| Ollama not running on VM2 | SSH to VM2: `sudo systemctl status ollama` → `sudo systemctl restart ollama` |
| Model not downloaded | SSH to VM2: `ollama list` — if empty, run `ollama pull phi3:mini` again |
| Slow LLM response (>10s) | Normal on first request (model loads). Subsequent calls are faster. Or upgrade VM2 to B4ms |

## Cost Management

```bash
# Stop all VMs when not presenting (saves ~60% cost)
az vm deallocate --resource-group smart-ticket-rg --name smartticket-vm1-backend
az vm deallocate --resource-group smart-ticket-rg --name smartticket-vm2-nlp
az vm deallocate --resource-group smart-ticket-rg --name smartticket-vm3-frontend
az vm deallocate --resource-group smart-ticket-rg --name smartticket-vm4-ad

# Start them again before demo
az vm start --resource-group smart-ticket-rg --name smartticket-vm1-backend
az vm start --resource-group smart-ticket-rg --name smartticket-vm2-nlp
az vm start --resource-group smart-ticket-rg --name smartticket-vm3-frontend
az vm start --resource-group smart-ticket-rg --name smartticket-vm4-ad
```

## Delete Everything (after capstone)

```bash
az group delete --name smart-ticket-rg --yes --no-wait
```
