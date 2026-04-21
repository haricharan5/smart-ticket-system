from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from datetime import datetime, timezone
from database import get_db
from models.ticket import Ticket, OutageFlag
from models.user import User
from services.auth_service import get_current_user
from services.sla_service import compute_sla_status

router = APIRouter(prefix="/api/alerts", tags=["alerts"])


@router.get("/sla")
def get_sla_alerts(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    open_tickets = (
        db.query(Ticket)
        .filter(Ticket.status.in_(["open", "in_progress"]), Ticket.sla_deadline != None)
        .all()
    )
    warnings, breaches = [], []
    for t in open_tickets:
        status = compute_sla_status(t.sla_deadline)
        entry = {
            "ticket_id": t.id,
            "title": t.title,
            "category": t.category,
            "urgency": t.urgency,
            "remaining_seconds": status["remaining_seconds"],
        }
        if status["is_breached"]:
            breaches.append(entry)
        elif status["is_warning"]:
            warnings.append(entry)
    return {"warnings": warnings, "breaches": breaches}


@router.get("/outage")
def get_outage_flags(db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    flags = (
        db.query(OutageFlag)
        .filter(OutageFlag.resolved == False)
        .order_by(OutageFlag.flagged_at.desc())
        .all()
    )
    return [
        {
            "id": f.id,
            "category": f.category,
            "ticket_count": f.ticket_count,
            "flagged_at": f.flagged_at.isoformat(),
        }
        for f in flags
    ]


@router.patch("/outage/{flag_id}/resolve")
def resolve_outage(flag_id: int, db: Session = Depends(get_db), _: User = Depends(get_current_user)):
    flag = db.query(OutageFlag).filter(OutageFlag.id == flag_id).first()
    if flag:
        flag.resolved = True
        db.commit()
    return {"resolved": True}
