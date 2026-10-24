import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('report', Path(__file__).resolve().parents[1] / 'tools/beta_dashboard/report.py')
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def fixture(counts=(0, 0, 0, 0, 2)):
    n = sum(counts)
    mean = str(sum((i + 1) * v for i, v in enumerate(counts)) / n) if n else ''
    lines = ['metric,category,count,mean', 'schema_version,beta-feedback-1,,',
             f'completed,total,{n},', 'skipped,total,1,', f'recorded_days,total,{n + 1},']
    for metric in ('ease', 'helpfulness'):
        lines.append(f'{metric},rated_responses,{n},{mean}')
        lines.extend(f'{metric},{i + 1},{v},' for i, v in enumerate(counts))
    lines.extend(f'issues,{issue},{n if issue == "none" else 0},' for issue in report.ISSUES)
    return '\n'.join(lines) + '\n'


class DashboardTest(unittest.TestCase):
    def test_weighted_rating_distribution(self):
        records = [report.parse(fixture()), report.parse(fixture((1, 0, 0, 0, 0)))]
        self.assertEqual(report.aggregate(records)['ease'], [1, 0, 0, 0, 2])
        self.assertIn('Mean: 3.67 / 5', report.render(records))

    def test_missing_and_duplicate_metrics_rejected(self):
        for text in (fixture().replace('ease,1,0,\n', ''), fixture() + 'ease,1,0,\n'):
            with self.assertRaises(ValueError):
                report.parse(text)

    def test_bad_totals_means_and_unknown_data_rejected(self):
        for text in (fixture().replace('completed,total,2,', 'completed,total,3,'),
                     fixture().replace('rated_responses,2,5.0', 'rated_responses,2,NaN'),
                     fixture() + 'email,private@example.com,1,\n',
                     fixture().replace('beta-feedback-1', 'beta-feedback-2')):
            with self.assertRaises(ValueError):
                report.parse(text)

    def test_empty_ratings_are_not_zero_scores(self):
        page = report.render([report.parse(fixture((0, 0, 0, 0, 0)))])
        self.assertIn('Mean: Not available', page)
        self.assertNotIn('<script', page)
        self.assertNotIn('https://', page)


if __name__ == '__main__':
    unittest.main()
