# Smart Support Ticket System — Cloud Operations Guide

Everything you need to operate, maintain, and shut down your Azure deployment.
Open this guide every time you sit down to work on the project.

---

## Your 4 Daily Commands (memorise these)

| What | Command | When |
|------|---------|------|
| **Start everything** | `bash ~/start-smartticket.sh` | Morning / before demo |
| **Stop everything** | `bash ~/stop-smartticket.sh` | Evening / done working |
| **Check status** | `bash ~/status-smartticket.sh` | Any time you're unsure |
| **Delete forever** | `bash ~/delete-smartticket.sh` | After capstone only |

> These scripts were created in your Cloud Shell home (`~/`) automatically by `master-setup.sh`.

---

## Day-to-Day Workflow

### Step 1 — Open Azure Cloud Shell
1. Go to **https://portal.azure.com**
2. Click the `>_` terminal icon in the top bar
3. Select **Bash**

### Step 2 — Start Your VMs (takes ~3 minutes)
```bash
bash ~/start-smartticket.sh
```

Wait 3–4 minutes, then open your app:
- **Frontend:** `https://YOUR_FRONTEND_IP` (check `~/smartticket-credentials.txt`)
- **API Docs:** `http://YOUR_BACKEND_IP:8000/docs`

> **First request after restart is slow (~30 seconds)** — this is Ollama loading the
> Phi-3 Mini model into memory. Every subsequent classification is instant.

### Step 3 — Work / Demo

Log in with:
| Role | Email | Password |
|------|-------|----------|
| Admin | `admin@ticket.local` | `Admin@2024!` |
| Team Lead | `lead@ticket.local` | `Lead@2024!` |
| Agent | `agent1@ticket.local` | `Agent@2024!` |

### Step 4 — Stop When Done (saves ~60% cost)
```bash
bash ~/stop-smartticket.sh
```

---

## Checking What's Running

```bash
# Full status — VM states + health checks
bash ~/status-smartticket.sh

# Just VM states (fast)
az vm list --resource-group smart-ticket-rg --show-details \
  --query "[].{Name:name, State:powerState}" --output table

# Check backend is responding
curl -s http://YOUR_BACKEND_IP:8000/health

# Check Ollama LLM is running on VM2
ssh azureuser@YOUR_BACKEND_IP \
  "curl -s http://OLLAMA_PRIVATE_IP:11434/api/tags | python3 -m json.tool"
```

---

## Viewing Logs

### Backend Application Logs (VM1)
```bash
# Connect to VM1
ssh azureuser@YOUR_BACKEND_IP

# Tail live logs
docker logs smart-ticket-backend -f

# Last 50 lines
docker logs smart-ticket-backend --tail 50

# Filter for errors only
docker logs smart-ticket-backend 2>&1 | grep -i error
```

### Frontend Logs (VM3)
```bash
ssh azureuser@YOUR_FRONTEND_IP
docker logs smart-ticket-frontend --tail 30
```

### Ollama LLM Logs (VM2)
```bash
ssh azureuser@YOUR_NLP_IP
sudo journalctl -u ollama -f          # live Ollama service logs
ollama list                            # show loaded models
ollama ps                              # show models currently in memory
```

### View from Cloud Shell without SSH (via az run-command)
```bash
# Backend logs — no SSH needed
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm1-backend \
  --command-id RunShellScript \
  --scripts "docker logs smart-ticket-backend --tail 30"

# Ollama status
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm2-nlp \
  --command-id RunShellScript \
  --scripts "systemctl status ollama && ollama list"
```

---

## Restarting Services (Without Rebuilding)

```bash
# Restart backend container (applies if .env was changed on VM1)
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm1-backend \
  --command-id RunShellScript \
  --scripts "docker restart smart-ticket-backend"

# Restart frontend container (on VM3)
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm3-frontend \
  --command-id RunShellScript \
  --scripts "docker restart smart-ticket-frontend"

# Restart Ollama (on VM2)
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm2-nlp \
  --command-id RunShellScript \
  --scripts "sudo systemctl restart ollama"
```

---

## Updating the Application (After Code Changes)

After you push changes to GitHub:

```bash
# Redeploy backend only
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm1-backend \
  --command-id RunShellScript \
  --scripts "
    cd /opt/smartticket
    git pull
    docker stop smart-ticket-backend
    docker rm smart-ticket-backend
    docker build -t smart-ticket-backend ./backend
    docker run -d --name smart-ticket-backend --restart unless-stopped \
      -p 8000:8000 --env-file /opt/smartticket/backend/.env smart-ticket-backend
    sleep 5 && curl -s http://localhost:8000/health
  "

# Redeploy frontend only (on VM3)
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm3-frontend \
  --command-id RunShellScript \
  --scripts "
    cd /opt/smartticket
    git pull
    docker stop smart-ticket-frontend
    docker rm smart-ticket-frontend
    docker build \
      --build-arg VITE_API_URL=http://YOUR_BACKEND_IP:8000 \
      --build-arg VITE_POWERBI_URL=YOUR_POWERBI_URL \
      --build-arg SSL_CERT_PATH=./certs \
      -t smart-ticket-frontend ./frontend
    docker run -d --name smart-ticket-frontend --restart unless-stopped \
      -p 80:80 -p 443:443 smart-ticket-frontend
  "
```

