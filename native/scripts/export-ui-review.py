#!/usr/bin/env python3
"""Keep named UI previews small enough to review without a full xcresult download."""
import json
import shutil
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=True)
for item in json.loads((source / 'manifest.json').read_text()):
    for attachment in item.get('attachments', []):
        name = attachment.get('suggestedHumanReadableName', '')
        if name.endswith('.png') or attachment.get('exportedFileName', '').endswith('.txt'):
            filename = attachment.get('exportedFileName')
            if filename and (source / filename).is_file():
                shutil.copy2(source / filename, destination / Path(name).name)
