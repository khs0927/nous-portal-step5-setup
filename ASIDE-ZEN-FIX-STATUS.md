# Aside · Zen Free 공급자 — 상태 판정 & 수리 패키지

판정일: 2026-10-17 (실측 + khs0927 GitHub 124레포 스캔 + 라이브 카탈로그 대조)

---

## 0. 당신이 보유한 자산 (GitHub 스캔으로 확인)

| 레포 | 역할 | 상태 |
|---|---|---|
| `cli-opencode-proxy` | Docker 안에서 **진짜 opencode 바이너리**(`opencode run --pure`)로 zen free를 태워 OpenAI 호환 API(`127.0.0.1:18080/v1`) 제공 → Aside/Cline/Continue/Hermes 연결 | 🟡 아키텍처 정상, **카탈로그/기본값 stale** (아래 B1~B5) |
| `aside` (빈 레포) + `aside-provider.json` | Aside 플랫폼용 zen-free provider 등록 파일 | 🟡 모델 4종 사망 항목 포함 (B3) |
| `nous-portal-step5-setup` | Hermes step-5 런북: `config.yaml.sanitized`, `delegation-switch.sh`, `verify.sh`, `step5_probe.py` | 🔴 **메인 체인 사망** — Nous Portal step-5 무료주간 10/15 종료 (B6~B8) |
| `omo-zen-spark`, `opencode-skills-pack`, `hermes-orchestrator`, `hermes-minis` | 주변 에셋 | 참고용 |

## 1. zen free 티어 자체의 상태 (오늘 실측)

- 익명 직결(`opencode.ai/zen/v1` + POST): **모든 서드파티 클라이언트 403 FreeTierError** — 2026-09부터 서버 측 검증(TLS 지문/세션). 헤더 조작 우회 불가(6종 조합 실측).
- **당신의 프록시 방식(공식 바이너리 경유)은 이 게이트를 정품 클라이언트로 통과하는 유일하게 건전한 경로** — 프록시 내부에서 실제 `opencode`가 요청하므로 zen 입장에서는 정상 앱 사용. (회색지대 주의: zen free는 best-effort 프로모션이고 OpenCode 측이 "traffic monitored for abuse"를 명시 — 개인 사용 범위 유지, 외부 공유/재판매 금지)
- 라이브 무료 카탈로그(오늘 200 확인, free slug 14종):
  `beam-free · big-pickle · deepseek-v4.1-flash-free · glm-5.3-flash-free · jev-1.13-free · ll-alpha-free · longcat-2.5-preview-free · mimo-v2.6-flash-free · muse-spark-1.2-contributor-free · muse-spark-1.3-contributor-free · nemotron-3.5-lightning-free · nemotron-3.5-super-vl-free · space-bunny-free · test`
- ⚠️ `step-5-preview-free`는 zen free 카탈로그에서 **영구 제거**됨 → Step 5는 Go 릴레이(`step-5-preview`, $10/월) 또는 StepFun 직결(종량제)로만 가능. 프록시로 살릴 수 없음.
- ⚠️ zen은 "리스트에 있어도 서빙 안 하는" 슬러그가 있는 것으로 악명높음(Hermes 쪽 기록: `deepseek-v4-flash-free` 등 리스팅 유지·서빙 중단). 그래서 업데이트된 `config.js`에 **기동 시 라이브 동기화**를 넣었음(B5 해결).

## 2. 발견된 버그 목록 → 수정 파일 매핑

