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

### 플러그인 마켓플레이스로 설치 (권장)

Claude Code에서 다음 명령어를 실행하세요:

```
/plugin marketplace add https://raw.githubusercontent.com/hajun3/kamo_security_plugin/main/.claude-plugin/marketplace.json
/plugin install km-security
```

> **사전 요구사항 없음** — `python3`은 macOS에 기본 내장되어 있어 별도 설치가 필요 없습니다.

### 수동 설치 (레거시)

```bash
git clone https://github.com/hajun3/kamo_security_plugin.git
cd kamo_security_plugin
chmod +x install.sh
./install.sh
```

> 수동 설치 시 `jq`가 필요합니다: `brew install jq`

## 작동 방식

위험한 명령이 감지되면 즉시 중단하고 사용자에게 친절하게 설명합니다:

```
🔴  잠깐요! 위험할 수 있는 작업이 감지되었습니다.

📋  작업 유형: 파일 / 폴더 영구 삭제

⚠️   왜 위험한가요?
    한번 삭제되면 휴지통에도 남지 않고 영구적으로 사라집니다.
    ...

✅  진행해도 되는지 확인해 주세요:
    - 삭제하려는 경로가 정확한지 확인하셨나요?
    ...

❓  진행하려면 저에게 '그래도 진행해줘'라고 말씀해주세요.
```

사용자가 '그래도 진행해줘'라고 하면 Claude가 재시도하고 허용됩니다.

## 2단계 승인 흐름

```
[1차 시도]
위험 감지 → 경고 메시지 표시 → 차단 (exit 2)
    ↓
Claude가 사용자에게 설명하고 "그래도 진행할까요?" 질문
    ↓
사용자: "응 해줘" → Claude 재시도
    ↓
[2차 시도]
승인 확인 → 허용 (exit 0)
```

승인은 **30초간만 유효**합니다. 이후에는 다시 경고가 표시됩니다.

## 파일 구조

```
km-security-plugin/
├── .claude-plugin/
│   ├── plugin.json           ← 플러그인 메타데이터
│   └── marketplace.json      ← 마켓플레이스 정보
├── plugins/km-security/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── hooks/
│   │   └── hooks.json        ← 훅 이벤트 설정
│   └── scripts/
│       ├── check-dangerous-commands.sh   ← 위험 명령 차단
│       ├── check-sensitive-files.sh      ← 민감 파일 보호
│       ├── session-security-context.sh   ← 세션 시작 보안 안내
│       └── audit-post-execution.sh       ← 실행 감사 로그
└── .claude/hooks/            ← 수동 설치용 스크립트 (jq 필요)
```

## 보안 로그

차단 및 승인된 모든 명령은 자동으로 기록됩니다:

```
~/.claude/security-logs/2026-04-02.jsonl
```

## 한계점

- **텍스트 패턴 매칭 기반**이므로 고도로 난독화된 명령은 탐지 못할 수 있습니다
- **우회 가능성**: 변수 치환, alias, base64 인코딩 등으로 패턴을 피할 수 있습니다
- 이 플러그인은 **1차 방어선**이며, 전문 보안 도구를 대체하지 않습니다

## 라이선스

MIT — 카카오모빌리티

---

문의: Tech Planning Team
