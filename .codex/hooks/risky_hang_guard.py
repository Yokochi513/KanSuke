# ~/.codex/hooks/risky_hang_guard.py
import json
import re
import sys

RISKY_PATTERNS = [
    r"flutter\s+pub\s+(add|get)",
    r"\b(npm|yarn|pnpm)\s+(install|add)\b",
    r"\bpip\s+install\b",
    r"\bgit\s+clone\b",
    r"\bdocker\s+build\b",
    r"\bgradle\b",
    r"\bpod\s+install\b",
]
TIMEOUT_MARKERS = [
    r"\btimeout\s+\d",
    r"Start-Job\s+.*-Timeout",
    r"timeout_ms",
]

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "") or data.get("input", {}).get(
    "command", ""
)

is_risky = any(re.search(p, cmd, re.I) for p in RISKY_PATTERNS)
has_timeout = any(re.search(p, cmd, re.I) for p in TIMEOUT_MARKERS)

if is_risky and not has_timeout:
    print(
        json.dumps(
            {
                "permissionDecision": "deny",
                "reason": (
                    "このコマンドはハングする可能性があります。"
                    "timeout(または Start-Job -Timeout)で包んで再実行してください。"
                ),
            }
        )
    )
    sys.exit(0)

sys.exit(0)  # 何も出力しなければ許可
