from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from dotenv import load_dotenv
import os
import logging

load_dotenv()

# ── Validate required env vars at startup ────────────────────────────────────
REQUIRED_VARS = [
    "AZURE_SQL_SERVER", "AZURE_SQL_DATABASE", "AZURE_SQL_USERNAME", "AZURE_SQL_PASSWORD",
    "AZURE_LANGUAGE_ENDPOINT", "AZURE_LANGUAGE_KEY",
    "JWT_SECRET_KEY",
    # LLM_BASE_URL and LLM_MODEL are optional — they default to the Ollama
    # instance on VM2.  The service falls back to keyword classification if
    # Ollama is unreachable, so startup is never blocked.
]
missing = [v for v in REQUIRED_VARS if not os.getenv(v)]
if missing:
    raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

# ── Configure structured JSON logging first ──────────────────────────────────
from middleware.logging_middleware import configure_logging, RequestLoggingMiddleware
configure_logging()
logger = logging.getLogger("smartticket.startup")

# ── Azure Application Insights (optional — skipped if no connection string) ──
app_insights_conn = os.getenv("APPLICATIONINSIGHTS_CONNECTION_STRING")
if app_insights_conn:
    try:
        from azure.monitor.opentelemetry import configure_azure_monitor
        configure_azure_monitor(connection_string=app_insights_conn)
        logger.info("Azure Application Insights configured.")
    except Exception as exc:
        logger.warning(f"Application Insights setup failed (non-fatal): {exc}")

# ── DB + models ──────────────────────────────────────────────────────────────
from database import engine, Base, SessionLocal
from models import ticket, user  # registers all models with Base

# ── Routes ───────────────────────────────────────────────────────────────────
from routes.auth import router as auth_router
from routes.tickets import router as tickets_router
from routes.alerts import router as alerts_router
from routes.analytics import router as analytics_router

# ── Seed data ────────────────────────────────────────────────────────────────
TEAMS = [
    {"name": "Technical Support Team", "category": "Technical Issue"},
    {"name": "Billing & Finance Team", "category": "Billing Query"},
    {"name": "Customer Success Team", "category": "General Inquiry"},
    {"name": "HR & People Team", "category": "HR/Internal"},
    {"name": "General Operations Team", "category": "Other"},
]

DEMO_USERS = [
    {"email": "admin@ticket.local",  "name": "Admin User",          "password": "Admin@2024!",  "role": "admin"},
    {"email": "lead@ticket.local",   "name": "David Brown",         "password": "Lead@2024!",   "role": "team_lead"},
    {"email": "agent1@ticket.local", "name": "John Smith",          "password": "Agent@2024!",  "role": "agent"},
    {"email": "agent2@ticket.local", "name": "Sarah Jones",         "password": "Agent@2024!",  "role": "agent"},
]


def seed_reference_data():
    from models.ticket import Team
    from models.user import User as UserModel
    from services.auth_service import hash_password

    db = SessionLocal()
    try:
        if db.query(Team).count() == 0:
            for t in TEAMS:
                db.add(Team(**t))
            db.commit()
            logger.info("Teams seeded.")

        for u in DEMO_USERS:
            exists = db.query(UserModel).filter(UserModel.email == u["email"]).first()
            if not exists:
                db.add(UserModel(
                    email=u["email"],
                    name=u["name"],
                    hashed_password=hash_password(u["password"]),
                    role=u["role"],
                ))
        db.commit()
        logger.info("Demo users seeded.")
    finally:
        db.close()


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Smart Support Ticket System...")
    Base.metadata.create_all(bind=engine)
    seed_reference_data()
    logger.info("Application ready.")
    yield
    logger.info("Application shutting down.")


# ── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Smart Support Ticket System",
    version="1.0.0",
    description="AI-powered ticket classification on Microsoft Azure",
    lifespan=lifespan,
)

# Request logging middleware (before CORS so all requests are logged)
app.add_middleware(RequestLoggingMiddleware)

frontend_url = os.getenv("FRONTEND_URL", "*")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[frontend_url] if frontend_url != "*" else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ──────────────────────────────────────────────────────────────────
app.include_router(auth_router)
app.include_router(tickets_router)
app.include_router(alerts_router)
app.include_router(analytics_router)


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok", "version": "1.0.0"}
