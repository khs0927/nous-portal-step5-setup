# Hermes Agent — step-5-preview-free 429 진단 & "사실상 무제한" 전환 가이드

작성일: 2026-10-15 · 갱신: 2026-10-17 (aside zen free 상태 점검 추가) · **최종: 2026-10-17 GitHub 스캔(khs0927) 기반 수리 패키지 → `../aside-zen-fix/` 참조**

---

## 0. 업데이트 — aside(보조) 슬롯의 "zen free" 공급자 상태 (10/17 실측)

**결론: 익명 Zen free 티어는 사망(403 앱 게이트), Go 릴레이의 `step-5-preview`는 생존.**

- `opencode.ai/zen/v1` 익명 free: 2026-09부터 서버 측 CLI 지문 검증 — 6가지 헤더 조합 전부 **403 FreeTierError** ("only from within OpenCode"). `step-5-preview-free`는 익명 카탈로그에서 제거됨
- `opencode.ai/zen/go/v1` (OpenCode Go, **$10/월**): 공개 리스팅 37모델에 **`step-5-preview` 포함**(slug 변경, `-free` 접미사 사라짐 → Hermes #136413 납치 버그도 비발동). Hermes는 Go 공식 검증 클라이언트(세션 헤더 PR #101864, v0.21.0 이후)
- 커뮤니티 플러그인 `anpicasso/hermes-oc-free-provider` v3.0.0: PR #6이 CLI 지문 spoof로 게이트 우회(200 확인 주장)하나 **ToS 위반 소지 → 배포 비권장**
- 상세 근거·표·출처: **`zen-free-status.md`**
- 실행 파일: **`config.zen-go.yaml`** (Go 릴레이 메인+보조 슬롯 구성) · **`test_zen_go.py`** (연결 검증기, 키 없어도 T1~T3 동작) · **`setup_opencode_delegate.sh`** (완전 무료 경로: OpenCode 앱 내 zen free + Hermes 위임)

---

## 1. 로그 진단

```
layer: provider | code: rate_limit | retryable: true
provider: custom | model: stepfun/step-5-preview-free
error: HTTP 429: Provider returned errord
```

- **429 = 공급사 측 요청 한도(quota) 소진.** Hermes 버그가 아니라 무료 채널의 제한에 걸린 것.
- `provider: custom` + `-free` 모델 ID → 지금 **무료 프로모션 엔드포인트**(OpenRouter 공식이 아닌 서드파티/포털 무료 채널)를 custom base_url로 물려둔 구성.
- `retryable: true` → Hermes가 이미 **지수 백오프(60초 → 최대 4시간)** 또는 429가 알린 reset 시각까지 자동 대기/재시도 중. 설정이 없어진 게 아니라 한도 자체가 막힌 상태.
- ⚠️ 참고: 이 429는 앞으로 **더 심해진다.** Step 5 Preview 무료 프로모션들이 오늘(10/15) 전후로 종료:
  - **Nous Portal 무료 주간: 2026-10-08 ~ 10-15 (오늘 종료)** — 10/16부터 정상 과금($1/$2.7 per 1M)으로 복귀
  - Cline: 10/8부터 "1주" (종료일 미공지), Kilo Code: 10/9부터 "1주"
  - OpenCode `step-5-preview-free`: "limited time" 무료 (언제든 종료 가능, upstream 502 등 불안정 보고 있음)

## 2. 리서치 결과 — step-5-preview 접근 채널 비교 (2026-10-15 확인)

| 채널 | 비용 | 요청 한도 | "무제한" 여부 |
|---|---|---|---|
| **StepFun 공식 API** (`api.stepfun.ai/v1`, 모델 `step-5-preview`) | $1.00/1M 입력(캐시ヒット $0.10), $2.70/1M 출력 | V0 티어(누적 충전 $15 미만): **동시 5 · 100 RPM · 500K TPM** / V1($15+): 400 RPM · 2M TPM | ✅ 실질적 무제한 — 에이전트 1개가 100 RPM을 소진하는 건 거의 불가능 |
| **OpenRouter 유료** (`stepfun/step-5-preview`) | $1.00/1M 입력, $2.70/1M 출력 (금일 API로 실확인) | 플랫폼 요청 캡 없음 (토큰/분 한도만) | ✅ 실질적 무제한 |
| OpenRouter 무료 `:free` 변형 | $0 | — | ❌ 현재 step-5-preview `:free` 변형은 OpenRouter 모델 목록에 **없음** (실확인) |
| 프로모션 무료 채널 (Nous Portal/Cline/Kilo/OpenCode, 현 구성) | $0 | 채널별 quota, best-effort | ❌ 제한적 + **프로모션 오늘~내일 종료** |
| 셀프호스팅 (공식 BF16 가중치 10/15 공개 예정, 커뮤니티 GGUF 양자화 ~275GB) | 하드웨어 | 없음 | ✅ 완전 무제한이나 600B MoE → 대형 멀티 GPU 필요, 현실성 낮음 |

**결론: "step-5-preview를 제한 없이" 쓰는 유일하게 현실적인 방법은 유료 공식 채널(StepFun 직결 또는 OpenRouter)로 전환 + Hermes의 3중 회복 장치(credential pool → fallback → backoff)를 걸어두는 것.** 비용은 매우 저렴 — 예: 입력 10M + 출력 2M 토큰/월 ≈ **$15.4/월**.

> 무료 한도를 늘리려고 계정을 대량 생성해 키를 돌리는 방법은 각 플랫폼 ToS 위반이며(밴 대상), 어차 promo가 오늘 끝나므로 권장하지 않음. Hermes의 credential pool은 *정당한* 복수 키(예: 조직 키 2개) 회전을 위한 기능.

## 3. 적용 방법

Hermes는 **StepFun을 네이티브 provider로 지원** (`stepfun`, `STEPFUN_API_KEY`, 선택 `STEPFUN_BASE_URL`).

### 경로 A (권장): StepFun 공식 API로 메인 전환 + 무료 채널은 fallback으로 강등

1. [platform.stepfun.ai](https://platform.stepfun.ai) 가입 → 신분 인증 → 소액 충전($5~15면 V0/V1 티어) → API 키 발급
2. 키 등록 (`.env`에 저장됨):
   ```bash
   hermes config set STEPFUN_API_KEY "你的-stepfun-key"
   hermes config set OPENROUTER_API_KEY "sk-or-v1-..."   # fallback용 (선택)
   ```
3. 메인 모델 전환:
   ```bash
   hermes config set model stepfun/step-5-preview
   # 또는 인터랙티브: hermes model → StepFun → step-5-preview
   ```
4. fallback 체인 추가 — 이 저장소의 `config.snippet.yaml`을 `~/.hermes/config.yaml`에 병합하거나:
   ```bash
   hermes fallback add    # 대화형: openrouter / stepfun/step-5-preview 추가
   hermes fallback add    # 대화형: stepfun / step-3.5-flash 추가 (저비용 최후 수단)
   ```
5. 429로 걸려 있던 cooldown 초기화 + 설정 검증:
   ```bash
   hermes auth reset
   hermes config check
   ```

### 경로 B (무료 유지): 지금 채널을 살리되 429에 죽지 않게 방어

프로모션이 오늘 끝나므로 미봉책임. 그래도 유지하려면:
- 기존 custom 무료 엔드포인트를 `fallback_providers` 2순위로 넣고, 1순위를 다른 무료 채널(예: OpenCode Zen `opencode-zen` + `OPENCODE_ZEN_API_KEY`)로 교체
- `fallback.min_switch_reset_seconds: 120` → reset이 2분 이내면 전환 대신 백오프로 대기(프롬프트 캐시 보존)
- 정당한 복수 키가 있으면 `hermes auth add <provider> --api-key ...`로 pool 구성 (429 시 자동 회전)

### 동작 원리 (Hermes 3중 방어)

```
요청 → credential pool 내 키 회전(같은 provider)
     → 전부 소진 시 fallback_providers 순차 전환(다른 provider, 세션 유지)
     → 429에 reset 시각이 있으면 그때까지 벤치, 없으면 60초→4시간 지수 백오프
```

## 4. 파일 구성

| 파일 | 용도 |
|---|---|
| `README.md` | 이 문서 |
| `zen-free-status.md` | aside zen free 공급자 상태 보고서 (10/17 실측+소스분석) |
| `config.snippet.yaml` | `~/.hermes/config.yaml`에 병합할 fallback/모델 설정 (StepFun 직결) |
| `config.zen-go.yaml` | OpenCode Go 릴레이 구성 (메인 step-5-preview + aside 슬롯) |
| `apply.sh` | StepFun 직결 경로를 실행하는 CLI 명령 스크립트(키 값만 채우면 됨) |
| `setup_opencode_delegate.sh` | **경로 B 완성판**: OpenCode CLI 설치→zen free 로그인→라이브 카탈로그 감지→스모크 테스트→Hermes 위임 연동 |
| `test_zen_go.py` | Zen/Go 연결 검증기 (무키 T1~T3 / Go 키 T4 / Zen 키 T5) |
| `zen-free-models-live.txt` | zen 무료 카탈로그 실측 스냅샷 (88모델, free slug 14종) |
| `hermes-429.log` | 제보받은 원본 에러 (참고용) |

## 5. 출처

- Hermes Agent docs: Fallback Providers / Credential Pools / Configuration (hermes-agent.nousresearch.com)
- StepFun Pricing & Tiered Rate Limits (platform.stepfun.ai/docs/en/guides/pricing/details) — V0: 5동시/100RPM/500K TPM, step-5-preview $1.00/$0.10/$2.70
- OpenRouter API Credit & Rate Limits (openrouter.ai/docs/api_reference/limits) — 유료 변형은 플랫폼 요청 캡 없음; 무료는 20 RPM/50회/일 ($10 충전 시 1,000회/일)
- OpenRouter `/api/v1/models` 실시간 조회 (2026-10-15): `stepfun/step-5-preview` 유료 존재, `:free` 변형 부재
- OrcaRouter blog: "Step 5 Preview Free in Three Places" / "Nous Portal Free Week" — Cline 10/8~, Nous Portal 10/8–15, Kilo 10/9~, 이후 정가 $1/$2.7 복귀; 커뮤니티 GGUF(~601B, 1M ctx, ~275GB) 존재
- OpenCode docs: `step-5-preview-free` "free for a limited time"
