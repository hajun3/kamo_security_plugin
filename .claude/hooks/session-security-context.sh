#!/usr/bin/env bash
# ============================================================
# KM Security Plugin - 세션 시작 시 보안 컨텍스트 주입
#
# Claude Code 세션이 시작될 때 보안 규칙을 자동으로 컨텍스트에 추가합니다.
# ============================================================
set -euo pipefail

LOG_DIR="$HOME/.claude/security-logs"
mkdir -p "$LOG_DIR"

cat <<'EOF'
{
  "additionalContext": "🔒 [KM Security Plugin 활성화]\n\n이 세션에는 카카오모빌리티 보안 플러그인이 적용되어 있습니다.\n\n자동 차단 항목:\n- 파괴적 명령 (rm -rf, mkfs 등)\n- 권한 상승 (sudo, chmod 777 등)\n- 시스템 파일 접근 (/etc/passwd, .ssh 등)\n- 데이터 외부 전송 (curl POST, nc 등)\n- 환경변수/시크릿 노출\n- 검증되지 않은 패키지 설치\n- 민감 파일 편집 (.env, .pem, credentials 등)\n\n차단 시 로그가 ~/.claude/security-logs/에 기록됩니다."
}
EOF
