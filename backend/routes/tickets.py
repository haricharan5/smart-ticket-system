from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from datetime import datetime, timezone
from database import get_db
from models.ticket import Ticket, Team
from models.user import User
from services.nlp_service import NLPService
from services.openai_service import OpenAIService
from services.sla_service import get_sla_deadline, compute_sla_status
from services.outage_service import check_and_flag_outage
from services.auth_service import get_current_user, require_role

router = APIRouter(prefix="/api/tickets", tags=["tickets"])

_nlp: NLPService | None = None
_ai: OpenAIService | None = None


def get_nlp() -> NLPService:
    global _nlp
    if _nlp is None:
        _nlp = NLPService()
    return _nlp


def get_ai() -> OpenAIService:
    global _ai
    if _ai is None:
        _ai = OpenAIService()
    return _ai


class TicketCreate(BaseModel):
    title: str
    description: str
    submitter_email: str


class TicketStatusUpdate(BaseModel):
    status: str


class TicketCategoryOverride(BaseModel):
    category: str


class TicketReplyUpdate(BaseModel):
    reply: str


def serialize(ticket: Ticket) -> dict:
    sla_status = {}
    if ticket.sla_deadline and ticket.status != "resolved":
        sla_status = compute_sla_status(ticket.sla_deadline)
    return {
        "id": ticket.id,
        "title": ticket.title,
        "description": ticket.description,
        "submitter_email": ticket.submitter_email,
        "category": ticket.category,
        "sentiment": ticket.sentiment,
        "urgency": ticket.urgency,
        "status": ticket.status,
        "team": ticket.team.name if ticket.team else None,
        "team_id": ticket.team_id,
        "ai_draft_reply": ticket.ai_draft_reply,
        "created_at": ticket.created_at.isoformat() if ticket.created_at else None,
        "sla_deadline": ticket.sla_deadline.isoformat() if ticket.sla_deadline else None,
        "resolved_at": ticket.resolved_at.isoformat() if ticket.resolved_at else None,
        "sla_status": sla_status,
    }


@router.post("", status_code=201)
def create_ticket(
    body: TicketCreate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),  # any authenticated user can submit
):
    sentiment_data = get_nlp().analyze_sentiment(f"{body.title} {body.description}")
    ai_data = get_ai().classify_and_draft(body.title, body.description)

    category = ai_data["category"]
    team = db.query(Team).filter(Team.category == category).first()
    sla_deadline = get_sla_deadline(category, datetime.now(timezone.utc))

    ticket = Ticket(
        title=body.title,
        description=body.description,
        submitter_email=body.submitter_email,
        category=category,
        sentiment=sentiment_data["sentiment"],
        urgency=sentiment_data["urgency"],
        status="open",
        team_id=team.id if team else None,
        ai_draft_reply=ai_data["draft_reply"],
        sla_deadline=sla_deadline,
    )
    db.add(ticket)
    db.commit()
    db.refresh(ticket)
    check_and_flag_outage(db, category)
    return serialize(ticket)


@router.get("")
def list_tickets(
    status: str = None,
    category: str = None,
    team_id: int = None,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    query = db.query(Ticket)
    if status:
        query = query.filter(Ticket.status == status)
    if category:
        query = query.filter(Ticket.category == category)
    if team_id:
        query = query.filter(Ticket.team_id == team_id)
    tickets = query.order_by(Ticket.created_at.desc()).limit(200).all()
    return [serialize(t) for t in tickets]


@router.get("/{ticket_id}")
def get_ticket(
    ticket_id: int,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    ticket = db.query(Ticket).filter(Ticket.id == ticket_id).first()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    return serialize(ticket)


@router.patch("/{ticket_id}/status")
def update_status(
    ticket_id: int,
    body: TicketStatusUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),  # any authenticated user can update status
):
    ticket = db.query(Ticket).filter(Ticket.id == ticket_id).first()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    ticket.status = body.status
    if body.status == "resolved":
        ticket.resolved_at = datetime.now(timezone.utc)
    db.commit()
    db.refresh(ticket)
    return serialize(ticket)


@router.patch("/{ticket_id}/reply")
def update_reply(
    ticket_id: int,
    body: TicketReplyUpdate,
    db: Session = Depends(get_db),
    _: User = Depends(get_current_user),
):
    ticket = db.query(Ticket).filter(Ticket.id == ticket_id).first()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    ticket.ai_draft_reply = body.reply
    db.commit()
    db.refresh(ticket)
    return serialize(ticket)


@router.patch("/{ticket_id}/category")
def override_category(
    ticket_id: int,
    body: TicketCategoryOverride,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_role("admin", "team_lead")),  # only leads/admins
):
    ticket = db.query(Ticket).filter(Ticket.id == ticket_id).first()
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    team = db.query(Team).filter(Team.category == body.category).first()
    ticket.category = body.category
    ticket.team_id = team.id if team else ticket.team_id
    ticket.sla_deadline = get_sla_deadline(body.category, ticket.created_at)
    db.commit()
    db.refresh(ticket)
    return serialize(ticket)
