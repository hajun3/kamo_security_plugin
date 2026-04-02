# 🔒 KM Security Plugin for Claude Code

카카오모빌리티 Claude Code 보안 플러그인입니다.

Claude Code가 위험한 행동을 하려 할 때 **자동으로 감지하고 차단**합니다.

## 어떤 걸 막아주나요?

| 영역 | 차단 대상 | 예시 |
|------|----------|------|
| 🗑️ 파괴적 명령 | 복구 불가능한 삭제/포맷 | `rm -rf /`, `mkfs`, `dd` |
| 🔑 권한 상승 | 관리자 권한 획득 시도 | `sudo`, `chmod 777` |
| 📁 시스템 파일 | OS 핵심 파일 접근 | `/etc/passwd`, `~/.ssh/` |
| 🌐 데이터 유출 | 외부로 데이터 전송 | `curl -d`, `nc -e` |
| 🔐 시크릿 노출 | API 키/인증정보 출력 | `printenv`, `cat .env` |
| 📦 위험한 설치 | 검증 안 된 패키지 | `curl | bash`, 커스텀 registry |
| ✏️ 민감 파일 편집 | 인증/설정 파일 수정 | `.env`, `.pem`, `credentials` |

## 설치 방법

### 1단계: 다운로드

```bash
git clone https://github.com/kakao-mobility/km-claude-security.git
cd km-claude-security
```

### 2단계: 설치

```bash
chmod +x install.sh
./install.sh
```

설치 모드 선택:
- **글로벌 (권장)**: 모든 프로젝트에서 보안 플러그인이 작동
- **프로젝트**: 현재 프로젝트에서만 작동

### 3단계: 확인

```bash
# Claude Code 재시작 후
/hooks    # 등록된 훅 확인
```

### 사전 요구사항

- **jq** 설치 필요 (JSON 파싱용)
  - macOS: `brew install jq`
  - Ubuntu: `sudo apt-get install jq`

## 작동 방식

```
사용자 요청 → Claude Code → [PreToolUse 훅 자동 실행]
                                    │
                        ┌───────────┼───────────┐
                        │           │           │
                   Bash 명령?   파일 편집?   세션 시작?
                        │           │           │
               check-dangerous  check-sensitive  session-context
                  -commands.sh    -files.sh       .sh
                        │           │           │
                   위험 감지?    보호 대상?   보안 규칙 주입
                   ├─ Yes → 🔴 차단 (exit 2)
                   └─ No  → 🟢 허용 (exit 0)
```

## 파일 구조

```
km-claude-security/
├── install.sh                              ← 설치 스크립트
├── uninstall.sh                            ← 제거 스크립트
├── CLAUDE.md                               ← Claude 행동 규칙
├── README.md                               ← 이 문서
└── .claude/
    ├── settings.json                       ← hooks 설정
    └── hooks/
        ├── check-dangerous-commands.sh     ← 위험 명령 차단
        ├── check-sensitive-files.sh        ← 민감 파일 보호
        └── session-security-context.sh     ← 세션 시작 보안 안내
```

## 보안 로그

차단된 모든 명령은 자동으로 로그에 기록됩니다:

```
~/.claude/security-logs/2026-04-02.log
```

로그 형식:
```
2026-04-02 14:30:00 [BLOCKED] [파괴적 명령] rm -rf /tmp/*
2026-04-02 14:31:00 [ALLOWED] ls -la
2026-04-02 14:32:00 [BLOCKED] [민감파일편집] .env.production
```

## 커스터마이징

### 차단 패턴 추가

`.claude/hooks/check-dangerous-commands.sh`에서 패턴 배열에 추가:

```bash
# 예: git force push 차단
DESTRUCTIVE_PATTERNS+=(
    'git push.*--force'
    'git push.*-f '
)
```

### 보호 파일 추가

`.claude/hooks/check-sensitive-files.sh`에서 패턴 추가:

```bash
# 예: 프로덕션 설정 보호
PROTECTED_PATTERNS+=(
    'production\.config'
    'firebase.*\.json'
)
```

## 제거

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## 한계점

- **텍스트 패턴 매칭 기반**이므로 고도로 난독화된 명령은 탐지 못할 수 있습니다
- **우회 가능성**: 변수 치환, alias, base64 인코딩 등으로 패턴을 피할 수 있습니다
- 이 플러그인은 **1차 방어선**이며, 전문 보안 도구를 대체하지 않습니다

## 라이선스

Internal Use Only - 카카오모빌리티

---

문의: Tech Planning Team
