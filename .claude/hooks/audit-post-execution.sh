#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 실행 감사 로그 (PostToolUse → Bash)
#
# 명령이 실행된 후 결과를 로깅합니다.
# 차단하지 않고 기록만 합니다 (감사 추적용).
# ============================================================
set -euo pipefail

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_output.exit_code // "unknown"')
# stdout은 길 수 있으므로 앞 500자만 기록
STDOUT_PREVIEW=$(echo "$INPUT" | jq -r '.tool_output.stdout // ""' | head -c 500)

LOG_DIR="$HOME/.claude/security-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')

jq -n -c \
    --arg ts "$timestamp" \
    --arg st "EXECUTED" \
    --arg cat "감사로그" \
    --arg cmd "$COMMAND" \
    --arg exit "$EXIT_CODE" \
    --arg out "$STDOUT_PREVIEW" \
    --arg user "${USER:-unknown}" \
    --arg pwd "${PWD:-unknown}" \
    '{timestamp: $ts, status: $st, category: $cat, command: $cmd, exit_code: $exit, output_preview: $out, user: $user, cwd: $pwd}' \
    >> "$LOG_FILE"

exit 0
