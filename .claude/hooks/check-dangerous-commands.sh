#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 위험 명령 차단 (PreToolUse → Bash)
# 
# Claude Code가 bash 명령을 실행하기 전에 자동 실행됩니다.
# 위험한 명령이 감지되면 exit 2로 차단합니다.
# ============================================================
set -euo pipefail

# stdin으로 JSON 입력 받기
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# 로그 기록 (선택)
LOG_DIR="$HOME/.claude/security-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

# ── 차단 패턴 정의 ──────────────────────────────────────────
# severity: CRITICAL(즉시 차단), HIGH(차단+경고), MEDIUM(경고 로그)

# 1. 파괴적 명령 [CRITICAL]
DESTRUCTIVE_PATTERNS=(
    'rm -rf /'
    'rm -rf ~'
    'rm -rf \.'
    'rm -rf \*'
    'rm -rf --no-preserve-root'
    'mkfs\.'
    'dd if=.* of=/dev/'
    '> /dev/sd'
    'format [cCdD]:'
    ':(){.*:;};'                 # fork bomb
    'truncate -s 0'
    '> /dev/null 2>&1 &.*rm'    # 백그라운드 삭제 은닉
)

# 2. 권한 상승 [CRITICAL]
PRIVILEGE_PATTERNS=(
    'sudo '
    'su -'
    'su root'
    'chmod 777'
    'chmod -R 777'
    'chmod u\+s'                # setuid
    'chmod g\+s'                # setgid
    'chown root'
    'chown -R root'
    'passwd'
    'visudo'
    'usermod'
    'useradd'
    'groupadd'
)

# 3. 시스템 파일 접근 [CRITICAL]
SYSTEM_FILE_PATTERNS=(
    '/etc/passwd'
    '/etc/shadow'
    '/etc/sudoers'
    '/etc/crontab'
    '/etc/ssh/'
    '/etc/hosts'
    '/etc/resolv\.conf'
    '~/.ssh/'
    '\.ssh/id_'
    '\.ssh/authorized_keys'
    '\.bash_history'
    '\.zsh_history'
    '/var/log/'
    '/proc/'
    '/sys/'
)

# 4. 네트워크 유출 [CRITICAL]
EXFIL_PATTERNS=(
    'curl .* -d '
    'curl .* --data'
    'curl .* -F '
    'curl .* --upload'
    'curl .* -T '
    'curl .* --request PUT'
    'curl .* --request POST'
    'curl .* --request PATCH'
    'wget .* --post'
    'nc -e'
    'nc .*-c '
    'ncat -e'
    'ncat .*-c '
    'bash -i >& /dev/tcp/'
    'python.*socket.*connect'
    'python.*http\.server'
    'python.*SimpleHTTPServer'
    'ngrok'
    'ssh -R '                    # 리버스 터널
    'ssh .*-D '                  # SOCKS 프록시
    'scp .* .*@'                 # 원격 전송
    'rsync .* .*@'
    'sftp '
    'ftp '
    'telnet '
)

# 5. 환경변수/시크릿 노출 [HIGH]
SECRET_PATTERNS=(
    '^printenv'
    '^env \|'
    '^env$'
    '^set \|'
    'echo \$\(env\)'
    '^cat .*\.env$'
    '^cat .*\.env\.'
    '^cat .*\.pem$'
    '^cat .*\.key$'
    '^cat .*\.p12$'
    '^cat .*\.pfx$'
    '^cat .*credentials'
    '^cat .*\.secret$'
    '^cat .*\.netrc'
    '^cat .*\.npmrc'
    '^cat .*\.pypirc'
    'AWS_SECRET_ACCESS_KEY'
    'ANTHROPIC_API_KEY'
    'OPENAI_API_KEY'
    'GOOGLE_API_KEY'
    'KAKAO_.*_KEY'
    'DB_PASSWORD'
    'DATABASE_URL.*password'
    'PRIVATE_KEY'
    'JWT_SECRET'
    'TOKEN'
)

# 6. 패키지 설치 (검증 안 된 소스) [HIGH]
INSTALL_PATTERNS=(
    'pip install .*--index-url'
    'pip install .*-i http'
    'pip install .*--extra-index'
    'pip install .*--trusted-host'
    'npm install .*--registry'
    'yarn add .*--registry'
    'curl .* | bash'
    'curl .* | sh'
    'curl .* | python'
    'wget .* | bash'
    'wget .* | sh'
    'wget .* | python'
    'pip install git\+http'       # Git URL 직접 설치
    'npm install https\?://'      # URL 직접 설치
)

