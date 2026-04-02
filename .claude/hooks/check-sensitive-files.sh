#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 민감 파일 편집 감지 및 사용자 승인 요청
#
# Claude Code가 파일을 편집/생성하기 전에 자동 실행됩니다.
# 민감한 파일을 수정하려 하면 사용자에게 친절하게 설명하고 승인을 구합니다.
# ============================================================
set -uo pipefail

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

APPROVAL_DIR="$HOME/.claude/security-approvals"
mkdir -p "$APPROVAL_DIR"
find "$APPROVAL_DIR" -mmin +0.5 -delete 2>/dev/null || true
APPROVAL_KEY=$(printf 'file:%s' "$FILE_PATH" | cksum | awk '{print $1}')
APPROVAL_FILE="$APPROVAL_DIR/$APPROVAL_KEY"

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

# ── 파일 유형별 설명 ─────────────────────────────────────────

get_file_description() {
    local file="$1"

    case "$file" in
        *\.env*) echo "환경 설정 파일 (.env) — API 키, 비밀번호 등 민감한 정보가 담겨 있어요." ;;
        *\.pem*|*\.key*|*\.p12*|*\.pfx*|*\.crt*|*\.cer*) echo "보안 인증서 / 개인 키 파일 — 서버나 서비스 접근에 사용되는 중요한 보안 파일이에요." ;;
        *credentials*|*\.secret*) echo "인증 정보 파일 — 계정이나 서비스 접근에 필요한 비밀 정보가 담겨 있어요." ;;
        *\.ssh*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*authorized_keys*|*known_hosts*) echo "SSH 키 / 설정 파일 — 서버 접속에 사용되는 보안 키예요. 노출되면 서버가 탈취될 수 있어요." ;;
        *\.aws*|*\.gcloud*|*\.azure*) echo "클라우드 인증 파일 — AWS, Google Cloud, Azure 접속 정보가 담겨 있어요." ;;
        *\.kube*|*kubeconfig*) echo "Kubernetes 설정 파일 — 서버 클러스터 접근 정보가 담겨 있어요." ;;
        *docker-compose*|*Dockerfile*) echo "Docker 설정 파일 — 서버 실행 환경 설정이에요. 잘못 변경되면 서비스가 중단될 수 있어요." ;;
        *terraform*) echo "Terraform 인프라 설정 파일 — 클라우드 인프라 구성 정보예요. 잘못 변경되면 서비스 전체에 영향을 줄 수 있어요." ;;
        *package-lock*|*yarn\.lock*|*pnpm-lock*|*Pipfile\.lock*|*poetry\.lock*) echo "패키지 잠금 파일 — 프로젝트가 사용하는 라이브러리 버전을 고정하는 파일이에요. 변경 시 예상치 못한 오류가 생길 수 있어요." ;;
        *\.gitignore*|*\.gitmodules*|*\.git/config*) echo "Git 설정 파일 — 코드 관리 도구의 핵심 설정이에요." ;;
        *\.github/workflows*|*\.gitlab-ci*|*Jenkinsfile*|*\.circleci*) echo "CI/CD 자동화 파일 — 코드 빌드 및 배포 자동화 설정이에요. 잘못 변경되면 배포가 실패하거나 보안 문제가 생길 수 있어요." ;;
        *kakao*) echo "카카오 설정 파일 — 카카오 서비스 관련 중요 설정이에요." ;;
        *firebase*) echo "Firebase 설정 파일 — Firebase 서비스 접근 정보가 담겨 있어요." ;;
        *\.netrc*|*\.npmrc*|*\.pypirc*) echo "패키지 레지스트리 인증 파일 — 패키지 저장소 로그인 정보가 담겨 있어요." ;;
        *) echo "보안 정책에 의해 보호되는 중요한 파일이에요." ;;
    esac
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

# ── 검사 및 승인 요청 ────────────────────────────────────────

for pattern in "${PROTECTED_PATTERNS[@]}"; do
    if echo "$FILE_PATH" | grep -qEi "$pattern"; then
        FILE_DESC=$(get_file_description "$FILE_PATH")

        echo "" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "🔴  잠깐요! 중요한 파일 수정이 감지되어 중단했어요." >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "" >&2
        echo "📁  수정하려는 파일:" >&2
        echo "    $FILE_PATH" >&2
        echo "" >&2
        echo "⚠️   이 파일은 무엇인가요?" >&2
        echo "    $FILE_DESC" >&2
        echo "" >&2
        echo "🛡️   왜 중단했나요?" >&2
        echo "    이 파일은 보안상 매우 중요합니다. Claude가 실수로" >&2
        echo "    잘못 수정하면 서비스 장애나 보안 사고로 이어질 수 있어요." >&2
        echo "" >&2

        # 승인 파일이 있으면 → 사용자가 이미 확인하고 진행 승인한 것
        if [ -f "$APPROVAL_FILE" ]; then
            rm -f "$APPROVAL_FILE"
            log_json "APPROVED" "민감파일편집" "$FILE_PATH" "$pattern"
            exit 0
        fi

        # 첫 시도 → 승인 파일 생성 후 경고 출력
        touch "$APPROVAL_FILE"
        log_json "WARNED" "민감파일편집" "$FILE_PATH" "$pattern"

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "❓  진행하려면 저에게 '그래도 진행해줘'라고 말씀해주세요." >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        exit 2
    fi
done

# ── 통과 ─────────────────────────────────────────────────────

log_json "ALLOWED" "파일편집" "$FILE_PATH"
exit 0
