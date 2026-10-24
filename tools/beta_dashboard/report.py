"""Offline survey aggregation. Standard library only; no network or app imports."""
import argparse
import csv
import html
import io
import math
from pathlib import Path

VERSION = 'beta-feedback-1'
ISSUES = ('none', 'navigation', 'audio', 'insights', 'health_sync', 'other')


def parse(text):
    rows = list(csv.reader(io.StringIO(text.lstrip('\ufeff'))))
    if not rows or rows.pop(0) != ['metric', 'category', 'count', 'mean']:
        raise ValueError('Unexpected CSV header')
    values = {}
    for row in rows:
        if not row:
            continue
        if len(row) != 4:
            raise ValueError('Every row must have four fields')
        key = tuple(row[:2])
        if key in values:
            raise ValueError('Duplicate metric row')
        values[key] = row[2:]
    expected = {('schema_version', VERSION)}
    expected.update((k, 'total') for k in ('completed', 'skipped', 'recorded_days'))
    expected.update((k, str(i)) for k in ('ease', 'helpfulness') for i in range(1, 6))
    expected.update((k, 'rated_responses') for k in ('ease', 'helpfulness'))
    expected.update(('issues', k) for k in ISSUES)
    if set(values) != expected or values[('schema_version', VERSION)] != ['', '']:
        raise ValueError('Missing, unknown, or incompatible schema/metrics')

    def count(key):
        raw, mean = values[key]
        if not raw.isascii() or not raw.isdecimal() or len(raw) > 9:
            raise ValueError('Counts must be nonnegative integers below one billion')
        if key[1] != 'rated_responses' and mean:
            raise ValueError('Unexpected mean')
        return int(raw)

    result = {k: count((k, 'total')) for k in ('completed', 'skipped', 'recorded_days')}
    if result['completed'] + result['skipped'] != result['recorded_days']:
        raise ValueError('Day totals do not reconcile')
    for metric in ('ease', 'helpfulness'):
        counts = [count((metric, str(i))) for i in range(1, 6)]
        n = count((metric, 'rated_responses'))
        if sum(counts) != n or n > result['completed']:
            raise ValueError('Rating denominators do not reconcile')
        mean = values[(metric, 'rated_responses')][1]
        if n:
            calculated = sum((i + 1) * v for i, v in enumerate(counts)) / n
            if not math.isclose(float(mean), calculated, abs_tol=1e-8):
                raise ValueError('Mean disagrees with rating distribution')
        elif mean:
            raise ValueError('Unrated metric must have an empty mean')
        result[metric] = counts
    result['issues'] = [count(('issues', issue)) for issue in ISSUES]
    if sum(result['issues']) != result['completed']:
        raise ValueError('Issue totals do not reconcile')
    return result


def aggregate(records):
    totals = {k: sum(r[k] for r in records) for k in ('completed', 'skipped', 'recorded_days')}
    for metric in ('ease', 'helpfulness', 'issues'):
        length = 6 if metric == 'issues' else 5
        totals[metric] = [sum(r[metric][i] for r in records) for i in range(length)]
    return totals


def render(records):
    totals = aggregate(records)
    sections = []
    for metric, title in (('ease', 'Ease of use'), ('helpfulness', 'Perceived helpfulness'), ('issues', 'Main reported issue')):
        counts = totals[metric]
        n = sum(counts)
        labels = ISSUES if metric == 'issues' else [str(i) + ' / 5' for i in range(1, 6)]
        summary = f'{n} responses'
        if metric != 'issues':
            mean = f'{sum((i + 1) * v for i, v in enumerate(counts)) / n:.2f} / 5' if n else 'Not available'
            summary += f' · Mean: {mean} · Not rated: {totals["completed"] - n}'
        bars = ''.join(f'<tr><th>{html.escape(label.replace("_", " "))}</th><td><meter min="0" max="{max(n, 1)}" value="{v}">{v}</meter></td><td>{v}</td><td>{v / n * 100 if n else 0:.1f}%</td></tr>' for label, v in zip(labels, counts))
        sections.append(f'<section><h2>{title}</h2><p>{summary}</p><table><thead><tr><th>Category</th><th>Distribution</th><th>Count</th><th>Percent</th></tr></thead><tbody>{bars}</tbody></table></section>')
    return '''<!doctype html><html lang="en"><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>NAVI beta feedback</title><style>
body{font:17px system-ui,sans-serif;max-width:900px;margin:40px auto;padding:0 24px;color:#173c3c;background:#f5faf8}
section{background:white;border:1px solid #ccdcd6;border-radius:12px;padding:20px;margin:20px 0}
table{width:100%;text-align:left;border-collapse:collapse}td,th{padding:8px}meter{width:100%;height:22px}td:nth-child(2){width:45%}
footer{font-size:14px} @media print{body{background:white;margin:0}section{break-inside:avoid}}
</style><h1>NAVI beta feedback</h1><p>Voluntarily shared, device-local survey summaries</p>''' + f'''
<section><strong>{len(records)} source snapshots · {totals['completed']} completed response-days · {totals['skipped']} skipped response-days</strong>
<p>Source snapshots are not verified unique participants. Each source must contain only its latest cumulative export.</p></section>
''' + ''.join(sections) + '''<footer>
<p>Schema: beta-feedback-1. Means are weighted by rated responses, reconstructed from rating distributions. “Not used” is excluded from each rating denominator. Frequent respondents contribute more observations. Percentages may round.</p>
<p>These are self-selected usability responses, not clinical outcomes, efficacy, retention, or representative population estimates. Days without survey interactions are absent. Exports contain no dates, so this report cannot show time trends. Overlap across different source files cannot be detected reliably.</p>
<p>No source filenames, account identifiers, journal text, or audio are included. This report is a local file, not an authenticated website. Anyone with the file can read it; review small-group counts before sharing.</p>
</footer></html>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--allow-identical', action='store_true', help='Only after confirming identical snapshots are from different sources')
    args = parser.parse_args()
    files = sorted(args.input_dir.glob('*.csv'))
    if not files:
        parser.error('No CSV snapshots found')
    records = []
    for index, path in enumerate(files, 1):
        try:
            if path.stat().st_size > 100_000:
                raise ValueError('Snapshot exceeds expected size')
            record = parse(path.read_text(encoding='utf-8'))
            if record in records and not args.allow_identical:
                raise ValueError('Identical snapshot detected; verify separate sources before using --allow-identical')
            records.append(record)
        except (ValueError, OSError) as error:
            parser.error(f'Input snapshot {index}: {error}')
    if args.output.suffix.lower() != '.html':
        parser.error('Output must be an HTML file')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(records), encoding='utf-8')
    args.output.chmod(0o600)
    print(f'Wrote local dashboard from {len(records)} snapshots. No uploads performed.')


if __name__ == '__main__':
    main()
