#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 위험 명령 감지 및 사용자 승인 요청
#
# Claude Code가 bash 명령을 실행하기 전에 자동 실행됩니다.
# 위험한 명령이 감지되면 사용자에게 친절하게 설명하고 승인을 구합니다.
# ============================================================
set -uo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

LOG_DIR="$HOME/.claude/security-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).jsonl"

# ── 패턴 정의 ───────────────────────────────────────────────

DESTRUCTIVE_PATTERNS=(
    'rm -rf'
    'rm -r '
    'rm --recursive'
    '^rm '
    'rmdir'
    'mkfs\.'
    'dd if=.* of=/dev/'
    '> /dev/sd'
    'format [cCdD]:'
    ':(){.*:;};'
    'truncate -s 0'
    '> /dev/null 2>&1 &.*rm'
)

PRIVILEGE_PATTERNS=(
    'sudo '
    'su -'
    'su root'
    'chmod 777'
    'chmod -R 777'
    'chmod u\+s'
    'chmod g\+s'
    'chown root'
    'chown -R root'
    '^passwd( |$)'
    'visudo'
    'usermod'
    'useradd'
    'groupadd'
)

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
    'ssh -R '
    'ssh .*-D '
    'scp .* .*@'
    'rsync .* .*@'
    'sftp '
    'ftp '
    'telnet '
)

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
    'pip install git\+http'
    'npm install https\?://'
)

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

DB_PATTERNS=(
    'DROP TABLE'
    'DROP DATABASE'
    'DROP SCHEMA'
    'TRUNCATE TABLE'
    'DELETE FROM .* WHERE 1'
    'DELETE FROM [^W]*$'
    'UPDATE .* SET .* WHERE 1'
    'mongoexport'
    'mongodump.*--host'
    'pg_dump.*--host'
    'mysqldump.*-h '
)

PROCESS_PATTERNS=(
    'kill -9'
    'killall'
    'pkill'
    'systemctl stop'
    'systemctl disable'
    'service .* stop'
    'crontab -r'
    'crontab -e'
    'nohup.*&'
)

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

# ── 승인 파일 설정 ──────────────────────────────────────────

APPROVAL_DIR="$HOME/.claude/security-approvals"
mkdir -p "$APPROVAL_DIR"

# 5분 이상 된 승인 파일 자동 정리
find "$APPROVAL_DIR" -mmin +0.5 -delete 2>/dev/null || true

# 명령어 해시 생성 (POSIX 표준 cksum 사용)
APPROVAL_KEY=$(printf '%s' "$COMMAND" | cksum | awk '{print $1}')
APPROVAL_FILE="$APPROVAL_DIR/$APPROVAL_KEY"

# ── 로그 함수 ────────────────────────────────────────────────

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

# ── 경고 및 승인 요청 함수 ──────────────────────────────────

ask_approval() {
    local category="$1"
    local friendly_name="$2"
    local explanation="$3"
    local checklist="$4"
    local pattern="$5"

    # 승인 파일이 있으면 → 사용자가 이미 확인하고 진행 승인한 것
    if [ -f "$APPROVAL_FILE" ]; then
        rm -f "$APPROVAL_FILE"
        log_json "APPROVED" "$category" "$COMMAND" "$pattern"
        exit 0
    fi

    # 승인 파일 없음 → 경고만 출력하고 차단
    # 승인 파일은 Claude가 사용자 확인 후 직접 생성해야 함 (자동 생성 금지)
    log_json "WARNED" "$category" "$COMMAND" "$pattern"

    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "🔴  잠깐요! 위험할 수 있는 작업이 감지되었습니다." >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2
    echo "📋  작업 유형: $friendly_name" >&2
    echo "" >&2
    echo "⚠️   왜 위험한가요?" >&2
    echo "$explanation" | while IFS= read -r line; do echo "    $line" >&2; done
    echo "" >&2
    echo "✅  진행해도 되는지 확인해 주세요:" >&2
    echo "$checklist" | while IFS= read -r line; do echo "    $line" >&2; done
    echo "" >&2
    echo "💻  감지된 명령:" >&2
    echo "    $COMMAND" >&2
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "❓  진행하려면 저에게 '그래도 진행해줘'라고 말씀해주세요." >&2
    echo "🔑  APPROVAL_TOKEN:$APPROVAL_FILE" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

    exit 2
}