# 7. Git 위험 작업 [HIGH]
GIT_PATTERNS=(
    'git push.*--force'
    'git push.*-f '
    'git reset --hard'
    'git clean -fd'
    'git checkout -- \.'
    'git branch -D '
    'git rebase.*--force'
    'git filter-branch'
    'git push.*--delete'
    'git push.*--mirror'
)

# 8. 데이터베이스 파괴 [CRITICAL]
DB_PATTERNS=(
    'DROP TABLE'
    'DROP DATABASE'
    'DROP SCHEMA'
    'TRUNCATE TABLE'
    'DELETE FROM .* WHERE 1'
    'DELETE FROM [^W]*$'           # WHERE 없는 DELETE
    'UPDATE .* SET .* WHERE 1'
    'mongoexport'
    'mongodump.*--host'
    'pg_dump.*--host'
    'mysqldump.*-h '
)

# 9. 프로세스/서비스 조작 [HIGH]
PROCESS_PATTERNS=(
    'kill -9'
    'killall'
    'pkill'
    'systemctl stop'
    'systemctl disable'
    'service .* stop'
    'crontab -r'
    'crontab -e'                  # 크론잡 변경
    'at '                         # 예약 실행
    'nohup.*&'                    # 백그라운드 지속 실행
)

# 10. 인코딩 우회 시도 [CRITICAL]
OBFUSCATION_PATTERNS=(
    'base64 -d'
    'base64 --decode'
    'echo .* | base64 -d | bash'
    'echo .* | base64 -d | sh'
    'python.*-c.*exec.*base64'
    'python.*-c.*import.*os'
    'perl -e'
    'ruby -e'
    'eval \$\('
    '\$\(echo .* | xxd'
    'printf.*\\\\x'
)

# ── 검사 함수 ────────────────────────────────────────────────

log_json() {
    local status="$1"
    local category="$2"
    local cmd="$3"
    local pattern="${4:-}"
    local timestamp
    timestamp=$(date '+%Y-%m-%dT%H:%M:%S%z')
    
    jq -n -c \
        --arg ts "$timestamp" \
        --arg st "$status" \
        --arg cat "$category" \
        --arg cmd "$cmd" \
        --arg pat "$pattern" \
        --arg user "${USER:-unknown}" \
        --arg pwd "${PWD:-unknown}" \
        '{timestamp: $ts, status: $st, category: $cat, command: $cmd, pattern: $pat, user: $user, cwd: $pwd}' \
        >> "$LOG_FILE"
}

check_patterns() {
    local category="$1"
    shift
    local patterns=("$@")
    
    for pattern in "${patterns[@]}"; do
        if echo "$COMMAND" | grep -qEi "$pattern"; then
            log_json "BLOCKED" "$category" "$COMMAND" "$pattern"
            
            echo "🔴 [KM Security] $category 위험 감지 - 명령어가 차단되었습니다: $pattern" >&2
            exit 2
        fi
    done
}

# ── 순차 검사 실행 ────────────────────────────────────────────

check_patterns "파괴적 명령"        "${DESTRUCTIVE_PATTERNS[@]}"
check_patterns "권한 상승"          "${PRIVILEGE_PATTERNS[@]}"
check_patterns "시스템 파일 접근"   "${SYSTEM_FILE_PATTERNS[@]}"
check_patterns "네트워크 유출"      "${EXFIL_PATTERNS[@]}"
check_patterns "시크릿 노출"        "${SECRET_PATTERNS[@]}"
check_patterns "위험한 패키지 설치" "${INSTALL_PATTERNS[@]}"
check_patterns "Git 위험 작업"      "${GIT_PATTERNS[@]}"
check_patterns "데이터베이스 파괴"  "${DB_PATTERNS[@]}"
check_patterns "프로세스 조작"      "${PROCESS_PATTERNS[@]}"
check_patterns "인코딩 우회"        "${OBFUSCATION_PATTERNS[@]}"

# ── 통과 ─────────────────────────────────────────────────────

# 로그 (정상 통과)
log_json "ALLOWED" "-" "$COMMAND"

exit 0
