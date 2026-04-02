#!/usr/bin/env bash
# ============================================================
# 🔒 KM Security Plugin - 제거 스크립트
# ============================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${YELLOW}KM Security Plugin 제거${NC}"
echo ""

echo "제거 범위를 선택하세요:"
echo "  1) 글로벌 설치 제거 (~/.claude)"
echo "  2) 프로젝트 설치 제거 (./.claude)"
read -rp "선택 (1/2): " MODE

case "$MODE" in
    1) TARGET_DIR="$HOME/.claude" ;;
    2) TARGET_DIR="./.claude" ;;
    *) echo -e "${RED}잘못된 선택${NC}"; exit 1 ;;
esac

HOOKS_DIR="$TARGET_DIR/hooks"

# 훅 스크립트 제거
for script in check-dangerous-commands.sh check-sensitive-files.sh session-security-context.sh; do
    if [ -f "$HOOKS_DIR/$script" ]; then
        rm "$HOOKS_DIR/$script"
        echo -e "${GREEN}✓${NC} 제거: $HOOKS_DIR/$script"
    fi
done

# settings.json에서 hooks 제거 (수동 안내)
echo ""
echo -e "${YELLOW}⚠ settings.json의 hooks 항목은 수동으로 제거해주세요:${NC}"
echo "  파일: $TARGET_DIR/settings.json"
echo ""
echo -e "${YELLOW}⚠ CLAUDE.md의 보안 정책 섹션도 수동으로 제거해주세요.${NC}"
echo ""
echo -e "${GREEN}✅ 제거 완료. Claude Code를 재시작하세요.${NC}"
