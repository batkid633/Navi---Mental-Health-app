"""Pure daily metric validation/selection. No I/O, credentials, or cloud imports."""
import json
import math

VERSION = "2.0.0"
LIMITS = {
    "sleep_hours": (0, 24), "sleep_efficiency": (0, 100),
    "resting_hr": (1, 300), "hrv_rmssd": (0, 2000),
    "hrv_sdnn": (0, 2000), "recovery_score": (0, 100),
    "strain": (0, 21), "active_zone_minutes": (0, 2880),
}
# A reproducible engineering precedence, not a claim of sensor superiority.
PRIORITY = ("whoop", "google_health", "apple_health")
UNITS = {"sleep_hours": "h", "sleep_efficiency": "%", "resting_hr": "bpm",
         "hrv_rmssd": "ms_rmssd", "hrv_sdnn": "ms_sdnn",
         "recovery_score": "whoop_recovery_0_100", "strain": "whoop_cycle_strain_0_21",
         "active_zone_minutes": "provider_active_zone_minutes"}


def valid_value(metric, value):
    if isinstance(value, bool) or not isinstance(value, (float, int)):
        return None
    lower, upper = LIMITS[metric]
    return float(value) if math.isfinite(value) and lower <= value <= upper else None


def decode(value):
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            result = json.loads(value)
            return result if isinstance(result, dict) else {}
        except ValueError:
            pass
    return {}


def merge_day(existing, incoming):
    """Replace this provider's snapshot; retain alternatives and explicit legacy provenance.

    No backfill is attempted. Prior values lacking attribution are retained only
    as legacy observations and excluded from normalized model columns for this day.
    """
    source = incoming.get("source")
    if source not in PRIORITY:
        raise ValueError("Unknown biometric provider")
    observations = dict(decode(existing.get("biometric_observations")))
    if not observations:
        legacy = {k: valid_value(k, existing.get(k)) for k in LIMITS}
        if any(v is not None for v in legacy.values()):
            observations["legacy_unknown"] = {"values": legacy, "version": "unverified"}
    values = {k: valid_value(k, incoming.get(k)) for k in LIMITS}
    if source != "whoop":
        values["strain"] = values["recovery_score"] = None
    if source == "apple_health":
        values["hrv_rmssd"] = None
    observations[source] = {
        "values": values, "version": incoming.get("normalization_version") if isinstance(incoming.get("normalization_version"), str) else "unverified",
        "day_policy": incoming.get("day_policy", "unspecified"),
        "details": decode(incoming.get("metric_provenance")),
        "units": UNITS,
        "availability": {k: "observed" if v is not None else "missing_or_rejected" for k, v in values.items()},
    }
    result, selected = {}, {}
    for metric in LIMITS:
        candidates = [(p, valid_value(metric, observations.get(p, {}).get("values", {}).get(metric)))
                      for p in PRIORITY if observations.get(p, {}).get("version") == VERSION]
        provider, value = next(((p, v) for p, v in candidates if v is not None), (None, None))
        result[metric] = value
        selected[metric] = provider
    result["biometric_observations"] = json.dumps(observations, sort_keys=True, allow_nan=False)
    result["biometric_sources"] = json.dumps(selected, sort_keys=True)
    result["biometric_normalization_version"] = VERSION
    result["missing_biometrics"] = int(all(result[k] is None for k in LIMITS))
    for suffix, metric in (("sleep", "sleep_hours"), ("hrv", "hrv_rmssd"), ("recovery", "recovery_score")):
        result[f"missing_{suffix}"] = int(result[metric] is None)
    return result


STORAGE_COLUMNS = list(LIMITS) + [
    "biometric_observations", "biometric_sources", "biometric_normalization_version",
    "missing_biometrics", "missing_sleep", "missing_hrv", "missing_recovery",
]


def preserve_biometrics(rows, existing):
    """Journal feature uploads must not erase provider-verified observations."""
    old = {str(r.get("date")): r for r in existing}
    result = []
    dates = set()
    for row in rows:
        row = dict(row)
        date = str(row.get("date"))
        dates.add(date)
        prior = old.get(date, {})
        if decode(prior.get("biometric_observations")):
            row.update({k: prior.get(k) for k in STORAGE_COLUMNS})
        result.append(row)
    for date, row in old.items():
        if date not in dates and decode(row.get("biometric_observations")):
            result.append(row)
    return result
