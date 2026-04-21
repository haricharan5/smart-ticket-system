# Cloud-Based Smart Support Ticket System
### AI-Based Classification & Analytics on Microsoft Azure

*Generated: 2026-04-20*
*Status: DRAFT — validated through structured discovery*
*Deadline: 5 days | Budget: $100 Azure credits*

---

## Problem Statement

Support Team Leads in enterprises spend 2–3 hours daily manually triaging, categorizing, and routing incoming support tickets — work that generates zero resolution value. Existing tools like Zendesk and Freshdesk offer rule-based routing but lack genuine NLP-driven classification, real-time urgency intelligence, and proactive SLA alerting. The result: misrouted tickets, invisible escalations, and managers flying blind without actionable data.

## Evidence

- Forrester reports ~23% of enterprise tickets are rerouted at least once due to wrong initial assignment
- SLA breaches occur because urgency signals are missed, not because teams lack capacity
- Assumption: classification accuracy of existing rule-based systems sits below 75% for ambiguous tickets — needs validation via demo benchmarking
- Assumption: support leads spend >2 hours/day on triage — to be validated with capstone judges as real-world context

## Proposed Solution

A cloud-native support ticket platform hosted on Microsoft Azure that uses Azure Language Service for real-time NLP classification, sentiment-based urgency scoring, and Azure OpenAI for auto-reply drafting. Tickets are submitted via a React frontend, classified in under 3 seconds, routed to the correct team automatically, and surfaced on a live dashboard with both embedded Power BI reports and React-native charts. The system proactively detects SLA breach risk and flags ticket clusters as potential outages — before any human notices.

## Key Hypothesis

We believe NLP-based auto-classification + proactive SLA alerting will eliminate manual triage for Support Team Leads.
We'll know we're right when:
- Classification accuracy exceeds 95% on the test dataset
- Zero tickets require manual team reassignment in the live demo
- Dashboard shows real-time ticket status, sentiment distribution, and outage flags without any manual input

## What We're NOT Building

- **Mobile app** — web dashboard covers the capstone scope; native app adds 3+ weeks
- **Multi-tenant support** — single-org deployment is sufficient for demo and academic evaluation
- **Live chat / chatbot** — distinct product surface; would dilute focus from core ticket intelligence
- **Customer-facing login portal** — ticket submission is via an open form; auth complexity deferred
- **Custom ML model training** — Azure Language Service (pre-trained) hits accuracy targets without weeks of training

## Success Metrics

| Metric | Target | How Measured |
|--------|--------|--------------|
| NLP Classification Accuracy | ≥ 95% | Test split of synthetic dataset (80/20) |
| Auto-routing correctness | 100% in demo | Manual verification of 20 test tickets |
| Ticket-to-classified latency | < 3 seconds | Browser network tab timing |
| SLA breach prediction | Fires ≥ 30 min before breach | Simulated ticket with backdated timestamp |
| Dashboard load time | < 2 seconds | Lighthouse / browser timing |
| Outage cluster detection | Flags ≥ 3 same-topic tickets | Batch submit 5 related tickets |

## Open Questions

