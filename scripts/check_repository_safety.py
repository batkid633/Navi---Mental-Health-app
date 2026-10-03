#!/usr/bin/env python3
"""Offline Git-content guard. Prints paths/categories only, never secret values.

This bounded pattern scan is not a credential-validity or full-history audit.
Run before staging/pushing; a nonzero exit requires review.
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def git(*args):
    return subprocess.check_output(['git', '-C', str(ROOT), *args])


def main():
    tracked = {p for p in git('ls-files', '-z').decode().split('\0') if p}
    untracked = {p for p in git('ls-files', '--others', '--exclude-standard', '-z').decode().split('\0') if p}
    findings = set()
    private = re.compile(r'(^|/)(?:\.env(?:\..*)?|credentials|tokens|user_runtime_data|recovery_artifacts)(/|$)|\.(?:p12|p8|mobileprovision|provisionprofile)$')
    signatures = {
        'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        'OpenAI-shaped token': rb'sk-(?:proj-)?[A-Za-z0-9_-]{32,}',
        'GitHub-shaped token': rb'gh[pousr]_[A-Za-z0-9]{30,}',
        'AWS-shaped access key': rb'AKIA[0-9A-Z]{16}',
    }
    for name in sorted(tracked | untracked):
        path = ROOT / name
        if private.search(name) and not name.endswith(('.example', '.template')):
            findings.add(('private path', name))
        if name.startswith('backend/logs/') and name.endswith(('.csv', '.jsonl')):
            findings.add(('runtime log', name))
        if not path.is_file() or path.is_symlink():
            continue
        if path.stat().st_size > 10_000_000:
            findings.add(('file exceeds scan size limit; manual review', name))
            continue
        contents = path.read_bytes()
        for label, pattern in signatures.items():
            if re.search(pattern, contents):
                findings.add((label, name))
    # Known historical issue: a clean worktree does not clear earlier tokens.
    historical = git('log', '--all', '--format=%h', '--', 'navi_ml/tokens/whoop_tokens.json').decode().splitlines()
    for commit in historical:
        result = subprocess.run(['git', '-C', str(ROOT), 'show', f'{commit}:navi_ml/tokens/whoop_tokens.json'], capture_output=True)
        if result.returncode == 0 and re.search(rb'"(?:access_token|refresh_token)"\s*:\s*"[^"\s]+"', result.stdout):
            findings.add(('historical token fields', f'{commit}:navi_ml/tokens/whoop_tokens.json'))
    for label, name in sorted(findings):
        print(f'REVIEW: {label}: {name}')
    print(f'Checked {len(tracked | untracked)} current paths and known WHOOP token history; values not printed.')
    print('Firebase client configuration is retained. Unknown token formats and other historical paths require separate review.')
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
