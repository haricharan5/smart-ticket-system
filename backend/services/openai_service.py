"""
LLM Service — Local Inference via Ollama
=========================================
Uses a self-hosted Phi-3 Mini model running on VM2 (NLP Worker).
Ollama exposes an OpenAI-compatible REST API on port 11434, so we
use the standard `openai` Python client pointed at the local endpoint.

No external API calls. No usage fees. All inference runs on your VM.

Required env vars:
    LLM_BASE_URL  — e.g. http://10.0.0.5:11434/v1   (VM2 private IP)
    LLM_MODEL     — e.g. phi3:mini                   (Ollama model tag)
"""

from openai import OpenAI
import json
import os
import logging

logger = logging.getLogger("smartticket.llm")

CATEGORIES = ["Technical Issue", "Billing Query", "General Inquiry", "HR/Internal", "Other"]

SYSTEM_PROMPT = """You are an expert support ticket analyst. Given a ticket title and description,
return a JSON object with:
- category: one of exactly ["Technical Issue", "Billing Query", "General Inquiry", "HR/Internal", "Other"]
- draft_reply: a professional, empathetic 3-sentence reply the agent can send to the customer

Rules:
- Technical Issue  → software bugs, errors, system failures, access problems
- Billing Query    → invoices, payments, charges, refunds, subscriptions
- HR/Internal      → leave, onboarding, salary, company policy, employees
- General Inquiry  → questions, information requests, how-to questions
- Other            → anything that does not fit the above

Respond ONLY with valid JSON. No explanation, no markdown fences."""


def _keyword_fallback(title: str, description: str) -> dict:
    """
    Simple keyword-based classifier used when Ollama is unavailable.
    Ensures the system degrades gracefully instead of crashing.
    """
    text = (title + " " + description).lower()
    if any(w in text for w in ["billing", "invoice", "payment", "charge", "refund", "subscription", "price"]):
        category = "Billing Query"
    elif any(w in text for w in ["hr", "leave", "vacation", "salary", "onboard", "policy", "employee", "payroll"]):
        category = "HR/Internal"
    elif any(w in text for w in ["error", "bug", "crash", "fail", "broken", "not working", "cannot", "unable", "slow"]):
        category = "Technical Issue"
    elif any(w in text for w in ["question", "how", "what", "where", "info", "information", "help me understand"]):
        category = "General Inquiry"
    else:
        category = "Other"

    return {
        "category": category,
        "draft_reply": (
            f"Thank you for contacting our support team. "
            f"We have received your request and a specialist from our {category} team will review it shortly. "
            "Please expect a response within our standard SLA timeframe."
        ),
    }


class OpenAIService:
    """
    Wraps local Ollama inference with the same interface as the original
    Azure OpenAI service, so no changes are needed in routes/tickets.py.
    """

    def __init__(self):
        base_url = os.environ.get("LLM_BASE_URL", "http://localhost:11434/v1")
        self.model = os.environ.get("LLM_MODEL", "phi3:mini")
        # Ollama accepts any non-empty string as the API key
        self.client = OpenAI(base_url=base_url, api_key="ollama")
        logger.info("LLM service initialised | endpoint=%s | model=%s", base_url, self.model)

    def classify_and_draft(self, title: str, description: str) -> dict:
        """
        Sends the ticket to the local LLM and returns:
            { "category": str, "draft_reply": str }

        Falls back to keyword matching if the model is unreachable or
        returns malformed output, so ticket creation never fails.
        """
        user_msg = f"Title: {title}\nDescription: {description[:2000]}"
        try:
            response = self.client.chat.completions.create(
                model=self.model,
                messages=[
                    {"role": "system", "content": SYSTEM_PROMPT},
                    {"role": "user",   "content": user_msg},
                ],
                response_format={"type": "json_object"},
                temperature=0.1,   # Low temperature → consistent JSON output
                max_tokens=400,
            )
            raw = response.choices[0].message.content
            result = json.loads(raw)

            category = result.get("category", "Other")
            if category not in CATEGORIES:
                logger.warning("LLM returned unknown category %r — defaulting to Other", category)
                category = "Other"

            return {
                "category": category,
                "draft_reply": result.get(
                    "draft_reply",
                    "Thank you for contacting support. We will get back to you shortly.",
                ),
            }

        except Exception as exc:
            logger.warning("LLM call failed (%s) — using keyword fallback", exc)
            return _keyword_fallback(title, description)
