#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT=/data/sonic/sonic-dzf-time-measure/src/sonic-build-hooks/scripts/post_run_cleanup
python3 - <<'PY'
from pathlib import Path

text = Path('/data/sonic/sonic-dzf-time-measure/src/sonic-build-hooks/scripts/post_run_cleanup').read_text()
assert '[[ ! ${IMAGENAME} =~ -slave- && ! ${IMAGENAME} =~ ^docker-base- ]]' in text
assert text.count('/usr/bin/apt-get purge -y --auto-remove rsync') == 1
PY