---

## Cost Control

### See Your Current Spending
```bash
# Current month costs by resource (may take 24h to reflect)
az consumption usage list \
  --query "sort_by([].{Resource:instanceName, Cost:pretaxCost}, &Cost)" \
  --output table
```

### Estimated Cost Per Day
| Scenario | Cost/day |
|----------|----------|
| All VMs running 24h | ~$9.80 |
| 8 hours/day + rest deallocated | ~$3.50 |
| All VMs deallocated (SQL + IP only) | ~$0.70 |

### Auto-Shutdown (already configured)
VMs are set to auto-deallocate every day at **23:00** — even if you forget to
run `stop-smartticket.sh`. You can verify it:

```bash
# Check auto-shutdown status on a VM
az vm show \
  --resource-group smart-ticket-rg \
  --name smartticket-vm1-backend \
  --query "osProfile" \
  --output json

# Or via Azure Portal:
# Virtual Machines → select VM → Operations → Auto-shutdown
```

Change the auto-shutdown time if needed:
```bash
for VM in smartticket-vm1-backend smartticket-vm2-nlp smartticket-vm3-frontend smartticket-vm4-ad; do
  az vm auto-shutdown \
    --resource-group smart-ticket-rg \
    --name $VM \
    --time 2000 \         # change to 8 PM
    --email you@email.com
done
```

---

## Power BI Setup (optional — adds analytics dashboard)

1. Go to **https://app.powerbi.com** → sign in with Microsoft/university account
2. **Get data → Azure SQL Database**
3. Server: `smartticket-sql.database.windows.net` | Database: `ticketdb`
4. Credentials: `sqladmin` / `Ticket@2024Secure!`
5. Build your visuals, then: **File → Publish to web → Create embed code**
6. Copy the URL from the iframe (`src="..."`)
7. Paste it into the frontend:

```bash
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm3-frontend \
  --command-id RunShellScript \
  --scripts "
    cd /opt/smartticket
    docker stop smart-ticket-frontend && docker rm smart-ticket-frontend
    docker build \
      --build-arg VITE_API_URL=http://YOUR_BACKEND_IP:8000 \
      --build-arg VITE_POWERBI_URL='YOUR_POWERBI_EMBED_URL_HERE' \
      --build-arg SSL_CERT_PATH=./certs \
      -t smart-ticket-frontend ./frontend
    docker run -d --name smart-ticket-frontend --restart unless-stopped \
      -p 80:80 -p 443:443 smart-ticket-frontend
  "
```

---

## RDP into the Windows AD Server (VM4)

From your local Windows machine:
```
mstsc /v:YOUR_AD_IP
```
- Username: `azureuser`
- Password: `Ticket@2024Secure!`

From Cloud Shell (get the IP):
```bash
az vm show -d --resource-group smart-ticket-rg \
  --name smartticket-vm4-ad --query publicIps -o tsv
```

---

## Common Problems & Fixes

| Problem | Symptom | Fix |
|---------|---------|-----|
| App not loading after VM start | Browser timeout | Wait 3–4 min, VMs need boot time |
| First classification is slow | 30s response | Normal — Ollama loading model into RAM |
| Backend 500 error | API crashes | `docker logs smart-ticket-backend --tail 30` on VM1 |
| Login fails | 401 Unauthorized | JWT_SECRET_KEY env var issue — check `.env` on VM1 |
| HTTPS certificate warning | Browser blocks page | Chrome → Advanced → Proceed (self-signed cert is safe) |
| Ollama not responding | Category always "Other" | SSH VM2 → `sudo systemctl restart ollama` |
| SQL connection error | Backend health fails | Check firewall: `az sql server firewall-rule list ...` |
| VM won't start | Quota or region issue | `az vm list -d -g smart-ticket-rg --query "[].powerState"` |

---

## SSH Quick Reference

```bash
# Get IPs any time
az vm list -d --resource-group smart-ticket-rg \
  --query "[].{Name:name, PublicIP:publicIps, PrivateIP:privateIps}" \
  --output table

# SSH into any Linux VM
ssh azureuser@VM_IP

# Run a command on a VM without SSH (from Cloud Shell)
az vm run-command invoke \
  --resource-group smart-ticket-rg \
  --name smartticket-vm1-backend \
  --command-id RunShellScript \
  --scripts "YOUR COMMAND HERE"
```

---

## After Capstone — Delete Everything

Run **only** after your submission is graded and you no longer need the project:

```bash
bash ~/delete-smartticket.sh
```

This asks you to type `DELETE` to confirm, then removes the entire resource group.
**All data, VMs, and AI services are permanently deleted. Charges stop within 10 minutes.**

Verify it's gone:
```bash
az group show --name smart-ticket-rg 2>&1 || echo "Resource group deleted ✅"
```

---

## Credentials File Location

All URLs, IPs, passwords, and keys are saved in Cloud Shell at:
```
~/smartticket-credentials.txt
```

View it any time:
```bash
cat ~/smartticket-credentials.txt
```
