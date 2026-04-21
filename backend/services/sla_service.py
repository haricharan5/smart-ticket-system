from datetime import datetime, timedelta, timezone

SLA_HOURS = {
    "Technical Issue": 4,
    "Billing Query": 8,
    "General Inquiry": 24,
    "HR/Internal": 48,
    "Other": 24,
}

WARNING_THRESHOLD_SECONDS = 1800  # 30 minutes


def get_sla_deadline(category: str, created_at: datetime) -> datetime:
    hours = SLA_HOURS.get(category, 24)
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    return created_at + timedelta(hours=hours)


def compute_sla_status(deadline: datetime) -> dict:
    now = datetime.now(timezone.utc)
    if deadline.tzinfo is None:
        deadline = deadline.replace(tzinfo=timezone.utc)
    remaining = (deadline - now).total_seconds()
    return {
        "remaining_seconds": max(0, int(remaining)),
        "is_breached": remaining <= 0,
        "is_warning": 0 < remaining <= WARNING_THRESHOLD_SECONDS,
    }
