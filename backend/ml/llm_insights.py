from openai import OpenAI
import os
from dotenv import load_dotenv
import json
from datetime import datetime

load_dotenv()
key = os.getenv("OPENAI_API_KEY")
client = OpenAI(api_key=key)

INSIGHTS_PATH = "logs/llm_insights.jsonl"

def load_cached_insight(entry_date):
    def load_cached_insight(entry_date):
        if "T" in entry_date:
          entry_date = entry_date.split("T")[0]

    if not os.path.exists(INSIGHTS_PATH):
        return None
    with open(INSIGHTS_PATH) as f:
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

    response = client.chat.completions.create(
        model="gpt-4.1-mini",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        temperature=0.4,
        max_tokens=180
    )

    # Safely extract assistant content; default to empty string if any attribute is missing or None
    content = ""
    try:
        choice = response.choices[0]
        message = getattr(choice, "message", None)
        content = getattr(message, "content", "") or ""
    except Exception:
        content = ""

    return content.strip()

def get_llm_insight(entry_date: str, features: dict):
    # Normalize date → YYYY-MM-DD
    if "T" in entry_date:
        entry_date = entry_date.split("T")[0]

    cached = load_cached_insight(entry_date)
    if cached:
        return cached

    insight = generate_insight(features)

    with open(INSIGHTS_PATH, "a") as f:
        f.write(json.dumps({
            "date": entry_date,
            "insight": insight
        }) + "\n")

    return insight
