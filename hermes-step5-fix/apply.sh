#!/usr/bin/env bash
# ============================================================
# Hermes Agent — step-5-preview "사실상 무제한" 전환 스크립트
# Hermes 가 설치된 머신에서 실행할 것 (이 샌드박스에선 실행 불가).
# 아래 3개 변수만 채우면 됨.
#   출처: hermes-agent.nousresearch.com/docs (configuration,
#         fallback-providers, credential-pools)
# ============================================================
set -euo pipefail

STEPFUN_KEY="${STEPFUN_KEY:-여기에-stepfun-api-key}"        # platform.stepfun.ai → API Keys
OPENROUTER_KEY="${OPENROUTER_KEY:-여기에-openrouter-key}"    # openrouter.ai/keys (선택, fallback용)
FREE_ENDPOINT_BASE_URL="${FREE_ENDPOINT_BASE_URL:-https://YOUR-FREE-ENDPOINT/v1}"  # 기존 custom 무료 엔드포인트

# 1) API 키 등록 (UPPER_SNAKE 이름은 자동으로 ~/.hermes/.env 에 저장됨)
hermes config set STEPFUN_API_KEY "$STEPFUN_KEY"
hermes config set OPENROUTER_API_KEY "$OPENROUTER_KEY"

# 2) 메인 모델을 StepFun 공식 API 의 step-5-preview 로 전환
#    (유료 pay-as-you-go, V0 티어 = 100 RPM / 500K TPM → 실질 무제한)
hermes config set model stepfun/step-5-preview

# 3) fallback 체인 등록 — 429/장애 시 순서대로 자동 전환, 세션 유지
#    3-1. OpenRouter 경유 동일 모델 (플랫폼 요청 캡 없음)
hermes fallback add --provider openrouter --model stepfun/step-5-preview 2>/dev/null || \
  echo "→ 대화형으로 추가: hermes fallback add → openrouter → stepfun/step-5-preview"

#    3-2. 기존 무료 프로모션 엔드포인트 (custom) — 대화형으로 추가:
#         hermes fallback add → Custom endpoint
#           model:    stepfun/step-5-preview-free
#           base_url: $FREE_ENDPOINT_BASE_URL
#           key_env:  STEP5_FREE_KEY   (미리 .env 에 등록: hermes config set STEP5_FREE_KEY <key>)

#    3-3. 저비용 최후 수단
hermes fallback add --provider stepfun --model step-3.5-flash 2>/dev/null || \
  echo "→ 대화형으로 추가: hermes fallback add → stepfun → step-3.5-flash"

# 4) 짧은 reset 은 전환 대신 백오프로 대기 (프롬프트 캐시 보존)
hermes config set fallback.min_switch_reset_seconds 120

# 5) 기존 429 로 걸려 있던 cooldown/벤치 상태 초기화 (실행 중 세션에도 반영됨)
hermes auth reset || true

# 6) 검증
hermes config check
hermes fallback list
hermes config get model
echo "✔ 완료 — 새 세션에서 stepfun/step-5-preview (공식 API) 가 메인으로 동작합니다."