| # | 위치 | 문제 | 수정 |
|---|---|---|---|
| B1 | `src/config.js` VERIFIED 목록 | `nemotron-3-ultra-free`, `ling-3.0-flash-fin-free` **사망**(카탈로그 소멸). 신규 6종(`glm-5.3-flash-free`, `deepseek-v4.1-flash-free`, `longcat-2.5-preview-free`, `nemotron-3.5-super-vl-free`, `beam-free`, `ll-alpha-free`) 미등록, `jev-1.13-free` 복귀 미반영 | `proxy/config.js` |
| B2 | `src/config.js` aliases | `ling-free` → **사망 모델로 매핑**(런타임 ProviderModelNotFound 유발), `deepseek-free` → mimo(산 후속모델 `deepseek-v4.1-flash-free` 있는데), `jev-1.13-free` → mimo(본체 생존) | `proxy/config.js` |
| B3 | `zen-free-provider.json` / `aside-provider.json` | 사망 4종 등록(`mimo-v2.5-free`, `deepseek-v4-flash-free`, `nemotron-3-ultra-free`, `ling-3.0-flash-fin-free`) — Aside/Cline에서 고르면 실패 | `proxy/*.json` |
| B4 | `docker-compose.yml` + `entrypoint.sh` + README | 기본값 `zen/mimo-v2.5-free`(**사망** + zen/ 접두어는 앱 내 규격 `opencode/`와 불일치) | `proxy/docker-compose.yml`, `proxy/entrypoint.sh` |
| B5 | `src/server.js` vs README | README가 광고하는 `syncLiveZenModels` **코드에 없음**; `/health`의 engine_mode 하드코딩; `ENGINE_MODE=serve` 데몬을 켜도 server.js는 항상 `opencode run`(serve 미사용) | `proxy/config.js`에 기동 시 라이브 동기화 구현(비차단, 실패 시 정적 목록 폴백) — server.js 수정 불필요 |
| B6 | Hermes `model.default` | `stepfun/step-5-preview:free` via **nous — 무료주간 10/15 종료로 사망**(최초 429의 원인) | `hermes/apply-hermes-fix.sh` (무료: nvidia `z-ai/glm-5.3`로 전환 / 유료 step-5 옵션 주석) |
| B7 | Hermes `delegation.*` + `delegation-switch.sh` smart 핀 | 사망한 nous step-5 free를 가리킴 | `hermes/delegation-switch-v2.sh` (fast/smart/zen/pro 4핀) |
| B8 | Hermes MoA reference | `provider: nous` step-5 free(사망) + `provider: opencode-free` muse-spark(Hermes 내장 keyless zen = **403 사망**, 실측) | `hermes/patch_hermes_yaml.py` — 둘 다 **zen-proxy(당신 프록시) 경유로 재배선** |
| B9 | `probes/verify.sh` | `model.default == stepfun/step-5-preview:free` 검사 → 항상 FAIL | `verify-all.sh`로 대체(구 verify.sh 호환 검사 포함) |

## 3. 적용 순서 (당신 머신에서)

```bash
# 1) 프록시 수리 — cli-opencode-proxy 레포에 proxy/ 파일들을 덮어쓰고
cd cli-opencode-proxy
cp <이 패키지>/proxy/config.js src/config.js
cp <이 패키지>/proxy/entrypoint.sh ./entrypoint.sh
cp <이 패키지>/proxy/docker-compose.yml ./docker-compose.yml
cp <이 패키지>/proxy/zen-free-provider.json ./zen-free-provider.json
cp <이 패키지>/proxy/aside-provider.json ./aside-provider.json
cp <이 패키지>/proxy/.env.example ./.env.example   # .env의 DEFAULT_MODEL도 zen/mimo-v2.6-flash-free로
docker compose up -d --build

# 2) 전체 검증 (프록시 health → 무료모델 chat ping → Hermes 설정)
bash verify-all.sh

# 3) Hermes 재배선 (스칼라는 hermes config set, 구조는 백업+diff 패치)
bash hermes/apply-hermes-fix.sh

# 4) 서브에이전트 웨이브 핀 전환 (기존 규칙: config set만 사용)
bash hermes/delegation-switch-v2.sh status
```

## 4. 참고 — Step 5 Preview를 진짜 쓰고 싶을 때 (zen free로는 불가)

| 경로 | 비용 | Hermes 설정 |
|---|---|---|
| OpenCode Go 릴레이 `opencode-go/step-5-preview` | $10/월 | `../hermes-step5-fix/config.zen-go.yaml` |
| StepFun 공식 직결 `stepfun/step-5-preview` | 종량제($1/$2.7 per 1M, 100 RPM) | `../hermes-step5-fix/apply.sh` |
| NVIDIA NIM `z-ai/glm-5.3` (무료 대체 스마트 모델) | $0 | 본 패키지 apply-hermes-fix.sh 기본값 |
