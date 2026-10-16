#!/usr/bin/env bash
# ============================================================
# verify-all.sh — zen free 체인端到 검증 (B9: 구 verify.sh 대체)
#   V1 zen 라이브 카탈로그 (무키, 공개 API)
#   V2 cli-opencode-proxy (health / models / chat ping)
#   V3 Hermes 재배선 상태 (config get + 잔재 grep)
# 실행: 프록시 Docker + Hermes 가 있는 머신에서  bash verify-all.sh
# ============================================================
set -u
PASS=0; FAIL=0; SKIP=0
ok(){ PASS=$((PASS+1)); echo "PASS: $1"; }
ng(){ FAIL=$((FAIL+1)); echo "FAIL: $1"; }
sk(){ SKIP=$((SKIP+1)); echo "SKIP: $1"; }

echo "── V1. zen 라이브 카탈로그 (공개, 무키) ──"
ZENCAT="$(python3 - <<'PY' 2>/dev/null
import json, urllib.request
req=urllib.request.Request("https://opencode.ai/zen/v1/models",headers={"User-Agent":"verify-all/1.0"})
try:
    with urllib.request.urlopen(req,timeout=20) as r:
        ids=[m["id"] for m in json.load(r)["data"]]
    free=[i for i in ids if i.endswith("-free") or i=="big-pickle"]
    print("OK "+str(len(free))+" "+",".join(free))
except Exception as e:
    print("ERR "+str(e))
PY
)"
if [[ "$ZENCAT" == OK* ]]; then
  ok "zen 카탈로그 응답 — free slug $(echo "$ZENCAT" | awk '{print $2}')종"
  for want in mimo-v2.6-flash-free muse-spark-1.3-contributor-free glm-5.3-flash-free; do
    if [[ ",$ZENCAT," == *",$want,"* ]]; then ok "핵심 모델 생존: $want"; else ng "핵심 모델 소멸: $want (카탈로그 변동 — config.js 라이브동기화가 자동 반영)"; fi
  done
  if [[ ",$ZENCAT," == *",step-5-preview-free,"* ]]; then ng "의외: step-5-preview-free 복귀?! — Go/StepFun 경로 재검토"; else ok "step-5-preview-free 부재 확인(예상대로 — zen free로는 Step5 불가)"; fi
else
  ng "zen 카탈로그 조회 실패: $ZENCAT"
fi

echo "── V2. cli-opencode-proxy (127.0.0.1:18080) ──"
if curl -s -m 3 http://127.0.0.1:18080/health >/dev/null 2>&1; then
  ok "health 응답"
  MODELS="$(curl -s -m 5 http://127.0.0.1:18080/v1/models)"
  if echo "$MODELS" | grep -q "mimo-v2.6-flash-free"; then ok "/v1/models 에 기본 무료모델 존재"; else ng "/v1/models 이상"; fi
  for dead in ling-3.0-flash-fin-free nemotron-3-ultra-free mimo-v2.5-free; do
    if echo "$MODELS" | grep -q "\"id\":\"$dead\"\|\"id\": \"$dead\""; then
      # alias로서는 허용(생존 모델로 리다이렉트) — zen/접두 없는 단품이 VERIFIED로 있으면 문제
      echo "INFO: $dead 는 alias로만 존재해야 함 (config.js DEAB_SLUG_ALIASES 확인)"
    fi
  done
  echo "  chat ping (opencode run 경유 — 최대 120초)..."
  RESP="$(curl -s -m 120 -X POST http://127.0.0.1:18080/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d '{"model":"mimo-v2.6-flash-free","messages":[{"role":"user","content":"Reply with exactly one word: pong"}],"max_tokens":16}')"
  if echo "$RESP" | grep -qi "pong\|content"; then ok "chat completion 응답 수신"; else ng "chat ping 실패: $(echo "$RESP" | head -c 200)"; fi
else
  sk "프록시 미구동 (cd cli-opencode-proxy && docker compose up -d --build)"
fi

echo "── V3. Hermes 재배선 상태 ──"
if command -v hermes >/dev/null 2>&1; then
  MD="$(hermes config get model.default 2>/dev/null || true)"
  case "$MD" in
    *step-5-preview:free*|*step-5-preview-free*) ng "model.default 가 여전히 사망한 nous free: $MD" ;;
    "") sk "model.default 조회 불가" ;;
    *) ok "model.default = $MD" ;;
  esac
  DP="$(hermes config get delegation.provider 2>/dev/null || true)"
  DM="$(hermes config get delegation.model 2>/dev/null || true)"
  case "$DM" in *step-5-preview:free*) ng "delegation 핀이 사망 모델: $DP/$DM";; *) ok "delegation 핀 = $DP/$DM";; esac
  CFG="${HERMES_CONFIG:-$HOME/.hermes/config.yaml}"
  if [ -f "$CFG" ]; then
    grep -q "zen-proxy:" "$CFG" && ok "providers.zen-proxy 등록됨" || ng "providers.zen-proxy 없음 — apply-hermes-fix.sh 실행"
    if grep -q "provider: opencode-free" "$CFG"; then ng "MoA에 사망한 opencode-free 잔재"; else ok "opencode-free 잔재 없음"; fi
    if grep -q "stepfun/step-5-preview:free" "$CFG"; then ng "nous step-5 free 잔재 (모델/핀/MoA 어딘가)"; else ok "nous step-5 free 잔재 없음"; fi
  else
    sk "config.yaml 을 못 찾음: $CFG"
  fi
else
  sk "hermes CLI 없음"
fi

echo ""
echo "RESULT: $PASS pass / $FAIL fail / $SKIP skip"
[ "$FAIL" -eq 0 ] || exit 1
echo "✔ zen free 체인 정상 — Aside/Cline/Continue 는 aside-provider.json(수리본) 기준으로 등록하세요"
