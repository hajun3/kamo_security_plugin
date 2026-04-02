#!/usr/bin/env bash
# ============================================================
# 🔒 KM Security Plugin for Claude Code - 설치 스크립트
#
# 사용법:
#   git clone https://github.com/kakao-mobility/km-claude-security.git
#   cd km-claude-security
#   chmod +x install.sh && ./install.sh
#
# 설치 위치: 
#   글로벌 설치 → ~/.claude/ (모든 프로젝트에 적용)
#   프로젝트 설치 → ./.claude/ (현재 프로젝트에만 적용)
# ============================================================
set -euo pipefail

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  🔒 KM Security Plugin for Claude Code           ║${NC}"
echo -e "${BLUE}║     카카오모빌리티 보안 플러그인 설치             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# ── 설치 모드 선택 ────────────────────────────────────────────

echo -e "${YELLOW}설치 모드를 선택하세요:${NC}"
echo ""
echo "  1) 글로벌 설치 (모든 프로젝트에 적용) — 권장"
echo "  2) 프로젝트 설치 (현재 디렉토리에만 적용)"
echo ""
read -rp "선택 (1/2): " INSTALL_MODE

case "$INSTALL_MODE" in
    1)
        TARGET_DIR="$HOME/.claude"
        SETTINGS_FILE="$TARGET_DIR/settings.json"
        CLAUDE_MD_TARGET="$HOME/.claude/CLAUDE.md"
        echo -e "\n${GREEN}→ 글로벌 모드로 설치합니다.${NC}"
        ;;
    2)
        TARGET_DIR="./.claude"
        SETTINGS_FILE="$TARGET_DIR/settings.json"
        CLAUDE_MD_TARGET="./CLAUDE.md"
        echo -e "\n${GREEN}→ 프로젝트 모드로 설치합니다.${NC}"
        ;;
    *)
        echo -e "${RED}잘못된 선택입니다. 설치를 중단합니다.${NC}"
        exit 1
        ;;
esac

# ── 디렉토리 생성 ─────────────────────────────────────────────

HOOKS_DIR="$TARGET_DIR/hooks"
LOG_DIR="$HOME/.claude/security-logs"

mkdir -p "$HOOKS_DIR"
mkdir -p "$LOG_DIR"

echo -e "${GREEN}✓${NC} 디렉토리 생성 완료"

# ── 훅 스크립트 복사 ──────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/.claude/hooks/check-dangerous-commands.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/.claude/hooks/check-sensitive-files.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/.claude/hooks/session-security-context.sh" "$HOOKS_DIR/"

chmod +x "$HOOKS_DIR/check-dangerous-commands.sh"
chmod +x "$HOOKS_DIR/check-sensitive-files.sh"
chmod +x "$HOOKS_DIR/session-security-context.sh"

echo -e "${GREEN}✓${NC} 보안 훅 스크립트 설치 완료 (3개)"

# ── settings.json 병합 ────────────────────────────────────────

# jq가 있는지 확인
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq가 설치되어 있지 않습니다.${NC}"
    echo "  설치 방법:"
    echo "    macOS:  brew install jq"
    echo "    Ubuntu: sudo apt-get install jq"
    exit 1
fi

# 경로 설정 (글로벌이면 $HOME/.claude, 프로젝트면 $CLAUDE_PROJECT_DIR)
if [ "$INSTALL_MODE" = "1" ]; then
    HOOK_PATH_PREFIX="\"\$HOME\"/.claude/hooks"
else
    HOOK_PATH_PREFIX="\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks"
fi

NEW_HOOKS=$(cat <<HOOKJSON
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH_PREFIX/session-security-context.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH_PREFIX/check-dangerous-commands.sh"
          }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH_PREFIX/check-sensitive-files.sh"
          }
        ]
      }
    ]
  }
}
HOOKJSON
)

if [ -f "$SETTINGS_FILE" ]; then
    # 기존 settings.json이 있으면 hooks 부분만 병합
    BACKUP_FILE="${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo -e "${YELLOW}⚠${NC} 기존 settings.json 백업: $BACKUP_FILE"
    
    # jq로 deep merge
    MERGED=$(jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$NEW_HOOKS"))
    echo "$MERGED" > "$SETTINGS_FILE"
    echo -e "${GREEN}✓${NC} settings.json 병합 완료 (기존 설정 유지)"
else
    echo "$NEW_HOOKS" > "$SETTINGS_FILE"
    echo -e "${GREEN}✓${NC} settings.json 새로 생성"
fi

# ── CLAUDE.md 설치 ────────────────────────────────────────────

if [ -f "$CLAUDE_MD_TARGET" ]; then
    # 기존 CLAUDE.md가 있으면 앞에 추가
    TEMP_FILE=$(mktemp)
    cat "$SCRIPT_DIR/CLAUDE.md" > "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    echo "---" >> "$TEMP_FILE"
    echo "" >> "$TEMP_FILE"
    cat "$CLAUDE_MD_TARGET" >> "$TEMP_FILE"
    mv "$TEMP_FILE" "$CLAUDE_MD_TARGET"
    echo -e "${GREEN}✓${NC} CLAUDE.md에 보안 규칙 추가 (기존 내용 유지)"
else
    cp "$SCRIPT_DIR/CLAUDE.md" "$CLAUDE_MD_TARGET"
    echo -e "${GREEN}✓${NC} CLAUDE.md 생성 완료"
fi

# ── 설치 완료 ─────────────────────────────────────────────────

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ KM Security Plugin 설치 완료!${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  📁 훅 스크립트:   ${HOOKS_DIR}/"
echo -e "  ⚙️  설정 파일:    ${SETTINGS_FILE}"
echo -e "  📋 보안 규칙:    ${CLAUDE_MD_TARGET}"
echo -e "  📝 보안 로그:    ${LOG_DIR}/"
echo ""
echo -e "${YELLOW}  다음 단계:${NC}"
echo -e "  1. Claude Code를 재시작하세요"
echo -e "  2. /hooks 명령으로 훅이 등록되었는지 확인하세요"
echo -e "  3. 테스트: claude 에서 'rm -rf /' 같은 명령 시도"
echo ""
echo -e "  ${RED}제거하려면:${NC} ./uninstall.sh"
echo ""
