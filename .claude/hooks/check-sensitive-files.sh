#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 민감 파일 편집 차단 (PreToolUse → Edit|Write|MultiEdit)
#
# Claude Code가 파일을 편집/생성하기 전에 자동 실행됩니다.
# 민감한 파일을 수정하려 하면 exit 2로 차단합니다.
# ============================================================
set -euo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '
    .tool_input.file_path // 
    .tool_input.path // 
    ""
')

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

LOG_DIR="$HOME/.claude/security-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

log_json() {
    local status="$1"
    local category="$2"
    local file="$3"
    local pattern="${4:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    
    jq -n -c \
        --arg ts "$timestamp" \
        --arg st "$status" \
        --arg cat "$category" \
        --arg file "$file" \
        --arg pat "$pattern" \
        --arg user "${USER:-unknown}" \
        '{timestamp: $ts, status: $st, category: $cat, file: $file, pattern: $pat, user: $user}' \
        >> "$LOG_FILE"
}

# ── 보호 대상 파일 패턴 ──────────────────────────────────────

PROTECTED_PATTERNS=(
    '\.env$'
    '\.env\.'
    '\.pem$'
    '\.key$'
    '\.p12$'
    '\.pfx$'
    '\.crt$'
    '\.cer$'
    '\.secret$'
    'credentials'
    '\.netrc'
    '\.npmrc'
    '\.pypirc'
    '\.docker/config\.json'
    '\.ssh/'
    'id_rsa'
    'id_ed25519'
    'id_ecdsa'
    'authorized_keys'
    'known_hosts'
    '\.aws/'
    '\.gcloud/'
    '\.azure/'
    '\.kube/config'
    'kubeconfig'
    'docker-compose.*\.yml'
    'Dockerfile'
    '\.terraform/'
    'terraform\.tfstate'
    'terraform\.tfvars'
    'package-lock\.json$'
    'yarn\.lock$'
    'pnpm-lock\.yaml$'
    'Pipfile\.lock$'
    'poetry\.lock$'
    '\.gitignore$'
    '\.gitmodules$'
    '\.git/config'
    '\.github/workflows/'
    '\.gitlab-ci\.yml'
    'Jenkinsfile'
    '\.circleci/'
    'kakao.*config'
    'kakao.*secret'
    'firebase.*\.json'
)

# ── 검사 ─────────────────────────────────────────────────────

for pattern in "${PROTECTED_PATTERNS[@]}"; do
    if echo "$FILE_PATH" | grep -qEi "$pattern"; then
        log_json "BLOCKED" "민감파일편집" "$FILE_PATH" "$pattern"
        
        echo "🔴 [KM Security] 보호 대상 파일 편집 차단: $FILE_PATH" >&2
        echo "이 파일은 보안 정책에 의해 Claude Code의 직접 편집이 제한됩니다." >&2
        echo "직접 편집이 필요하면 수동으로 수정해주세요." >&2
        exit 2
    fi
done

# ── 통과 ─────────────────────────────────────────────────────

log_json "ALLOWED" "파일편집" "$FILE_PATH"

exit 0
