import time
import json
import logging
import os
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger("smartticket.api")


def configure_logging():
    """Set up structured JSON logging to stdout and optionally to a file."""
    log_level = os.getenv("LOG_LEVEL", "INFO").upper()

    class JsonFormatter(logging.Formatter):
        def format(self, record: logging.LogRecord) -> str:
            log_record = {
                "timestamp": self.formatTime(record),
                "level": record.levelname,
                "logger": record.name,
                "message": record.getMessage(),
            }
            if record.exc_info:
                log_record["exception"] = self.formatException(record.exc_info)
            return json.dumps(log_record)

    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())

    # Optional: write to file when LOG_FILE env var is set
    handlers = [handler]
    log_file = os.getenv("LOG_FILE")
    if log_file:
        os.makedirs(os.path.dirname(log_file), exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        file_handler.setFormatter(JsonFormatter())
        handlers.append(file_handler)

    logging.basicConfig(level=log_level, handlers=handlers, force=True)

    # Silence noisy third-party loggers
    for noisy in ["azure", "urllib3", "httpx", "openai"]:
        logging.getLogger(noisy).setLevel(logging.WARNING)


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.perf_counter()
        try:
            response = await call_next(request)
            duration_ms = round((time.perf_counter() - start) * 1000, 2)
            log_level = logging.WARNING if response.status_code >= 400 else logging.INFO
            logger.log(
                log_level,
                json.dumps({
                    "event": "request",
                    "method": request.method,
                    "path": str(request.url.path),
                    "status": response.status_code,
                    "duration_ms": duration_ms,
                    "ip": request.client.host if request.client else "unknown",
                }),
            )
            return response
        except Exception as exc:
            duration_ms = round((time.perf_counter() - start) * 1000, 2)
            logger.error(
                json.dumps({
                    "event": "request_error",
                    "method": request.method,
                    "path": str(request.url.path),
                    "duration_ms": duration_ms,
                    "error": str(exc),
                }),
            )
            raise
