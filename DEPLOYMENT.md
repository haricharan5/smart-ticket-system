# Smart Support Ticket System — Complete Deployment Guide

## Day-by-Day Execution Plan

---

## DAY 1 — Azure Infrastructure

### Step 1: Login to Azure
```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### Step 2: Provision all Azure resources (one command)
```bash
bash infrastructure/provision.sh
```
This creates: 4 VMs, VNet, NSG, Azure SQL, Azure Language Service, Azure OpenAI.
**Save all keys/endpoints printed at the end.**

### Step 3: Setup Linux VMs (run on each of VM1, VM2, VM3)
```bash
ssh azureuser@<VM_PUBLIC_IP>
curl -sSL https://raw.githubusercontent.com/... | bash
# Or copy and run infrastructure/vm-setup-linux.sh manually
```

### Step 4: Setup Windows VM4 (Active Directory)
- RDP into VM4
- Open PowerShell as Administrator
- Run `infrastructure/vm-setup-windows.ps1`
- Server will reboot; after reboot, run the second section of the script

---

## DAY 2 — Backend + NLP Pipeline

### Step 1: Configure backend environment
```bash
# On VM1
cp backend/.env.example backend/.env
nano backend/.env   # Fill in all values from provision.sh output
```

### Step 2: Apply database schema
```bash
# Using Azure CLI or Azure Data Studio
az sql db import --resource-group smart-ticket-rg \
  --server smartticket-sql \
  --name ticketdb \
  --admin-user sqladmin \
  --admin-password "Ticket@2024Secure!" \
  --storage-uri ... # Or use Azure Data Studio to run infrastructure/schema.sql
```

### Step 3: Deploy backend
```bash
# On VM1
git clone https://github.com/YOUR_USERNAME/smart-ticket-system.git
cd smart-ticket-system
bash deploy/deploy.sh backend
```

### Step 4: Verify API
```
curl http://YOUR_VM1_IP:8000/health
# → {"status": "ok"}

# Interactive docs:
http://YOUR_VM1_IP:8000/docs
```

### Step 5: Test NLP classification
```bash
curl -X POST http://YOUR_VM1_IP:8000/api/tickets \
  -H "Content-Type: application/json" \
  -d '{"title":"Cannot login","description":"Getting 500 error on login page","submitter_email":"test@test.com"}'
```
Expected: ticket returned with category, sentiment, urgency, draft_reply populated.

---

## DAY 3 — Frontend Dashboard

### Step 1: Deploy frontend to VM3
```bash
# On VM3
git clone https://github.com/YOUR_USERNAME/smart-ticket-system.git
cd smart-ticket-system
BACKEND_VM_IP=YOUR_VM1_IP bash deploy/deploy.sh frontend
```

### Step 2: Verify
```
http://YOUR_VM3_IP      → Dashboard
http://YOUR_VM3_IP/submit → Ticket form
```

---

## DAY 4 — Analytics + Power BI

### Step 1: Seed demo data
```bash
cd smart-ticket-system/data
python3 generate_dataset.py
python3 seed.py --url http://YOUR_VM1_IP:8000 --count 50
```

### Step 2: Setup Power BI
1. Go to https://app.powerbi.com
2. Connect to Azure SQL: `smartticket-sql.database.windows.net / ticketdb`
3. Import tables: tickets, teams
4. Build report: category pie chart, daily bar chart, resolution time
5. Publish → Get embed link (Publish to Web)
6. Add URL to `frontend/.env` as `VITE_POWERBI_URL=<embed_url>`
7. Rebuild frontend: `bash deploy/deploy.sh frontend`

---

## DAY 5 — Integration Test + Demo Prep

### Demo script (run in order for judges)
```
1. Open dashboard → show empty or pre-seeded queue
2. Go to Submit Ticket → enter: "VPN keeps disconnecting every 10 minutes during calls"
3. Watch it appear on dashboard: classified as "Technical Issue", sentiment, SLA timer
4. Click ticket → show AI draft reply from Azure OpenAI
5. Submit 3 more technical tickets → outage banner fires automatically
6. Open Analytics → show charts + Power BI report
7. Update one ticket to "resolved" → show SLA resolved
```

---

## Environment Variables Reference

### backend/.env
| Variable | Where to get |
|----------|-------------|
| AZURE_SQL_SERVER | provision.sh output |
| AZURE_SQL_DATABASE | ticketdb |
| AZURE_SQL_USERNAME | sqladmin |
| AZURE_SQL_PASSWORD | Ticket@2024Secure! |
| AZURE_LANGUAGE_ENDPOINT | provision.sh output |
| AZURE_LANGUAGE_KEY | provision.sh output |
| LLM_BASE_URL | http://VM2_PRIVATE_IP:11434/v1 |
| LLM_MODEL | phi3:mini |
| FRONTEND_URL | http://YOUR_VM3_IP |

### frontend/.env
| Variable | Value |
|----------|-------|
| VITE_API_URL | http://YOUR_VM1_IP:8000 |
| VITE_POWERBI_URL | Power BI embed URL |

---

## Architecture Summary

```
Internet
   │
   ├─ VM3 (Linux) ── nginx ── React Frontend (port 80)
   │                              │ polls every 3s
   │                              ▼
   ├─ VM1 (Linux) ── Docker ── FastAPI Backend (port 8000)
   │                              │
   │                    ┌─────────┼─────────────┐
   │                    ▼         ▼              ▼
   │             Azure SQL   Azure Language   Azure OpenAI
   │            (tickets)    (sentiment)     (classify+draft)
   │
   ├─ VM2 (Linux) ── Reserved for monitoring / scaling
   └─ VM4 (Windows) ── Active Directory (ticket.local domain)
```

## Budget Estimate ($100 limit)

| Resource | Est. Cost/day | 5 days |
|----------|--------------|--------|
| 3× B2s Linux VMs | $0.10/hr × 3 = $0.30/hr | ~$36 |
| 1× B2ms Windows VM | $0.18/hr | ~$22 |
| Azure SQL Basic | $0.17/day | ~$1 |
| Azure Language S tier | Pay-per-use | ~$2 |
| Azure OpenAI GPT-4o-mini | ~$0.15/1M tokens | ~$5 |
| **Total** | | **~$66** |

**Tip**: Stop VMs when not working to save ~60% of VM cost.
```bash
az vm deallocate --resource-group smart-ticket-rg --name smartticket-vm1-backend
```
