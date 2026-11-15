"""One serving contract; experimental training artifacts do not change routing."""
CONTRACT_VERSION = 'navi-forecast-1.1'


def predict_current(features, user_id=None, *, legacy_predict=None, trajectory_predict=None):
    if legacy_predict is None:
        from .predict_mood import predict_next_day
        legacy_predict = predict_next_day
    if trajectory_predict is None:
        from .trajectory_model import predict_trajectory
        trajectory_predict = predict_trajectory
    legacy = legacy_predict(features, user_id)
    trajectory = trajectory_predict(features, user_id, legacy_next_day=legacy)
    return {
        **legacy,
        **trajectory,
        'raw_next_day_model': legacy,
        'model_version': f"{legacy.get('model_version', 'unknown')}+{CONTRACT_VERSION}",
        'prediction_contract_version': CONTRACT_VERSION,
        'model_family': 'legacy_plus_multimodal_trajectory_v1',
        'target_definition': 'journal_sentiment_forecast',
        'confidence_kind': 'uncalibrated_heuristic_score',
        'uncertainty_kind': 'heuristic_spread_not_prediction_interval',
    }
