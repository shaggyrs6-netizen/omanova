"""Local build identity; no settings, network access or process-argument locations."""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent


def identity(root=ROOT):
    result = {"version": "unknown", "build": "local usability", "revision": ""}
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
