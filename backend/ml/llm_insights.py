from openai import OpenAI
import os
from dotenv import load_dotenv
import json
from datetime import datetime
from pathlib import Path
try:
    from user_data import user_logs_dir
except ModuleNotFoundError:
    from ..user_data import user_logs_dir

load_dotenv()

BACKEND_DIR = Path(__file__).resolve().parents[1]
INSIGHTS_PATH = BACKEND_DIR / "logs" / "llm_insights.jsonl"

def _insights_path(user_id: str | None = None) -> Path:
    if user_id:
        return user_logs_dir(user_id) / "llm_insights.jsonl"
    return INSIGHTS_PATH

def get_openai_client() -> OpenAI:
    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY is not configured")
    return OpenAI(api_key=key)

def load_cached_insight(entry_date, user_id: str | None = None):
    # Normalize date → YYYY-MM-DD
    if "T" in entry_date:
        entry_date = entry_date.split("T")[0]

    insights_path = _insights_path(user_id)
    if not insights_path.exists():
        return None
    with open(insights_path, encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            if row["date"] == entry_date:
                return row["insight"]
    return None

SYSTEM_PROMPT = """
You are a reflective mental health journaling assistant.
You explain mood predictions in a supportive, grounded, non-alarmist way.
Avoid medical claims. Focus on patterns, not certainty.
"""

def generate_insight(context: dict) -> str:
    user_prompt = f"""

Write a concise insight (max 150 words).
If you reach the word limit, complete the current sentence
and stop cleanly without truncation.

Tomorrow mood prediction:
- Predicted change: {context['predicted_delta']}
- Confidence: {context['confidence']}

Recent patterns:
- 7-day sentiment mean: {context.get('rolling_mean_7')}
- Volatility: {context.get('volatility_7')}
- Sleep hours: {context.get('sleep_hours')}
- HRV: {context.get('hrv_rmssd')}
- Strain: {context.get('strain')}

Explain *why* tomorrow may look this way and suggest one gentle reflection.
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

    return content.strip()

def fallback_insight(context: dict) -> str:
    predicted_delta = context.get("predicted_delta", 0.0) or 0.0
    confidence = context.get("confidence", 0.0) or 0.0
    direction = "steady"
    if predicted_delta > 0.1:
        direction = "slightly brighter"
    elif predicted_delta < -0.1:
        direction = "a little more tender"

    return (
        f"Tomorrow is estimated to look {direction}, with confidence around "
        f"{confidence:.0%}. Treat this as a pattern signal rather than a certainty. "
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
