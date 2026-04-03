#!/usr/bin/env bash
# ============================================================
# KM Security Plugin v2.0 - 민감 파일 편집 감지 및 systemMessage 경고
#
# Claude Code가 파일을 편집/생성하기 전에 자동 실행됩니다.
# 민감한 파일을 수정하려 하면 systemMessage로 Claude에게 경고를 주입합니다.
# 실제 차단은 하네스의 permissions 시스템이 담당합니다.
# ============================================================
set -uo pipefail

INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
print(ti.get('file_path') or ti.get('path') or '')
")

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

    python3 -c "
import json, sys
entry = {
    'timestamp': sys.argv[1],
    'status': sys.argv[2],
    'category': sys.argv[3],
    'file': sys.argv[4],
    'pattern': sys.argv[5],
    'user': sys.argv[6],
}
print(json.dumps(entry, ensure_ascii=False))
" "$timestamp" "$status" "$category" "$file" "$pattern" "${USER:-unknown}" >> "$LOG_FILE"
}

# ── 파일 유형별 설명 ─────────────────────────────────────────

get_file_description() {
    local file="$1"
    case "$file" in
        *\.env*) echo "환경 설정 파일 (.env) — API 키, 비밀번호 등 민감한 정보가 담겨 있어요." ;;
        *\.pem*|*\.key*|*\.p12*|*\.pfx*|*\.crt*|*\.cer*) echo "보안 인증서 / 개인 키 파일 — 서버나 서비스 접근에 사용되는 중요한 보안 파일이에요." ;;
        *credentials*|*\.secret*) echo "인증 정보 파일 — 계정이나 서비스 접근에 필요한 비밀 정보가 담겨 있어요." ;;
        *\.ssh*|*id_rsa*|*id_ed25519*|*id_ecdsa*|*authorized_keys*|*known_hosts*) echo "SSH 키 / 설정 파일 — 서버 접속에 사용되는 보안 키예요." ;;
        *\.aws*|*\.gcloud*|*\.azure*) echo "클라우드 인증 파일 — 클라우드 접속 정보가 담겨 있어요." ;;
        *\.kube*|*kubeconfig*) echo "Kubernetes 설정 파일 — 서버 클러스터 접근 정보가 담겨 있어요." ;;
        *docker-compose*|*Dockerfile*) echo "Docker 설정 파일 — 서버 실행 환경 설정이에요." ;;
        *terraform*) echo "Terraform 인프라 설정 파일 — 클라우드 인프라 구성 정보예요." ;;
        *package-lock*|*yarn\.lock*|*pnpm-lock*|*Pipfile\.lock*|*poetry\.lock*) echo "패키지 잠금 파일 — 라이브러리 버전을 고정하는 파일이에요." ;;
        *\.gitignore*|*\.gitmodules*|*\.git/config*) echo "Git 설정 파일 — 코드 관리 도구의 핵심 설정이에요." ;;
        *\.github/workflows*|*\.gitlab-ci*|*Jenkinsfile*|*\.circleci*) echo "CI/CD 자동화 파일 — 빌드 및 배포 자동화 설정이에요." ;;
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

# ── 검사 및 systemMessage 경고 ──────────────────────────────

for pattern in "${PROTECTED_PATTERNS[@]}"; do
    if echo "$FILE_PATH" | grep -qEi "$pattern"; then
        FILE_DESC=$(get_file_description "$FILE_PATH")

        log_json "WARNED" "민감파일편집" "$FILE_PATH" "$pattern"

        # systemMessage로 Claude에게 경고 주입
        python3 -c "
import json, sys
warning = (
    '[KM 보안 경고] 민감 파일 편집: ' + sys.argv[1] + '\n\n'
    '📁 수정하려는 파일: ' + sys.argv[1] + '\n\n'
    '⚠️ 이 파일은 무엇인가요?\n' + sys.argv[2] + '\n\n'
    '🛡️ 왜 중단했나요?\n'
    '이 파일은 보안상 매우 중요합니다. 실수로 잘못 수정하면 '
    '서비스 장애나 보안 사고로 이어질 수 있어요.\n\n'
    '📌 이 정보를 사용자에게 한국어로 친절하게 설명해주세요. '
    '하네스 권한 시스템이 사용자에게 수정 여부를 물어볼 것입니다.'
)
print(json.dumps({'systemMessage': warning}, ensure_ascii=False))
" "$FILE_PATH" "$FILE_DESC"

        exit 0
    fi
done

# ── 통과 ─────────────────────────────────────────────────────

log_json "ALLOWED" "파일편집" "$FILE_PATH"
exit 0
