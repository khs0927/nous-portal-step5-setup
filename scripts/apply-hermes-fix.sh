#!/usr/bin/env bash
# ============================================================
# apply-hermes-fix.sh — 사망한 nous step-5 free / opencode-free 체인을
#   생존 경로(nvidia 무료 + zen-proxy)로 재배선 (B6~B8)
# 규칙 준수: 스칼라 쓰기는 `hermes config set`만 사용 (당신 런북의 불변 규칙).
#   구조 변경(providers.zen-proxy 추가, MoA reference 교체)만 예외적으로
#   patch_hermes_yaml.py 가 백업+diff 후 적용.
# 실행 위치: Hermes 가 설치된 머신 (Windows면 git-bash)
# ============================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v hermes >/dev/null 2>&1 || { echo "hermes CLI 가 PATH 에 없음"; exit 1; }

echo "== 0) 사전 점검: zen-proxy(18080) 생존 여부 =="
if curl -s -m 3 http://127.0.0.1:18080/health >/dev/null 2>&1; then
  echo "  ✔ 프록시 응답함"
else
  echo "  ⚠ 프록시 미응답 — 먼저 cli-opencode-proxy 에서 'docker compose up -d --build'"
  echo "    (프록시 없이 진행하면 zen-proxy 경유 항목은 실패함. 계속하려면 Enter, 중단은 Ctrl+C)"
  read -r _ || true
fi

echo "== 1) 메인 모델: 사망한 nous/step-5-preview:free → nvidia/z-ai-glm-5.3 (무료) =="
hermes config set model.provider nvidia
hermes config set model.default z-ai/glm-5.3
hermes config unset model.base_url 2>/dev/null || true   # nous inference-api 잔재 제거
hermes config unset model.key_env  2>/dev/null || true
# 유료 Step 5 원할 때 (택1, 주석 해제):
#   hermes config set model.provider stepfun    && hermes config set model.default step-5-preview     # STEPFUN_API_KEY 필요
#   hermes config set model.provider opencode-go && hermes config set model.default step-5-preview    # OPENCODE_GO_API_KEY 필요 ($10/월)

echo "== 2) delegation 핀 기본값 (자세한 전환: delegation-switch-v2.sh) =="
hermes config set delegation.provider nvidia
hermes config set delegation.model z-ai/glm-5.3

echo "== 3) 구조 패치: providers.zen-proxy 등록 + MoA 사망 reference 재배선 =="
CFG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
python3 "$SCRIPT_DIR/patch_hermes_yaml.py" "$CFG" || {
  echo "패치 실패 — config.merged.reference.yaml 과 diff 하며 수동 적용하세요"; exit 1; }

echo "== 4) 429/401 로 걸린 cooldown 초기화 + 검증 =="
hermes auth reset 2>/dev/null || true
hermes config check 2>/dev/null || true
hermes config get model.default
hermes config get delegation.model
echo "✔ 완료 — 이어서: bash ../verify-all.sh"
