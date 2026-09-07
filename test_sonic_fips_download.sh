#!/usr/bin/env bash
set -Eeuo pipefail

python3 - <<'PY'
from pathlib import Path
text = Path('/data/sonic/sonic-dzf-time-measure/src/sonic-fips/Makefile').read_text()
assert 'tmp="$(DEST)/$$target.tmp"' in text
assert 'SKIP_BUILD_HOOK=y wget -O "$$tmp" "$$url"' in text
assert 'test -s "$$tmp"' in text
assert 'mv "$$tmp" "$(DEST)/$$target"' in text
assert 'curl -f -o "$(DEST)/$$target"' not in text
assert 'touch "$(DEST)/$$target"' not in text
PY
