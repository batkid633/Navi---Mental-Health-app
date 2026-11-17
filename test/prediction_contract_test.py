import ast
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'backend/ml' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

service = load('prediction_service')
privacy = load('insight_context')


class PredictionContractTest(unittest.TestCase):
    def test_shared_contract_preserves_trajectory_and_artifact_version(self):
        def legacy(features, uid):
            self.assertEqual(uid, 'synthetic')
            return {'model_version': 'fixture.pkl', 'predicted_delta': .2, 'confidence': .4}
        def trajectory(features, uid, legacy_next_day):
            self.assertEqual(legacy_next_day['predicted_delta'], .2)
            return {'predicted_delta': .1, 'confidence': .3, 'trajectory': [{'horizon_days': 1}]}
        result = service.predict_current({}, 'synthetic', legacy_predict=legacy, trajectory_predict=trajectory, primary="v1")
        self.assertEqual(result['model_version'], 'fixture.pkl+navi-forecast-1.1')
        self.assertEqual(result['predicted_delta'], .1)
        self.assertEqual(result['confidence_kind'], 'uncalibrated_heuristic_score')

    def test_all_public_prediction_routes_use_shared_service(self):
        tree = ast.parse((ROOT / 'backend/app.py').read_text())
        names = {'predict_tomorrow', 'predict_mood_trajectory', 'predict_mood_trajectory_v2'}
        for node in tree.body:
            if isinstance(node, ast.FunctionDef) and node.name in names:
                calls = [n.func.id for n in ast.walk(node) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)]
                self.assertEqual(calls.count('predict_current'), 1, node.name)
                self.assertNotIn('predict_trajectory_v2', calls)
                self.assertNotIn('predict_next_day', calls)

    def test_llm_boundary_rejects_prose_even_in_metric_fields(self):
        context = {'journal': 'PRIVATE', 'note': 'PRIVATE', 'rolling_mean_7': 'PRIVATE',
                   'predicted_delta': .1, 'confidence': .4,
                   'trajectory': [{'horizon_days': 1, 'predicted_mood': 'PRIVATE'}],
                   'modality_coverage': {'available_modalities': ['journal', 'PRIVATE']},
                   'trajectory_summary': {'direction': 'PRIVATE'}}
        safe = privacy.safe_insight_context(context)
        self.assertNotIn('PRIVATE', str(safe))
        self.assertEqual(safe['predicted_delta'], .1)
        self.assertEqual(safe['modality_coverage']['available_modalities'], ['journal'])

    def test_cache_changes_with_model_and_numeric_inputs_but_not_journal_text(self):
        base = {'model_version': 'a', 'predicted_delta': .1}
        key = privacy.insight_cache_key(base)
        self.assertNotEqual(key, privacy.insight_cache_key({**base, 'model_version': 'b'}))
        self.assertNotEqual(key, privacy.insight_cache_key({**base, 'predicted_delta': .2}))
        self.assertEqual(key, privacy.insight_cache_key({**base, 'journal': 'PRIVATE'}))

if __name__ == '__main__':
    unittest.main()
