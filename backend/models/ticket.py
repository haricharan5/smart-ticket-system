from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, Text
from sqlalchemy.orm import relationship
from datetime import datetime, timezone
from database import Base


class Team(Base):
    __tablename__ = "teams"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    category = Column(String(50), nullable=False)
    tickets = relationship("Ticket", back_populates="team")


class Ticket(Base):
    __tablename__ = "tickets"
    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(500), nullable=False)
    description = Column(Text, nullable=False)
    submitter_email = Column(String(255), nullable=False)
    category = Column(String(50), nullable=True)
    sentiment = Column(String(20), nullable=True)
    urgency = Column(String(20), nullable=True)
    status = Column(String(20), default="open")
    team_id = Column(Integer, ForeignKey("teams.id"), nullable=True)
    ai_draft_reply = Column(Text, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    sla_deadline = Column(DateTime, nullable=True)
    resolved_at = Column(DateTime, nullable=True)
    team = relationship("Team", back_populates="tickets")


class SLAAlert(Base):
    __tablename__ = "sla_alerts"
    id = Column(Integer, primary_key=True, index=True)
    ticket_id = Column(Integer, ForeignKey("tickets.id"))
    alert_type = Column(String(50))
    fired_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))


class OutageFlag(Base):
    __tablename__ = "outage_flags"
    id = Column(Integer, primary_key=True, index=True)
    category = Column(String(50), nullable=False)
    ticket_count = Column(Integer, nullable=False)
    window_start = Column(DateTime, nullable=False)
    window_end = Column(DateTime, nullable=False)
    flagged_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    resolved = Column(Boolean, default=False)
