# Zen Free 공급자 상태 보고서 (aside 슬롯용)

점검일: 2026-10-16~17 · 방법: 실시간 엔드포인트 프로브 + Hermes/OpenCode 오픈소스 분석

---

## TL;DR

**익명 Zen free 티어는 2026년 9월부터 서버 측 앱 게이트(403 FreeTierError)로 차단되어 Hermes 등 서드파티 클라이언트에서 직접 연결 불가.** 대신 ① OpenCode Go 구독($10/월)이면 Go 릴레이에서 `step-5-preview`가 정상 서빙되고(실측 확인) Hermes는 공식 검증 클라이언트이며, ② 완전 무료로는 OpenCode CLI에 zen free를 붙이고 Hermes가 `opencode` 스킬로 위임하는 경로가 유일하게 ToS-안전하다. 아래 구성파일·검증스크립트로 둘 다 바로 구동 가능.

## 1. 실시간 프로브 결과 (직접 측정)

| # | 측정 | 결과 |
|---|---|---|
| T1 | `GET opencode.ai/zen/v1/models` (무키) | **200** — 88개 모델 공개 리스팅. 단 `step-5-preview-free`는 **목록에서 사라짐** (zen 익명 카탈로그에 더 이상 없음). `longcat-2.5-preview-free`, `glm-5.3-flash-free`, `big-pickle` 등은 리스팅됨 |
| T2 | `POST opencode.ai/zen/v1/chat/completions` (무키/빈 Authorization/placeholder Bearer/`x-opencode-session`/`x-opencode-client` 등 6가지 헤더 조합) | **전부 403** `FreeTierError: "OpenCode's free tier can only be used from within OpenCode"` — 앱 게이트가 헤더로 우회 불가(서버 측 CLI 지문 검증) |
| T3 | `POST zen/v1` + `step-5-preview-free` | **400** "Model is unavailable" (익명 릴레이에서 해당 모델 자체가 내려감) |
| T4 | `GET opencode.ai/zen/go/v1/models` (무키) | **200** — Go 릴레이 37개 모델 공개 리스팅: **`step-5-preview` 포함** (slug가 `-free` 접미사 없이 변경됨), `longcat-2.5-preview-free`, `beam-free` 등 |
| T5 | `GET zen/go/v1/models` + 잘못된 키 | **401** "Invalid credential" — 인증 게이트 정상 동작 (진짜 Go 키 필요) |
| T6 | `api.opencode-zen.com` (Hermes 구버전 기본값) | **DNS 미해석** — issue #11661의 잘못된 base_url, 현행 main에서는 `opencode.ai/zen/v1`로 수정됨 |

## 2. 오픈소스 분석 (hermes-agent main, 2026-10-16 push 기준)

### Hermes 코어 (NousResearch/hermes-agent)
- `plugins/model-providers/opencode-zen/__init__.py`: **Zen + Go 두 provider를 네이티브 등록**
  - `opencode-zen`: env `OPENCODE_ZEN_API_KEY`, base `https://opencode.ai/zen/v1`, 기본 aux 모델 `gemini-3-flash`
  - `opencode-go`: env `OPENCODE_GO_API_KEY`, base `https://opencode.ai/zen/go/v1`, 기본 aux 모델 `glm-5`, Go 사용량 API(`/zen/go/v1/usage`: rolling/weekly/monthly %) 연동
  - Hermes 귀속 헤더(HTTP-Referer/X-Title/UA) 자동 전송 → Go의 "클라이언트 신원 요구" 충족
