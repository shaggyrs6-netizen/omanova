"""Local build identity; no settings, network access or process-argument locations."""
import json
from pathlib import Path
import re
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent


def identity(root=ROOT):
    result = {"version": "unknown", "build": "release", "revision": ""}
    try:
        version = json.loads((root / 'manifest.json').read_text()).get('version')
        if isinstance(version, str) and re.fullmatch(r'\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?', version):
            result['version'] = version
    except (OSError, ValueError, AttributeError):
        pass
    try:
        revision = json.loads((root / '.omanova-build.json').read_text()).get('revision')
        if isinstance(revision, str) and re.fullmatch(r'[0-9a-f]{40}', revision):
            result['revision'] = revision
    except (OSError, ValueError, AttributeError):
        pass
    return result


def record(root=ROOT):
    """Called by setup after dependency verification, before the first snapshot."""
    revision = os.environ.get('OMANOVA_SOURCE_REVISION', '')
    if not revision and (root / '.git').exists():
        revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    if not revision and (root / 'SOURCE-COMMIT.txt').is_file():
        revision = (root / 'SOURCE-COMMIT.txt').read_text().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('No valid source revision. Use the guided installer or a complete release archive.')
    with tempfile.NamedTemporaryFile(mode='w', dir=root, prefix='.omanova-build.', delete=False) as f:
        json.dump({'revision': revision}, f)
        temporary = f.name
    os.replace(temporary, root / '.omanova-build.json')


if __name__ == '__main__':
    import sys
    if sys.argv[1:] != ['--record']:
        raise SystemExit('Usage: runtime_identity.py --record')
    try:
        record()
    except (OSError, ValueError, subprocess.SubprocessError):
        raise SystemExit('Could not record source identity; use the matching guided installer/archive.')