# ── 검사 함수 ────────────────────────────────────────────────

check_patterns() {
    local category="$1"
    local friendly_name="$2"
    local explanation="$3"
    local checklist="$4"
    shift 4
    local patterns=("$@")

    for pattern in "${patterns[@]}"; do
        if echo "$COMMAND" | grep -qEi "$pattern"; then
            ask_approval "$category" "$friendly_name" "$explanation" "$checklist" "$pattern"
        fi
    done
}

# ── 검사 실행 ────────────────────────────────────────────────

check_patterns \
    "파괴적 명령" \
    "파일 / 폴더 영구 삭제" \
    "한번 삭제되면 휴지통에도 남지 않고 영구적으로 사라집니다.
중요한 코드, 문서, 이미지 등이 복구 불가능하게 없어질 수 있어요.
실수로 잘못된 폴더를 지우면 몇 달치 작업이 한순간에 날아갈 수 있습니다." \
    "- 삭제하려는 경로가 정확한지 확인하셨나요?
- 이 파일/폴더가 다른 곳에도 백업되어 있나요?
- 팀원이 사용 중인 파일은 아닌가요?" \
    "${DESTRUCTIVE_PATTERNS[@]}"

check_patterns \
    "권한 상승" \
    "시스템 관리자(루트) 권한 획득" \
    "컴퓨터의 모든 파일, 설정, 다른 사용자 계정까지 마음대로 바꿀 수 있는 최고 권한을 얻으려 합니다.
이 권한으로 잘못된 명령이 실행되면 운영체제 전체가 망가질 수 있고,
악성 프로그램이 관리자 권한을 얻는 경우 컴퓨터 전체가 탈취될 수 있습니다." \
    "- 관리자 권한이 꼭 필요한 작업인지 확인하셨나요?
- Claude가 왜 이 권한을 요청하는지 이해가 되시나요?
- 이해가 안 된다면 진행하지 마시고 팀의 개발자에게 문의하세요." \
    "${PRIVILEGE_PATTERNS[@]}"

check_patterns \
    "시스템 파일 접근" \
    "운영체제 핵심 파일 접근" \
    "컴퓨터가 정상적으로 켜지고 동작하는 데 꼭 필요한 시스템 파일에 접근하려 합니다.
이 파일들이 잘못 수정되면 컴퓨터가 부팅조차 안 될 수 있고,
사용자 계정 정보, 비밀번호, 네트워크 설정 등이 노출될 위험이 있습니다." \
    "- 이 시스템 파일에 접근해야 하는 명확한 이유가 있나요?
- 개발 작업에 왜 시스템 파일이 필요한지 이해가 되시나요?
- 이해가 안 된다면 진행하지 마시고 팀의 개발자에게 문의하세요." \
    "${SYSTEM_FILE_PATTERNS[@]}"

check_patterns \
    "네트워크 유출" \
    "내 컴퓨터 데이터를 외부 서버로 전송" \
    "내 컴퓨터 안의 파일이나 정보를 인터넷을 통해 외부로 보내려 합니다.
코드, 설정 파일, API 키, 개인정보 등 민감한 데이터가 의도치 않게 유출될 수 있어요.
한번 외부로 나간 데이터는 회수가 불가능합니다." \
    "- 데이터를 전송하는 대상 서버가 신뢰할 수 있는 곳인지 확인하셨나요?
- 전송되는 내용에 비밀번호, API 키, 개인정보가 포함되어 있지 않나요?
- 이 전송이 작업에 꼭 필요한 과정인지 이해가 되시나요?" \
    "${EXFIL_PATTERNS[@]}"

check_patterns \
    "시크릿 노출" \
    "비밀번호 / API 키 화면 출력" \
    "API 키, 비밀번호, 인증 토큰 등 절대 외부에 노출되면 안 되는 정보를 화면에 출력하려 합니다.
화면에 출력된 정보는 로그, 화면 공유, 스크린샷 등을 통해 의도치 않게 유출될 수 있어요.
유출된 API 키로 과금 폭탄이나 서비스 탈취가 발생한 사례가 많습니다." \
    "- 지금 화면을 공유 중이거나 녹화 중은 아닌가요?
- 이 정보를 꼭 화면에 출력해야 하는 이유가 있나요?
- 확인 후에는 즉시 터미널 내용을 지워주세요 (clear 명령어)." \
    "${SECRET_PATTERNS[@]}"

