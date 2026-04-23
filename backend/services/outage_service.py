from datetime import datetime, timedelta, timezone
from sqlalchemy.orm import Session
from models.ticket import Ticket, OutageFlag

OUTAGE_THRESHOLD = 3
WINDOW_MINUTES = 30


def check_and_flag_outage(db: Session, category: str) -> bool:
    window_start = datetime.now(timezone.utc) - timedelta(minutes=WINDOW_MINUTES)
    count = (
        db.query(Ticket)
        .filter(Ticket.category == category, Ticket.created_at >= window_start)
        .count()
    )
    if count < OUTAGE_THRESHOLD:
        return False

    existing = (
        db.query(OutageFlag)
        .filter(
            OutageFlag.category == category,
            OutageFlag.resolved == False,
        )
        .first()
    )
    if existing:
        return True

    flag = OutageFlag(
        category=category,
        ticket_count=count,
        window_start=window_start,
        window_end=datetime.now(timezone.utc),
    )
    db.add(flag)
    db.commit()
    return True
