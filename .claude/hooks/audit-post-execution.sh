#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 실행 감사 로그 (PostToolUse → Bash)
#
# 명령이 실행된 후 결과를 로깅합니다.
# 차단하지 않고 기록만 합니다 (감사 추적용).
# ============================================================
set -euo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))")
EXIT_CODE=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_output',{}).get('exit_code','unknown'))")
# stdout은 길 수 있으므로 앞 500자만 기록
STDOUT_PREVIEW=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_output',{}).get('stdout','')[:500])")

LOG_DIR="$HOME/.claude/security-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')

python3 -c "
import json, sys
entry = {
    'timestamp': sys.argv[1],
    'status': 'EXECUTED',
    'category': '감사로그',
    'command': sys.argv[2],
    'exit_code': sys.argv[3],
    'output_preview': sys.argv[4],
    'user': sys.argv[5],
    'cwd': sys.argv[6],
}
print(json.dumps(entry, ensure_ascii=False))
" "$timestamp" "$COMMAND" "$EXIT_CODE" "$STDOUT_PREVIEW" "${USER:-unknown}" "${PWD:-unknown}" >> "$LOG_FILE"

exit 0
