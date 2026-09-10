#!/usr/bin/env bash
set -euo pipefail

project_file="macos/Runner.xcodeproj/project.pbxproj"
test -f "$project_file"

# The release workflow supplies CODE_SIGNING_ALLOWED=NO and CODE_SIGNING_REQUIRED=NO.
# This guard rejects only actual upstream signing coupling, not empty local fields.
python3 - "$project_file" <<'PY'
from pathlib import Path
import sys

project = Path(sys.argv[1]).read_text(encoding="utf-8")
for forbidden in ("DEVELOPMENT_TEAM = 28W", "match AppStore", "com.anxcye"):
    if forbidden in project:
        raise SystemExit(f"forbidden signing coupling remains: {forbidden}")
print("macOS unsigned-build configuration verified")
PY