- `agent/opencode_affinity.py`: **`opencode.ai` 호스트로 가는 모든 요청(main + auxiliary)에 `x-opencode-session` 자동 부착**. 세션 없으면 `oneshot-<hex>` 생성 (Go는 이 헤더 없으면 400 MissingSessionID — #105841). aside(보조) 슬롯에 base_url 직결해도 헤더가 붙음
- `hermes_cli/models.py`: 모델별 wire 라우팅 — `step-5-preview`는 접두사 테이블(gpt-/grok-/muse-spark→responses, claude-/minimax-/qwen→messages)에 안 걸리므로 **`/v1/chat/completions`** 사용 (정상)
- **issue #136413** (v0.21.1, open, P3): `-free` 접미사 모델을 익명 Zen으로 납치 → 401. **현행 main에서는 해당 코드(`opencode_zen_free_runtime`, `_OPENCODE_FREE_KEYED_SUFFIX_MODELS`)가 리팩토링으로 제거됨** + Go 릴레이의 step-5 slug가 `step-5-preview`로 바뀌어 이중으로 비발동. → **Hermes를 최신으로 업데이트하는 것만으로解消**
- Go 공식 문서: **Hermes는 검증된(validated) 클라이언트** — PR #101864가 v0.21.0 이후 병합, main/auxiliary 양쪽에 세션 헤더 전송. **v0.21.0 딱 그 버전만 헤더 누락**

### 커뮤니티 플러그인 (anpicasso/hermes-oc-free-provider v3.0.0)
- Hermes 플러그인 카탈로그(`plugin-catalog/oc-free-provider.yaml`) 등록본: "Unofficial OpenCode Zen free-model transport", requires_hermes ≥0.21.3, 최종 push 2026-09-21
- **issue #1** (open): 공개 Zen 경로가 403 FreeTierError로 죽었다는 재현 보고서 (2026-09-28, `Bearer public` + UA `opencode/1.18.31`로도 403)
- **PR #6** (open): "comply with Zen free-tier server-side validation" — OpenCode가 2026년 9월 추가한 서버 측 검증(CLI 지문: UA `opencode/1.18.31 ai-sdk/provider-utils/4.0.23 runtime/bun/1.3.14`, `x-opencode-client: cli`, `x-opencode-project: global`, `x-opencode-request: msg_...` ID 포맷, bash/read 도구 주입)을 **복제(spoof)해서 통과**시키는 패치. 작성자는 big-pickle 200 확인 주장
- ⚠️ **권고: PR #6 방식은 배포하지 말 것.** 게이트 메시지가 명시적("only from within OpenCode")이고 Go 문서도 "Traffic is monitored for abuse"라고 경고 — CLI 지문 위장은 접근통제 우회로 계정/IP 밴 및 ToS 위반 소지. 상태 보고용으로만 기록

### OpenCode Go (공식 문서, 금일 fetch)
- **Go $10/월 · Go Plus $40/월**, 콘솔에서 구독 후 API 키 발급, 요청당 과금 아님(구독 포함 사용량, `/usage`로 잔량 확인)
- 모델 목록에 **Step 5 Preview** 포함 (37종: Grok 4.7, GLM-5.3, GPT-6 Luna, Claude Haiku 5.5, Kimi K3, Qwen3.8 Max, DeepSeek V4 Pro, LongCat 2.5 Preview Free 등)
- 클라이언트 요구사항: 자체 UA + 대화별 `x-opencode-session` → Hermes 최신 버전이 둘 다 충족

## 3. 결론 — aside의 zen free를 "실제로 연결"하는 경로

| 경로 | 비용 | step-5-preview | 상태 | 파일 |
|---|---|---|---|---|
| **A. OpenCode Go 구독 → `opencode-go` provider** (권장) | $10/월 | ✅ `step-5-preview` (Go 포함, 실측 200 확인됨 — issue #136413 표) | ✅ 지금 동작. Hermes 최신 + `OPENCODE_GO_API_KEY`만 있으면 됨 | `config.zen-go.yaml`, `test_zen_go.py` |
| **B. OpenCode CLI 위임 (zen free는 앱 안에서만 합법)** | $0 | ✅ 앱 내 무료 카탈로그 | ✅ ToS-안전. Hermes `opencode` 스킬이 `opencode run`으로 위임 | `setup_opencode_delegate.sh` |
| C. Zen 유료 콘솔 키 (`OPENCODE_ZEN_API_KEY`) | 요청당 과금 | 콘솔 목록 기준 (free slug 불가) | ✅ 동작하나 free가 아님 | `test_zen_go.py` T5 |
| D. 익명 zen free 직결 (기존 aside 구성) | $0 | ❌ 목록에서 제거됨 | ❌ **사망** — 403 앱 게이트 (실측). PR #6 spoof는 ToS 위험 | — |
| E. StepFun 공식 API 직결 (전턴 구성) | 종량제 $1/$2.7 per 1M | ✅ 제한없음(100 RPM+) | ✅ 동작 | `apply.sh`, `config.snippet.yaml` |

## 4. 출처
- 실측 프로브: 이 샌드박스에서 2026-10-16/17 직접 실행 (T1~T6, `test_zen_go.py`로 재현 가능)
- github.com/NousResearch/hermes-agent: `plugins/model-providers/opencode-zen/__init__.py`, `agent/opencode_affinity.py`, `hermes_cli/models.py` (main, 2026-10-16), issues #136413/#11661/#18140, PR #101864, website/docs fallback-providers
- github.com/anpicasso/hermes-oc-free-provider: v3.0.0, issue #1, PR #6 (2026-09)
- opencode.ai/v2/docs/console/go (Go 플랜·모델목록·클라이언트 검증표), opencode.ai/v2/docs/console/models (Zen 콘솔)