check_patterns \
    "위험한 패키지 설치" \
    "출처가 불분명한 프로그램 설치" \
    "공식 패키지 저장소(npm, pip 등)가 아닌 검증되지 않은 곳에서 프로그램을 설치하려 합니다.
악성 코드가 포함된 프로그램이 설치될 수 있고, 설치 즉시 컴퓨터가 해킹될 수 있어요.
인터넷에서 복사한 설치 명령어를 그대로 실행하는 것은 매우 위험합니다." \
    "- 이 패키지의 출처가 공식 사이트인지 확인하셨나요?
- 이 명령어가 어디서 왔는지 알고 계신가요?
- 모르는 출처라면 팀의 개발자에게 먼저 확인을 받으세요." \
    "${INSTALL_PATTERNS[@]}"

check_patterns \
    "Git 위험 작업" \
    "코드 기록 삭제 / 팀원 작업 강제 덮어쓰기" \
    "Git은 팀원들의 모든 코드 변경 기록을 관리하는 시스템입니다.
이 작업은 팀원들이 작업한 코드를 강제로 지우거나 덮어써서 영구적으로 사라지게 할 수 있어요.
한 번 강제로 덮어쓰면 팀원들의 몇 주치 작업이 사라지고 복구가 매우 어렵습니다." \
    "- 팀원들에게 이 작업을 알렸나요?
- 현재 작업 중인 팀원이 있지는 않나요?
- 정말 코드 기록을 되돌리거나 삭제해야 하는 상황인가요?
- 확실하지 않다면 팀의 개발자에게 먼저 확인하세요." \
    "${GIT_PATTERNS[@]}"

check_patterns \
    "데이터베이스 파괴" \
    "데이터베이스 데이터 삭제 / 테이블 제거" \
    "앱이나 서비스에서 사용하는 실제 데이터(회원 정보, 주문 내역, 게시글 등)를 삭제하려 합니다.
운영 중인 서비스의 DB를 건드리면 서비스 전체가 중단되고 데이터 복구가 불가능할 수 있어요.
특히 WHERE 조건 없는 삭제는 테이블의 모든 데이터를 한꺼번에 날릴 수 있습니다." \
    "- 지금 연결된 DB가 실제 운영 서버(프로덕션)인가요, 테스트 서버인가요?
- 삭제하려는 데이터의 백업이 있나요?
- 이 작업이 서비스에 영향을 주지 않는다고 확신하시나요?
- 확실하지 않다면 반드시 팀의 개발자에게 확인하세요." \
    "${DB_PATTERNS[@]}"

check_patterns \
    "프로세스 조작" \
    "실행 중인 프로그램 강제 종료 / 시스템 설정 변경" \
    "현재 실행 중인 서버, 앱, 시스템 서비스를 강제로 끄거나 설정을 바꾸려 합니다.
운영 중인 서비스가 갑자기 종료되면 사용자들이 서비스를 이용하지 못하게 되고,
자동 실행 설정(크론잡 등)을 잘못 바꾸면 정기적으로 돌아야 할 작업이 멈출 수 있어요." \
    "- 종료하려는 프로그램이 현재 서비스 중인 프로그램은 아닌가요?
- 이 프로그램을 끄면 어떤 영향이 생기는지 파악하고 계신가요?
- 팀원들에게 미리 알렸나요?" \
    "${PROCESS_PATTERNS[@]}"

check_patterns \
    "인코딩 우회" \
    "암호화되거나 숨겨진 명령 실행 시도" \
    "사람이 읽기 어렵게 인코딩되거나 숨겨진 명령을 실행하려 합니다.
악성 코드가 이런 방식으로 숨겨지는 경우가 많고, 무엇을 실행하는지 파악이 어렵습니다.
인터넷에서 복사해온 명령어가 이런 형태라면 해킹 시도일 가능성이 있어요." \
    "- 이 명령어가 어디서 왔는지 알고 계신가요?
- 명령어가 무엇을 하는지 이해하고 계신가요?
- 출처를 모르거나 내용이 이해되지 않는다면 절대 실행하지 마세요.
- 팀의 개발자에게 먼저 확인을 받으세요." \
    "${OBFUSCATION_PATTERNS[@]}"

# ── 통과 ─────────────────────────────────────────────────────

log_json "ALLOWED" "-" "$COMMAND"
exit 0
