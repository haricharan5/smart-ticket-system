#!/bin/bash
# Azure Resource Provisioning Script
# Run once from Azure Cloud Shell or local CLI with: bash provision.sh
# Prerequisites: az login completed, subscription set

set -e

# ── CONFIG — edit these before running ──────────────────────────────────────
RG="smart-ticket-rg"
LOCATION="eastus"
PREFIX="smartticket"
SQL_ADMIN="sqladmin"
SQL_PASSWORD="Ticket@2024Secure!"
LLM_MODEL="phi3:mini"   # Ollama model tag — installed on VM2
# ─────────────────────────────────────────────────────────────────────────────

echo "▶ Creating resource group..."
az group create --name $RG --location $LOCATION

# ── Virtual Network ──────────────────────────────────────────────────────────
echo "▶ Creating VNet..."
az network vnet create \
  --resource-group $RG \
  --name "${PREFIX}-vnet" \
  --address-prefix 10.0.0.0/16 \
  --subnet-name default \
  --subnet-prefix 10.0.0.0/24

# ── Network Security Group ───────────────────────────────────────────────────
echo "▶ Creating NSG..."
az network nsg create --resource-group $RG --name "${PREFIX}-nsg"
az network nsg rule create --resource-group $RG --nsg-name "${PREFIX}-nsg" \
  --name AllowHTTP --priority 100 --protocol Tcp --destination-port-ranges 80 8000 5173 --access Allow --direction Inbound
az network nsg rule create --resource-group $RG --nsg-name "${PREFIX}-nsg" \
  --name AllowSSH --priority 110 --protocol Tcp --destination-port-ranges 22 3389 --access Allow --direction Inbound

# ── VM 1: Backend API (Linux) ────────────────────────────────────────────────
echo "▶ Creating VM1 (Backend - Linux)..."
az vm create \
  --resource-group $RG \
  --name "${PREFIX}-vm1-backend" \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" \
  --vnet-name "${PREFIX}-vnet" \
  --subnet default \
  --public-ip-sku Standard

# ── VM 2: NLP Worker — Ollama host (Linux) ───────────────────────────────────
echo "▶ Creating VM2 (NLP/Ollama Worker - Linux)..."
az vm create \
  --resource-group $RG \
  --name "${PREFIX}-vm2-nlp" \
  --image Ubuntu2204 \
  --size Standard_B2ms \
  --admin-username azureuser \
  --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" \
  --vnet-name "${PREFIX}-vnet" \
  --subnet default \
  --public-ip-sku Standard

# ── VM 3: Frontend (Linux) ───────────────────────────────────────────────────
echo "▶ Creating VM3 (Frontend - Linux)..."
az vm create \
  --resource-group $RG \
  --name "${PREFIX}-vm3-frontend" \
  --image Ubuntu2204 \
  --size Standard_B2s \
  --admin-username azureuser \
  --generate-ssh-keys \
  --nsg "${PREFIX}-nsg" \
  --vnet-name "${PREFIX}-vnet" \
  --subnet default \
  --public-ip-sku Standard

# ── VM 4: Active Directory (Windows) ────────────────────────────────────────
echo "▶ Creating VM4 (Active Directory - Windows)..."
az vm create \
  --resource-group $RG \
  --name "${PREFIX}-vm4-ad" \
  --image Win2022Datacenter \
  --size Standard_B2ms \
  --admin-username azureuser \
  --admin-password "${SQL_PASSWORD}" \
  --nsg "${PREFIX}-nsg" \
  --vnet-name "${PREFIX}-vnet" \
  --subnet default \
  --public-ip-sku Standard

# ── Azure SQL ────────────────────────────────────────────────────────────────
echo "▶ Creating Azure SQL Server + Database..."
az sql server create \
  --resource-group $RG \
  --name "${PREFIX}-sql" \
  --location $LOCATION \
  --admin-user $SQL_ADMIN \
  --admin-password "$SQL_PASSWORD"

az sql server firewall-rule create \
  --resource-group $RG \
  --server "${PREFIX}-sql" \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

az sql db create \
  --resource-group $RG \
  --server "${PREFIX}-sql" \
  --name ticketdb \
  --edition Basic \
  --capacity 5

# ── Azure Language Service ───────────────────────────────────────────────────
echo "▶ Creating Azure Language Service..."
az cognitiveservices account create \
  --resource-group $RG \
  --name "${PREFIX}-language" \
  --kind TextAnalytics \
  --sku S \
  --location $LOCATION \
  --yes

# ── Azure Application Insights (Monitoring) ──────────────────────────────────
echo "▶ Creating Log Analytics Workspace + Application Insights..."
az monitor log-analytics workspace create \
  --resource-group $RG \
  --workspace-name "${PREFIX}-logs" \
  --location $LOCATION

WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group $RG \
  --workspace-name "${PREFIX}-logs" \
  --query customerId -o tsv)

az monitor app-insights component create \
  --resource-group $RG \
  --app "${PREFIX}-appinsights" \
  --location $LOCATION \
  --kind web \
  --workspace "$WORKSPACE_ID"

# ── Open port 8443 for HTTPS backend (optional) ───────────────────────────────
az network nsg rule create --resource-group $RG --nsg-name "${PREFIX}-nsg" \
  --name AllowHTTPS --priority 120 --protocol Tcp \
  --destination-port-ranges 443 8443 --access Allow --direction Inbound

# ── Print outputs ────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "✅ PROVISIONING COMPLETE"
echo "════════════════════════════════════════"
echo ""
echo "SQL Server:      ${PREFIX}-sql.database.windows.net"
echo "SQL Database:    ticketdb"
echo "SQL User:        $SQL_ADMIN"
echo "SQL Password:    $SQL_PASSWORD"
echo ""
LANG_KEY=$(az cognitiveservices account keys list --resource-group $RG --name "${PREFIX}-language" --query key1 -o tsv)
LANG_EP=$(az cognitiveservices account show --resource-group $RG --name "${PREFIX}-language" --query properties.endpoint -o tsv)
NLP_PRIVATE_IP=$(az vm show -d --resource-group $RG --name "${PREFIX}-vm2-nlp" --query privateIps -o tsv)
AI_CONN=$(az monitor app-insights component show \
  --resource-group $RG \
  --app "${PREFIX}-appinsights" \
  --query connectionString -o tsv)
echo "Language Key:    $LANG_KEY"
echo "Language EP:     $LANG_EP"
echo "VM2 Private IP:  $NLP_PRIVATE_IP  (Ollama endpoint)"
echo "App Insights:    $AI_CONN"
echo ""
echo "▶ Next steps:"
echo "  1. Install Ollama on VM2: curl -fsSL https://ollama.ai/install.sh | sh"
echo "     Then: OLLAMA_HOST=0.0.0.0 ollama pull $LLM_MODEL"
echo "  2. Set LLM_BASE_URL=http://$NLP_PRIVATE_IP:11434/v1 in backend/.env"
echo "  3. Run vm-setup-linux.sh on VM1 and VM3"
echo "  4. Generate JWT secret: python3 -c \"import secrets; print(secrets.token_hex(32))\""
echo "  5. Run ssl-setup.sh on VM3 before deploying frontend"
