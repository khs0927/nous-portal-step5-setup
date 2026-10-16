#!/usr/bin/env bash
# ============================================================
# 경로 B 완성판 (완전 무료 · ToS-안전): OpenCode CLI 위임 구성
# ------------------------------------------------------------
# 원리: zen free 티어는 서버 측 앱 게이트(403 FreeTierError)라서
#   "OpenCode 앱 컨텍스트"에서만 추론이 허용된다.
#   → OpenCode CLI를 설치·로그인해 무료 모델을 앱 안에서 돌리고,
#   → Hermes는 번들 `opencode` 스킬(terminal 도구)로 `opencode run`에
#     코딩 작업을 위임(delegate)한다.
# 주의: step-5-preview-free 는 무료 카탈로그에서 제거됨(2026-10 실측,
#   zen-free-models-live.txt 참조). 무료로 쓸 수 있는 건 아래 14종:
#   big-pickle, glm-5.3-flash-free, deepseek-v4.1-flash-free,
#   longcat-2.5-preview-free, mimo-v2.6-flash-free, jev-1.13-free,
#   nemotron-3.5-lightning-free, space-bunny-free, beam-free 등.
#   step-5-preview 자체는 Go($10/월) 또는 StepFun 직결(종량제) 경로 사용.
# 실행: Hermes가 설치된 머신에서  bash setup_opencode_delegate.sh
# ============================================================
set -uo pipefail

step() { printf "\n\033[1m== %s ==\033[0m\n" "$1"; }

step "1/5 OpenCode CLI 설치"
if command -v opencode >/dev/null 2>&1; then
  echo "이미 설치됨: $(opencode --version 2>/dev/null | head -1)"
elif command -v npm >/dev/null 2>&1; then
  npm i -g opencode-ai@latest
elif command -v brew >/dev/null 2>&1; then
  brew install anomalyco/tap/opencode
else
  echo "npm/brew 없음 — https://opencode.ai 설치 안내 참조 후 재실행"; exit 1
fi
command -v opencode >/dev/null 2>&1 || { echo "설치 실패"; exit 1; }

step "2/5 로그인 (zen free 티어 활성화)"
if opencode auth list 2>/dev/null | grep -qi "opencode\|zen"; then
  echo "이미 로그인된 OpenCode 자격증명 발견 — 건너뜀"
else
  echo "브라우저 로그인 진행 (OpenCode 계정 필요, 무료):"
  opencode auth login
fi
opencode auth list 2>/dev/null | head -10

step "3/5 무료 카탈로그 라이브 감지"
FREE_MODELS="$(python3 - <<'PY'
import json, urllib.request
req = urllib.request.Request("https://opencode.ai/zen/v1/models", headers={"User-Agent":"Mozilla/5.0"})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        ids = [m["id"] for m in json.load(r)["data"]]
    pref = [i for i in ids if i.endswith("-free") or i == "big-pickle"]
    print(" ".join(pref))
except Exception as e:
    print("")
PY
)"
if [ -n "$FREE_MODELS" ]; then
  echo "현재 무료 모델(${#FREE_MODELS} chars): $FREE_MODELS"
else
  echo "카탈로그 감지 실패 — 스냅샷(zen-free-models-live.txt) 기준 진행"
  FREE_MODELS="glm-5.3-flash-free big-pickle deepseek-v4.1-flash-free"
fi
# 코딩 위임 기본 모델: 우선순위 순으로 첫 생존 모델 선택
PICK=""
for want in glm-5.3-flash-free deepseek-v4.1-flash-free big-pickle mimo-v2.6-flash-free; do
  case " $FREE_MODELS " in *" $want "*) PICK="$want"; break;; esac
done
[ -n "$PICK" ] || PICK="$(echo "$FREE_MODELS" | awk '{print $1}')"
echo "→ 위임 기본 모델: opencode/$PICK"

step "4/5 앱 내 zen free 스모크 테스트"
if opencode run --model "opencode/$PICK" "Reply with exactly one word: pong" 2>&1 | tail -3; then
  echo "스모크 테스트 완료 (위 출력에 pong 이 보이면 zen free 정상)"
else
  echo "스모크 테스트 실패 — 'opencode models' 로 slug 확인 후 수동 재시도:"
  echo "  opencode run --model opencode/<slug> 'say pong'"
fi

step "5/5 Hermes 위임 연동 확인"
if command -v hermes >/dev/null 2>&1; then
  hermes skills list 2>/dev/null | grep -i opencode \
    && echo "✔ opencode 위임 스킬 활성화됨" \
    || echo "스킬이 안 보이면 Hermes 업데이트(pip install -U hermes-agent 또는 git pull) 후 'hermes skills' 재확인"
else
  echo "hermes CLI가 PATH에 없음 — Hermes 머신에서 실행했는지 확인"
fi

cat <<EOF

============================================================
✔ 구성 완료 — 사용법 (Hermes 대화에서 그대로 요청하면 됨)

  • 일회성 코딩 작업 위임:
      opencode run --model opencode/$PICK 'Add retry logic to api.py and update tests'
  • 파일 컨텍스트 포함 / 사고과정 표시:
      opencode run --model opencode/$PICK 'Review this for security issues' -f src/auth.py --thinking
  • 장기 인터랙티브 세션 (Hermes terminal 도구, background+pty):
      opencode   (TUI)
  • Hermes 메인/보조 슬롯은 zen free 직결 불가(403 앱 게이트) —
      aside 슬롯은 config.zen-go.yaml(Go \$10/월) 또는 apply.sh(StepFun 직결)로 구성할 것.
  • 무료 카탈로그 변동 감시: python3 test_zen_go.py  (T1~T3 무키 점검)

참고: step-5-preview 를 쓰고 싶다면 — Go 릴레이(opencode-go/step-5-preview,
구독 \$10/월, config.zen-go.yaml) 또는 StepFun 공식 직결(apply.sh) 경로.
============================================================
EOF
