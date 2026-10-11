#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# delegation-switch.sh — delegate_task(서브에이전트) 모델 핀 전환기
#
# 배경: delegate_task에는 태스크별 model 파라미터가 없다. 자식 모델은 전역
#       delegation.* 핀에서 결정되므로, 웨이브 사이에 이 스크립트로 핀을 바꾼다.
#       실행·수집·검증 웨이브는 fast 핀, 추론 웨이브는 smart 핀을 쓴다.
#
#   fast   → provider=nvidia, model=nvidia/nemotron-3.5-lightning-30b-a3b
#   smart  → provider=nous,   model=stepfun/step-5-preview:free
#   status → 현재 핀 조회 (hermes config get, 실패 시 설정 파일 읽기 전용 grep)
#
# ⚠️ 불변 규칙: config.yaml을 sed/에디터로 직접 수정하지 말 것.
#    쓰기는 반드시 `hermes config set`만 사용한다. status는 순수 읽기 전용이다.
#
# 사용법: scripts/delegation-switch.sh fast|smart|status
# (Windows git-bash 호환)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
    cat >&2 <<EOF
사용법: $SCRIPT_NAME <fast|smart|status>

  fast     실행·수집·검증 웨이브용 고속 핀
           provider=nvidia, model=nvidia/nemotron-3.5-lightning-30b-a3b
  smart    추론 웨이브용 핀
           provider=nous, model=stepfun/step-5-preview:free
  status   현재 delegation 핀 조회 (읽기 전용)

예시:
  $SCRIPT_NAME fast      # 고속 웨이브 디스패치 전
  $SCRIPT_NAME smart     # 추론 웨이브 디스패치 전
  $SCRIPT_NAME status    # 현재 핀 확인

주의: 이미 실행 중인 자식은 디스패치 당시 모델을 유지한다.
      핀 변경은 다음 웨이브부터 적용된다.
EOF
}

# ── hermes CLI 존재 확인 (fast/smart는 쓰기 작업이라 필수) ──
require_hermes() {
    if ! command -v hermes >/dev/null 2>&1; then
        echo "[delegation-switch] 오류: hermes CLI를 PATH에서 찾을 수 없습니다." >&2
        exit 1
    fi
}

# ── Windows 경로(C:\Users\<you>\...) → git-bash POSIX 경로(/c/Users/<you>/...) 변환 ──
win_to_posix() {
    local p="${1//\\//}"
    case "$p" in
        [A-Za-z]:*)
            local drive="${p:0:1}" rest="${p:2}"
            printf '/%s/%s' "$(printf '%s' "$drive" | tr '[:upper:]' '[:lower:]')" "${rest#/}"
            ;;
        *)          printf '%s' "$p" ;;
    esac
}

# ── status 폴백용: 설정 파일 탐색 (읽기 전용) ──
# $HERMES_HOME/config.yaml → 없으면 $LOCALAPPDATA/hermes/config.yaml
find_config_file() {
    local f
    if [ -n "${HERMES_HOME:-}" ]; then
        f="$(win_to_posix "$HERMES_HOME")/config.yaml"
        if [ -f "$f" ]; then printf '%s' "$f"; return 0; fi
    fi
    if [ -n "${LOCALAPPDATA:-}" ]; then
        f="$(win_to_posix "$LOCALAPPDATA")/hermes/config.yaml"
        if [ -f "$f" ]; then printf '%s' "$f"; return 0; fi
    fi
    return 1
}

# ── status 폴백용: delegation 블록의 model/provider 값 추출 (읽기 전용 grep) ──
# delegation: 하위 들여쓰기 2칸 키만 취급 — fallback_providers 등 중첩 항목은 제외한다.
grep_delegation_value() {
    local cfg="$1" key="$2"
    local in_block=0 val=""
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            delegation:*)
                in_block=1
                continue
                ;;
            [![:space:]]*)
                # 새 최상위 키 시작 = delegation 블록 종료
                if [ "$in_block" -eq 1 ]; then break; fi
                ;;
        esac
        if [ "$in_block" -ne 1 ]; then continue; fi
        if [[ "$line" =~ ^[[:space:]]{2}${key}:[[:space:]]*(.*)$ ]]; then
            val="${BASH_REMATCH[1]}"
            val="${val%$'\r'}"
            val="${val#[\'\"]}"
            val="${val%[\'\"]}"
            break
        fi
    done < "$cfg"
    printf '%s' "$val"
}

# ── status: hermes config get 우선, 실패 시 설정 파일 폴백 (읽기 전용) ──
hermes_config_get() {
    local key="$1" out
    command -v hermes >/dev/null 2>&1 || return 1
    out=$(hermes config get "$key" 2>/dev/null | tail -n 1) || return 1
    out="${out%$'\r'}"
    [ -n "$out" ] || return 1
    # get 서브커맨드가 없거나 키를 못 찾은 경우(usage/error 출력)는 폴백으로
    case "$out" in
        *[Uu]sage:*|*nknown*|*rror*|*[Nn]ot\ found*) return 1 ;;
    esac
    printf '%s' "$out"
}

show_pin() {
    local key="$1" label="$2" val="" source=""
    if val=$(hermes_config_get "$key"); then
        source="hermes config get"
    else
        local cfg
        if cfg=$(find_config_file); then
            val=$(grep_delegation_value "$cfg" "${key##*.}")
            source="$cfg (읽기 전용)"
        fi
    fi
    if [ -n "$val" ]; then
        printf '  %-10s %s    [%s]\n' "$label:" "$val" "$source"
    else
        printf '  %-10s (조회 실패 — hermes CLI와 설정 파일 모두 확인할 수 없음)\n' "$label:"
    fi
}

MODE="${1:-status}"
case "$MODE" in
    fast)
        require_hermes
        hermes config set delegation.provider nvidia
        hermes config set delegation.model nvidia/nemotron-3.5-lightning-30b-a3b
        echo "[delegation-switch] FAST 핀 적용 완료"
        echo "  provider: nvidia"
        echo "  model:    nvidia/nemotron-3.5-lightning-30b-a3b"
        echo "  용도:     실행·수집·검증 웨이브 (고속)"
        echo "  참고:     이미 디스패치된 자식은 기존 모델 유지 — 변경은 다음 웨이브부터 적용"
        ;;
    smart)
        require_hermes
        hermes config set delegation.provider nous
        hermes config set delegation.model stepfun/step-5-preview:free
        echo "[delegation-switch] SMART 핀 적용 완료"
        echo "  provider: nous"
        echo "  model:    stepfun/step-5-preview:free"
        echo "  용도:     추론 웨이브"
        echo "  참고:     이미 디스패치된 자식은 기존 모델 유지 — 변경은 다음 웨이브부터 적용"
        ;;
    status)
        echo "[delegation-switch] 현재 delegation 핀"
        show_pin delegation.model model
        show_pin delegation.provider provider
        ;;
    *)
        usage
        exit 2
        ;;
esac
