from fastapi import APIRouter, Depends
from sqlalchemy import func, cast, Date, text
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from database import get_db
from models.ticket import Ticket, Team

router = APIRouter(prefix="/api/analytics", tags=["analytics"])


@router.get("/summary")
def get_summary(db: Session = Depends(get_db)):
    total = db.query(func.count(Ticket.id)).scalar()
    open_count = db.query(func.count(Ticket.id)).filter(Ticket.status == "open").scalar()
    resolved = db.query(func.count(Ticket.id)).filter(Ticket.status == "resolved").scalar()
    in_progress = db.query(func.count(Ticket.id)).filter(Ticket.status == "in_progress").scalar()
    critical = db.query(func.count(Ticket.id)).filter(Ticket.urgency == "Critical").scalar()
    return {
        "total": total,
        "open": open_count,
        "in_progress": in_progress,
        "resolved": resolved,
        "critical": critical,
    }


@router.get("/categories")
def get_category_distribution(db: Session = Depends(get_db)):
    rows = (
        db.query(Ticket.category, func.count(Ticket.id).label("count"))
        .filter(Ticket.category != None)
        .group_by(Ticket.category)
        .all()
    )
    return [{"category": r.category, "count": r.count} for r in rows]


@router.get("/daily")
def get_daily_volume(db: Session = Depends(get_db)):
    since = datetime.now(timezone.utc) - timedelta(days=7)
    # Use CONVERT(date, created_at) which is reliable on Azure SQL
    day_col = func.convert(text("date"), Ticket.created_at)
    rows = (
        db.query(day_col.label("day"), func.count(Ticket.id).label("count"))
        .filter(Ticket.created_at >= since)
        .group_by(day_col)
        .order_by(day_col)
        .all()
    )
    return [{"day": str(r.day), "count": r.count} for r in rows]


@router.get("/resolution")
def get_resolution_times(db: Session = Depends(get_db)):
    # DATEDIFF requires unquoted keyword — use text() for the full expression
    rows = (
        db.query(
            Ticket.category,
            func.avg(
                text("DATEDIFF(minute, tickets.created_at, tickets.resolved_at)")
            ).label("avg_minutes"),
        )
        .filter(Ticket.resolved_at != None)
        .group_by(Ticket.category)
        .all()
    )
    return [
        {"category": r.category, "avg_minutes": round(float(r.avg_minutes or 0))}
        for r in rows
    ]


@router.get("/sentiment")
def get_sentiment_distribution(db: Session = Depends(get_db)):
    rows = (
        db.query(Ticket.sentiment, func.count(Ticket.id).label("count"))
        .filter(Ticket.sentiment != None)
        .group_by(Ticket.sentiment)
        .all()
    )
    return [{"sentiment": r.sentiment, "count": r.count} for r in rows]


@router.get("/teams")
def get_team_load(db: Session = Depends(get_db)):
    rows = (
        db.query(Team.name, func.count(Ticket.id).label("count"))
        .join(Ticket, Ticket.team_id == Team.id, isouter=True)
        .filter(Ticket.status.in_(["open", "in_progress"]))
        .group_by(Team.name)
        .all()
    )
    return [{"team": r.name, "count": r.count} for r in rows]