- [x] **Dataset**: Use Kaggle [IT Helpdesk Ticket dataset](https://www.kaggle.com/datasets/suraj520/customer-support-ticket-dataset) as base corpus; augment with Python script to generate 500 balanced synthetic tickets across 5 categories
- [x] **Power BI**: Publish-to-Web (free public embed) — no licensing cost, sufficient for live demo
- [x] **VM split**: 3× Ubuntu 22.04 Linux + 1× Windows Server 2022 — confirmed with instructor
- [x] **Demo format**: Live demo to capstone panel — backup recorded video as contingency
- [x] **Azure OpenAI**: GPT-4o-mini — lowest cost, fastest response, Azure-native

---

## Users & Context

### Primary User — Support Team Lead

- **Who**: Mid-level operations role in an enterprise IT or SaaS support department; manages 5–15 agents; accountable for SLA compliance and queue health
- **Current behavior**: Opens email/Zendesk each morning, manually reads tickets, assigns them to agents, follows up on overdue items — all by hand
- **Trigger**: First thing every shift — queue has accumulated overnight; urgency is unknown until manually reviewed
- **Success state**: Opens dashboard, sees every ticket already classified, assigned, and color-coded by urgency; only needs to act on the 2–3 edge cases flagged red

### Secondary Users

| Role | Need | Touchpoint |
|------|------|------------|
| Support Agent | See assigned tickets, get AI-drafted reply to edit & send | Ticket detail view |
| Operations Manager | Weekly/monthly performance trends, team throughput | Power BI report page |
| System Admin | Manage categories, SLA thresholds, team assignments | Admin settings panel |

### Job to Be Done (Primary)

> When I start my shift, I want every ticket already classified, prioritized by urgency, and routed to the right agent — so I can spend my time on escalations and team coaching, not sorting emails.

### Non-Users

- **End-customers** submitting tickets — they interact via a simple form only; no login, no portal
- **C-suite executives** — they consume Power BI passively; not active system users
- **External vendors / third parties** — no access; single-org deployment

---

## Solution Detail

### Core Capabilities (MoSCoW)

| Priority | Capability | Rationale |
|----------|------------|-----------|
| Must | NLP ticket classification (Technical / Billing / General / HR / Other) | Core value proposition; demo centerpiece |
| Must | Sentiment + urgency scoring (Low / Medium / High / Critical) | Differentiator vs rule-based tools |
| Must | Auto-routing to correct team on classification | Eliminates manual triage |
| Must | Real-time dashboard — ticket queue, status, team load | Team Lead's primary workspace |
| Must | SLA breach prediction alert (30-min warning) | Proactive vs reactive — key unique feature |
| Must | Azure OpenAI auto-reply draft generation | Saves agent time; showcases Azure AI depth |
| Must | Outage/cluster detection (≥3 tickets, same category, <30 min window) | Novel intelligence layer |
| Must | Power BI analytics report (embedded) | Instructor requirement + manager use case |
| Must | React-native charts (ticket volume, category breakdown, resolution time) | Dashboard UX richness |
| Should | Email-style notification when ticket assigned (simulated) | Realistic workflow simulation |
| Should | Manual override — agent can reclassify if AI is wrong | Trust + control for users |
| Could | Historical trend comparison (this week vs last week) | Adds analytics depth |
| Could | Agent performance leaderboard | Manager engagement feature |
| Won't | Customer-facing ticket portal with auth | Out of scope — adds auth complexity |
| Won't | Mobile app | Out of scope |
| Won't | Live chat | Out of scope |

### MVP Scope (Demo-Ready in 5 Days)

A working end-to-end flow:
1. Submit a ticket via React form (title + description + email)
2. Azure Language Service classifies category + sentiment in real-time
3. Ticket auto-routes to correct team; appears on dashboard instantly
4. Azure OpenAI generates a draft reply visible on ticket detail page
5. If 3+ tickets in same category within 30 minutes → outage banner fires
6. SLA timer visible; warning triggers when 70% of SLA time consumed
7. Power BI report + React charts show live ticket distribution

### User Flow (Critical Path)

```
[User submits ticket via React form]
         ↓
[Backend receives → calls Azure Language API]
         ↓
[Category + Sentiment scored → stored in Azure SQL]
         ↓
[Auto-routing logic assigns team → SLA timer starts]
         ↓
[Azure OpenAI generates draft reply → stored with ticket]
         ↓
[Dashboard updates in real-time → Team Lead sees ticket]
         ↓
[Outage detector checks: same category ≥3 in 30 min? → Banner if yes]
         ↓
[SLA monitor: 70% time consumed? → Alert fires to Team Lead]
```

---

## Technical Approach

**Feasibility**: HIGH for core features | MEDIUM for Power BI Embedded (budget constraint)

### Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  Azure Cloud                        │
│                                                     │
│  VM1 (Linux) ──── Backend API (Python/FastAPI)      │
│  VM2 (Linux) ──── NLP Worker + Azure Language API   │
│  VM3 (Linux) ──── React Frontend (served via nginx) │
│  VM4 (Windows) ── Active Directory + Admin Tools    │
│                                                     │
│  Azure App Service ── Fallback/staging deploy       │
│  Azure SQL Database ── Tickets, teams, SLA data     │
│  Azure Cognitive/Language Service ── NLP            │
│  Azure OpenAI (GPT-4o-mini) ── Draft replies        │
│  Power BI ── Embedded analytics report              │
│  Docker ── Containerized on all Linux VMs           │
│  Active Directory ── Auth + team group management   │
└─────────────────────────────────────────────────────┘
```

### Key Technical Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| NLP engine | Azure Language Service (pre-trained) | 95%+ accuracy without training time; fits budget |
| Auto-reply | Azure OpenAI GPT-4o-mini | Cheapest capable model; ~$0.15/1M tokens |
| Database | Azure SQL Basic | Structured ticket data; familiar SQL; free 250GB |
| Frontend state | React + polling (2s interval) | Real-time feel without WebSocket complexity in 5 days |
| Docker base image | python:3.11-slim + node:20-alpine | Minimal image sizes; fast CI |
| VM OS split | 3× Ubuntu 22.04 + 1× Windows Server 2022 | Instructor requirement; AD needs Windows |
| Analytics dual | Power BI Publish-to-Web (free) + Recharts in React | Avoids Embedded licensing cost |

### Sample Dataset Strategy

Use **Kaggle Customer Support Ticket Dataset** (`suraj520/customer-support-ticket-dataset`) as the base corpus. Augment with a Python script that generates 500 synthetic tickets across 5 categories with injected sentiment variance. Split 80/20 for accuracy benchmarking.

```
Synthetic ticket categories:
- Technical Issue     (35%) — server errors, login failures, bugs
- Billing Query       (25%) — invoice, refund, payment
- General Inquiry     (20%) — feature questions, how-to
- HR / Internal       (10%) — leave, payroll, access request
- Other               (10%) — uncategorized edge cases
```

### Technical Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Azure budget exhausted by VMs | HIGH | Use B1s VMs (~$0.012/hr); stop VMs when not demoing |
| Azure OpenAI quota / approval delay | MEDIUM | Apply for access Day 1; fallback to Azure Language summarization |
| Power BI Embedded licensing cost | MEDIUM | Use Publish-to-Web (free public embed) instead |
| Real-time dashboard latency | LOW | 2-second polling is sufficient; no WebSocket needed for demo |
| NLP accuracy below 95% on edge cases | LOW | Azure Language Service benchmarks at 97%+ on support text |
| Active Directory integration complexity | MEDIUM | Use Azure AD Free tier; teams as AD security groups |

---

## Implementation Phases

| # | Phase | Description | Status | Parallel | Depends | PRP Plan |
|---|-------|-------------|--------|----------|---------|----------|
| 1 | Azure Infrastructure | VMs, AD, Docker, networking, Azure services provisioning | pending | - | - | - |
| 2 | Data & NLP Pipeline | Synthetic dataset, Azure Language integration, classification + sentiment scoring | pending | - | 1 | - |
| 3 | Backend API | FastAPI app, ticket CRUD, routing logic, SLA timer, outage detector | pending | with 4 | 2 | - |
| 4 | React Dashboard | Ticket form, queue view, ticket detail, real-time polling, alert banners | pending | with 3 | 2 | - |
| 5 | OpenAI + Analytics | Auto-reply integration, Power BI embed, React charts (Recharts) | pending | - | 3, 4 | - |
| 6 | Integration & Demo | End-to-end testing, demo script, load 50 sample tickets, deploy to Azure | pending | - | 5 | - |

### Phase Details

**Phase 1: Azure Infrastructure** *(Day 1)*
- **Goal**: Full Azure environment live with all services provisioned
- **Scope**: 3 Linux VMs + 1 Windows VM, Docker installed on Linux VMs, Azure AD with team groups (Technical, Billing, General, HR), Azure SQL database with schema, Azure Language + OpenAI resources created, networking/firewall rules set
- **Success signal**: Can SSH into all VMs; Docker `hello-world` runs; Azure SQL connection string works; Language API returns a test classification

**Phase 2: Data & NLP Pipeline** *(Day 2 AM)*
- **Goal**: Classification + sentiment scoring working end-to-end
- **Scope**: 500-ticket synthetic dataset generated and loaded, Azure Language Service integration tested, classification accuracy benchmark run (≥95% target), sentiment labels (Low/Medium/High/Critical) mapped from confidence scores
- **Success signal**: Python script classifies 20 sample tickets with correct category and sentiment; accuracy report generated

**Phase 3: Backend API** *(Day 2 PM – Day 3)*
- **Goal**: All business logic endpoints live and tested
- **Scope**: FastAPI app containerized on VM1, endpoints: POST /tickets, GET /tickets, GET /tickets/{id}, POST /tickets/{id}/classify, GET /alerts/sla, GET /alerts/outage; SLA timer logic (configurable per category); outage detector (3+ same-category tickets in 30-min rolling window); Azure SQL integration
- **Success signal**: Postman collection of 10 API calls all return correct responses; SLA alert fires on test ticket; outage flag triggers on batch insert

**Phase 4: React Dashboard** *(Day 3 — parallel with Phase 3)*
- **Goal**: Full frontend UI live and connected to API
- **Scope**: Ticket submission form, live ticket queue table with category/sentiment/status badges, ticket detail view with AI draft reply, SLA countdown timers, outage alert banner, team filter sidebar, 2-second polling for real-time updates
- **Success signal**: Submit a ticket via form → appears on dashboard within 3 seconds with correct classification and routing

**Phase 5: OpenAI + Analytics** *(Day 4)*
- **Goal**: Auto-reply drafts live; analytics dashboards complete
- **Scope**: Azure OpenAI GPT-4o-mini integration for draft reply generation on ticket creation, Power BI report published (ticket volume by category, avg resolution time, SLA compliance rate), Recharts in React (donut chart for category split, bar chart for daily volume, line chart for resolution trend)
- **Success signal**: New ticket shows AI draft reply within 5 seconds; Power BI iframe loads in dashboard; all 3 React charts render with real data

**Phase 6: Integration & Demo Prep** *(Day 5)*
- **Goal**: Demo-ready, stable, impressive
- **Scope**: Load 50 pre-classified sample tickets into database, run full end-to-end demo script 3 times, fix any UI/UX rough edges, record backup demo video, prepare 2-min live demo narrative, stress test with 10 simultaneous ticket submissions
- **Success signal**: Full demo runs without errors in 3 consecutive attempts; backup video recorded

### Parallelism Notes

Phases 3 and 4 run in parallel — backend and frontend can be developed simultaneously because the API contract (endpoints + response shapes) is defined at the start of Phase 2. Frontend uses mock data until Phase 3 API is ready, then switches to live endpoints on Day 3 afternoon.

---

## Decisions Log

| Decision | Choice | Alternatives Considered | Rationale |
|----------|--------|------------------------|-----------|
| NLP approach | Azure Language Service (zero-shot) | Train custom model, spaCy local, HuggingFace | Pre-trained hits 95%+ with zero training time; fits 5-day window |
| Auto-reply AI | Azure OpenAI GPT-4o-mini | GPT-4o, local Llama, Azure ML | Lowest cost capable model; Azure-native; ~$5 total usage |
| Database | Azure SQL Basic | Cosmos DB, Postgres, SQLite | Structured ticket schema fits relational model; familiar to team; $5/mo |
| Real-time updates | React polling (2s) | WebSocket, Server-Sent Events | Simpler implementation; sufficient for demo; no infra changes needed |
| Analytics dual-stack | Power BI (free embed) + Recharts | Power BI Embedded only, Grafana, Chart.js | Budget constraint rules out Embedded licensing; Recharts gives interactive UX |
| VM split | 3 Linux + 1 Windows | 2+2, all Linux | AD requires Windows; Linux best for containerized Python/React workloads |
| Dataset | Synthetic (script-generated) + Kaggle base | Real org data, manual creation only | Kaggle base gives realistic language patterns; script controls category balance |

---

## Research Summary

**Market Context**
Zendesk, ServiceNow, Freshdesk, and Jira Service Management all offer ticket management but rely on rule-based routing. None combine real-time NLP classification + sentiment urgency scoring + proactive SLA prediction + cluster-based outage detection in a single platform at this price point. Azure's Language Service provides 97%+ accuracy on customer support text out-of-the-box, eliminating custom model training as a bottleneck.

**Technical Context**
Azure Language Service (successor to Text Analytics) supports custom classification and pre-built sentiment analysis. Azure OpenAI GPT-4o-mini is the most cost-efficient model for short-form text generation (reply drafts). Power BI Publish-to-Web is free and sufficient for academic demo purposes without requiring Premium licensing. Docker on Ubuntu 22.04 with Azure Container Registry provides clean, reproducible deployments across VMs.

---

*Generated: 2026-04-20*
*Status: DRAFT — needs validation*
*Next step: Run `/prp-plan .claude/PRPs/prds/smart-support-ticket-system.prd.md` to generate Phase 1 implementation plan*
