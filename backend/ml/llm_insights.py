from openai import OpenAI
import os
from dotenv import load_dotenv
import json
from datetime import datetime
from pathlib import Path
try:
    from user_data import user_logs_dir
    from config import SETTINGS, secret_value
except ModuleNotFoundError:
    from ..user_data import user_logs_dir
    from ..config import SETTINGS, secret_value

load_dotenv()

BACKEND_DIR = Path(__file__).resolve().parents[1]
INSIGHTS_PATH = BACKEND_DIR / "logs" / "llm_insights.jsonl"

def _insights_path(user_id: str | None = None) -> Path:
    if user_id:
        return user_logs_dir(user_id) / "llm_insights.jsonl"
    return INSIGHTS_PATH

def get_openai_client() -> OpenAI:
    key = secret_value("OPENAI_API_KEY_SECRET", ["OPENAI_API_KEY"])
    if not key:
        raise RuntimeError("OPENAI_API_KEY is not configured")
    return OpenAI(api_key=key, timeout=SETTINGS.outbound_timeout_seconds)

def load_cached_insight(entry_date, user_id: str | None = None):
    # Normalize date → YYYY-MM-DD
    if "T" in entry_date:
        entry_date = entry_date.split("T")[0]

    insights_path = _insights_path(user_id)
    if not insights_path.exists():
        return None
    latest = None
    with open(insights_path, encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            if row["date"] == entry_date:
                latest = row["insight"]
    return latest

SYSTEM_PROMPT = """
You are a reflective mental health journaling assistant.
You explain mood predictions in a supportive, grounded, non-alarmist way.
Avoid medical claims. Focus on patterns, not certainty.
"""

def outlook_bucket(predicted_delta: float | None) -> dict:
    delta = predicted_delta or 0.0
    if delta > 0.3:
        return {
            "label": "Likely improvement tomorrow",
            "direction": "improvement",
            "allowed_terms": "improvement, brighter, lift, upward shift",
            "forbidden_terms": "decline, dip, worse, downturn, tough day",
        }
    if delta > 0.1:
        return {
            "label": "Slightly better tomorrow",
            "direction": "slight improvement",
            "allowed_terms": "slightly better, modest lift, steadier, brighter",
            "forbidden_terms": "decline, dip, worse, downturn, tough day",
        }
    if delta > -0.1:
        return {
            "label": "Likely stable",
            "direction": "stable",
            "allowed_terms": "stable, steady, little change, similar",
            "forbidden_terms": "improvement, decline, dip, worse, downturn",
        }
    if delta > -0.3:
        return {
            "label": "Slight dip possible",
            "direction": "slight dip",
            "allowed_terms": "slight dip, tender, lower, more demanding",
            "forbidden_terms": "improvement, better, brighter, lift",
        }
    return {
        "label": "Higher risk of a tough day",
        "direction": "larger dip",
        "allowed_terms": "tougher, lower, more demanding, notable dip",
        "forbidden_terms": "improvement, better, brighter, lift",
    }

def _violates_bucket(text: str, bucket: dict) -> bool:
    normalized = text.lower()
    forbidden_terms = [
        term.strip().lower()
        for term in bucket.get("forbidden_terms", "").split(",")
        if term.strip()
    ]
    return any(term in normalized for term in forbidden_terms)

def generate_insight(context: dict) -> str:
    bucket = outlook_bucket(context.get("predicted_delta"))
    trajectory = context.get("trajectory") or []
    trajectory_lines = []
    for point in trajectory[:4]:
        trajectory_lines.append(
            f"- {point.get('horizon_days')} days: mood {point.get('predicted_mood')}, "
            f"delta {point.get('predicted_delta')}, uncertainty {point.get('uncertainty')}"
        )
    modality_coverage = context.get("modality_coverage") or {}
    coverage_modalities = ", ".join(modality_coverage.get("available_modalities") or [])
    if not coverage_modalities:
        coverage_modalities = "journal only or unavailable"

    user_prompt = f"""

Write a concise insight (max 150 words).
If you reach the word limit, complete the current sentence
and stop cleanly without truncation.

Mood trajectory prediction:
- Predicted change: {context['predicted_delta']}
- Confidence: {context['confidence']}
- Required tomorrow label: {bucket['label']}
- Required tomorrow direction: {bucket['direction']}
- Available modalities: {coverage_modalities}
- Trajectory:
{chr(10).join(trajectory_lines) if trajectory_lines else '- No extended trajectory available'}

Recent patterns:
- 7-day sentiment mean: {context.get('rolling_mean_7')}
- Volatility: {context.get('volatility_7')}
- Sleep hours: {context.get('sleep_hours')}
- HRV: {context.get('hrv_rmssd')}
- Strain: {context.get('strain')}
- Audio sessions today: {context.get('audio_session_count')}
- Audio negative/anxious ratios: {context.get('audio_negative_ratio')}, {context.get('audio_anxious_ratio')}

The first sentence must align with the required tomorrow label and direction.
Use terms consistent with: {bucket['allowed_terms']}.
Do not describe tomorrow using: {bucket['forbidden_terms']}.
If the extended trajectory differs from tomorrow's label, clearly separate it as a later pattern.
Explain the short-term trajectory, avoid certainty, and suggest one gentle reflection.
"""

    try:
        response = get_openai_client().chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": user_prompt}
            ],
            temperature=0.4,
            max_tokens=180
        )
    except Exception:
        return fallback_insight(context)

    # Safely extract assistant content; default to empty string if any attribute is missing or None
    content = ""
    try:
        choice = response.choices[0]
        message = getattr(choice, "message", None)
        content = getattr(message, "content", "") or ""
    except Exception:
        content = ""

    content = content.strip()
    if _violates_bucket(content, bucket):
        return fallback_insight(context)
    return content

def fallback_insight(context: dict) -> str:
    predicted_delta = context.get("predicted_delta", 0.0) or 0.0
    confidence = context.get("confidence", 0.0) or 0.0
    bucket = outlook_bucket(predicted_delta)
    summary = context.get("trajectory_summary") or {}
    direction = summary.get("direction") or "stable"
    coverage = context.get("modality_coverage") or {}
    modalities = coverage.get("available_modalities") or []
    modality_phrase = ", ".join(modalities) if modalities else "limited available data"
    return (
        f"{bucket['label']}: tomorrow is estimated to show {bucket['direction']}, "
        f"and the broader pattern is "
        f"{direction}, with confidence around {confidence:.0%}. This used "
        f"{modality_phrase}. Treat it as a trajectory signal rather than a certainty. "
        "A helpful reflection is to notice one small support that usually steadies "
        "your mood, such as rest, movement, connection, or a quieter moment."
    )

def save_cached_insight(
    entry_date: str,
    insight: str,
    user_id: str | None = None,
) -> None:
    if "T" in entry_date:
        entry_date = entry_date.split("T")[0]

    insights_path = _insights_path(user_id)
    insights_path.parent.mkdir(parents=True, exist_ok=True)
    with open(insights_path, "a", encoding="utf-8") as f:
        f.write(json.dumps({
            "user_id": user_id,
            "date": entry_date,
            "insight": insight
        }) + "\n")

def get_llm_insight(entry_date: str, features: dict, user_id: str | None = None):
    # Normalize date → YYYY-MM-DD
    if "T" in entry_date:
        entry_date = entry_date.split("T")[0]

    cached = load_cached_insight(entry_date, user_id)
    if cached:
        return cached

    insight = generate_insight(features)

    save_cached_insight(entry_date, insight, user_id)

    return insight
