#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# delegation-switch-v2.sh — delegate_task(서브에이전트) 모델 핀 전환기 v2
#
# v1 과의 차이 (2026-10-17):
#   - smart 핀: nous stepfun/step-5-preview:free (무료주간 10/15 종료로 사망)
#               → nvidia z-ai/glm-5.3 (무료, 기존 키 사용)
#   - zen 핀 신설: zen-proxy(cli-opencode-proxy) muse-spark-1.3-contributor-free
#   - pro 핀 신설: stepfun step-5-preview (유료 직결, STEPFUN_API_KEY 필요)
#
#   fast   → nvidia / nvidia/nemotron-3.5-lightning-30b-a3b  (실행·수집·검증 웨이브)
#   smart  → nvidia / z-ai/glm-5.3                            (추론 웨이브, 무료)
#   zen    → zen-proxy / muse-spark-1.3-contributor-free      (프록시 경유 zen free)
#   pro    → stepfun / step-5-preview                         (진짜 Step 5, 유료)
#   status → 현재 핀 조회 (읽기 전용)
#
# ⚠️ 불변 규칙(v1 계승): config.yaml 직접 수정 금지 — 쓰기는 `hermes config set`만.
# 사용법: delegation-switch-v2.sh <fast|smart|zen|pro|status>   (git-bash 호환)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
S="$(basename "$0")"

usage() { cat >&2 <<EOF
사용법: $S <fast|smart|zen|pro|status>
  fast   실행·수집·검증 웨이브용 고속 핀 (nvidia nemotron-3.5-lightning)
  smart  추론 웨이브용 무료 스마트 핀 (nvidia z-ai/glm-5.3)  ← v1의 사망한 nous step-5 대체
  zen    zen free 핀 (zen-proxy muse-spark-1.3-contributor-free — cli-opencode-proxy 필요)
  pro    유료 Step 5 핀 (stepfun step-5-preview — STEPFUN_API_KEY 필요)
  status 현재 delegation 핀 조회 (읽기 전용)
EOF
}

set_pin() {  # $1=provider $2=model
    hermes config set delegation.provider "$1"
    hermes config set delegation.model "$2"
    echo "[delegation-switch-v2] pin → $1 / $2"
    echo "  참고: 이미 디스패치된 자식은 기존 모델 유지 — 변경은 다음 웨이브부터 적용"
}

case "${1:-}" in
    fast)  set_pin nvidia "nvidia/nemotron-3.5-lightning-30b-a3b" ;;
    smart) set_pin nvidia "z-ai/glm-5.3" ;;
    zen)
        if ! curl -s -m 3 http://127.0.0.1:18080/health >/dev/null 2>&1; then
            echo "⚠ zen-proxy(18080) 미응답 — docker compose up -d 먼저. (전환은 진행)" >&2
        fi
        set_pin zen-proxy "muse-spark-1.3-contributor-free" ;;
    pro)
        ENVF="${HOME}/.hermes/.env"
        if ! { [ -n "${STEPFUN_API_KEY:-}" ] || grep -qs "^STEPFUN_API_KEY=" "$ENVF"; }; then
            echo "⚠ STEPFUN_API_KEY 미설정 — hermes config set STEPFUN_API_KEY <키> 후 사용하세요" >&2
        fi
        set_pin stepfun "step-5-preview" ;;
    status)
        echo "[delegation-switch-v2] 현재 핀:"
        hermes config get delegation.provider 2>/dev/null || echo "  provider: (조회 실패)"
        hermes config get delegation.model    2>/dev/null || echo "  model: (조회 실패)"
        hermes config get delegation.fast_model  2>/dev/null || true
        hermes config get delegation.flash_model 2>/dev/null || true
        ;;
    *) usage; exit 2 ;;
esac
