# StepFun Step-5 모델 구현 가이드 (Hermes Agent + Nous Research Portal)

## 개요
이 리포지토리는 Hermes Agent와 Nous Research Portal을 통해 StepFun의 Step-5 모델(Step-5-preview, Step-5-preview:free 등)을 통합하고 사용하는 방법을 문서화한 실무용 런북입니다. 인증, 모델 선택, API 호출, 로컬 프록시 설정, 서브에전트 위임, Mixture-of-Agents(MoA) 교차 검증 구성까지 단계별로 안내합니다.

---

## 사전 요구사항

- **Hermes Agent**가 설치된 환경 (v0.21.2 이상 권장)
- **웹 브라우저**에서 OAuth 디바이스 코드 플로우 인증 수행 가능
- **cURL** 또는 HTTP 클라이언트 사용 가능
- **.env 또는 config.yaml** 편집 권한

---

## 1단계: Portal 로그인 (OAuth 디바이스 코드 플로우)

Hermes CLI로 포털 로그인을 진행합니다. 최초 1회만 수행하면 `%LOCALAPPDATA%/hermes/auth.json`에 토큰이 저장됩니다.

```bash
# OAuth 디바이스 코드 흐름 시작 (client_id 'hermes-cli', scope 'inference:invoke')
hermes auth add nous --type oauth
```

- 브라우저가 열리면 디스플레이된 인증 코드를 입력하거나, `hermes auth status`로 진행 상황을 확인
- 인증 성공 시 `auth.json`에 `access_token`, `refresh_token`, `agent_key`, `expires_in`이 기록됨

> **보안 경고**: `auth.json`에 포함된 라이브 토큰은 절대 Git 등에 커밋하지 마세요. 민감한 정보이니 `.gitignore` 등에 등록하십시오.

---

## 2단계: Step-5 모델 선택 & 기본 프로바이더 설정

로그인 후 사용 가능한 모델 목록을 확인하고 기본 모델을 설정합니다.

```bash
# 사용 가능한 모델 목록 조회 (step-5 가족 확인)
hermes model --refresh
```

확인된 Step-5 모델 패밀리 (Nous 포털 `/v1/models` 실측 422개 중 Step 계열 5종):

| 모델 ID | 용도 |
|---|---|
| `stepfun/step-5-preview` | 플래그십 (유료) |
| `stepfun/step-5-preview:free` | 플래그십 무료 변형 — 이 문서의 주 대상 |
| `stepfun/step-3.7-flash` | 고속 플래시 |
| `stepfun/step-3.7-flash:free` | 고속 플래시 무료 |
| `stepfun/step-3.5-flash` | 경량 플래시 |

> 컨텍스트·출력 한도 등 세부 스펙은 [model-specs.md](model-specs.md)를 참고하십시오. 해당 문서의 Step-3.x 수치는 어그리게이터 캐시 기반 추정치이며 Nous 포털 실측값이 아닙니다.

기본 프로바이더(`config.yaml`)에 모델을 지정합니다.

```yaml
# config.yaml — model 블록 예시
model:
  default: stepfun/step-5-preview:free
  provider: nous
```

> **CRITICAL**: `/v1/models` 엔드포인트에는 `access_token`을 넣어도 되지만, `/v1/chat/completions`에는 `access_token`이 **HTTP 429**에 의해 거부됩니다. 반드시 **short-lived `agent_key`**를 사용해야 합니다.

---

## 3단계: 직접 API 호출 (curl 예시, 429 gotcha 강조)

`/v1/chat/completions`는 `access_token`을 거부하고 **HTTP 429**를 반환합니다. 반드시 `auth.json`의 **short-lived `agent_key`**를 사용해야 합니다.

```bash
# agent_key 추출 (Windows / git-bash 기준)
AGENT_KEY=$(python -c "import json,os;print(json.load(open(os.path.expandvars(r'%LOCALAPPDATA%/hermes/auth.json')))['providers']['nous']['agent_key'])")

curl -X POST "https://inference-api.nousresearch.com/v1/chat/completions" \
  -H "Authorization: Bearer $AGENT_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "stepfun/step-5-preview:free",
    "messages": [{"role": "user", "content": "Reply with exactly: PONG-STEP5"}],
    "max_tokens": 400
  }'
```

수동으로 토큰을 뽑지 않으려면 이 리포지토리의 프로브를 사용하십시오:

```bash
python probes/step5_probe.py                      # 기본 모델로 핑
python probes/step5_probe.py --list-models        # Step 계열 모델 조회
bash probes/verify.sh                             # 전체 스모크 테스트
```

### ⚠️ 429 Gotcha (필독)

| 헤더에 넣은 값 | `/v1/models` | `/v1/chat/completions` |
|---|---|---|
| `access_token` | ✅ 200 (422개 모델) | ❌ **HTTP 429** |
| `agent_key` | ✅ 200 | ✅ 200 (실측 2.6s) |

- `agent_key` 수명은 `expires_in` 기준 약 3602초(1시간)입니다.
- 만료 시 `hermes auth refresh` 또는 `hermes portal login`으로 갱신하십시오.

---

## 4단계: 로컬 프록시로 외부 앱 연결

Hermes 프록시는 OAuth 자격증명을 붙여 OpenAI 호환 요청을 중계하는 로컬 서버입니다. 외부 앱은 아무 bearer 토큰이나 넣어도 프록시가 진짜 자격증명을 주입합니다.

```bash
hermes proxy start            # 포그라운드 실행
hermes proxy status           # 업스트림 준비 상태 확인
hermes proxy providers        # 사용 가능한 프로바이더 목록
```

- 실측 기준 `nous` 업스트림은 `ready`로 보고되며 bearer 만료시각이 함께 표시됩니다.
- `hermes proxy`는 프록시 서브커맨드가 `start`뿐이라 별도 `stop`은 없습니다 — 포그라운드 프로세스를 Ctrl-C로 종료하거나 백그라운드 세션을 종료하십시오.

> 참고: 이 리포지토리의 Spark 브리지는 포트 4747에서 같은 OpenAI 호환 인터페이스를 제공합니다. 운영법은 [operations.md](operations.md)를 참고하십시오.

---

## 5단계: 서브에이전트 위임 설정 (delegation)

`delegate_task`는 **태스크별 `model` 파라미터가 없습니다** — 자식 모델은 전역 `delegation.*` 핀에서 결정됩니다. 따라서 웨이브 사이에 모델을 바꿔가며 디스패치해야 합니다. 이 리포지토리의 `scripts/delegation-switch.sh`가 그 스위치입니다.

```bash
scripts/delegation-switch.sh fast     # 실행·수집·검증 웨이브 → nemotron
scripts/delegation-switch.sh smart    # 추론 웨이브 → stepfun/step-5-preview:free
scripts/delegation-switch.sh status   # 현재 핀 확인
```

`config.yaml`의 대응 블록:

```yaml
delegation:
  provider: nous
  model: stepfun/step-5-preview:free
  max_concurrent_children: 10
  max_spawn_depth: 2
  max_iterations: 400
  reasoning_effort: high
  orchestrator_enabled: true
  fallback_providers:            # 주 모델 실패 시 순서대로 시도
    - provider: nvidia
      model: z-ai/glm-5.3-flash
    - provider: nvidia
      model: nvidia/nemotron-3.5-lightning-30b-a3b
```

> 이미 실행 중인 자식은 디스패치 당시 모델을 유지합니다. 핀 변경은 다음 웨이브부터 적용됩니다.

---

## 6단계: MoA 교차 검증 설정 (moa)

Mixture-of-Agents는 여러 레퍼런스 모델에 동시에 질의한 뒤 집계자가 종합합니다. `fanout: user_turn`은 사용자 턴마다 fan-out함을 의미합니다.

```yaml
moa:
  enabled: true
  fanout: user_turn
  degraded_reference_policy: loud      # 레퍼런스 실패를 조용히 삼키지 않고 알림
  reference_models:
    - provider: nous
      model: stepfun/step-5-preview:free
      enabled: true
    - provider: nvidia
      model: z-ai/glm-5.3
      enabled: true
  aggregator:
    provider: atria
    model: Atria-Dawn-Preview
```

CLI로 슬롯을 다룰 수도 있습니다: `hermes moa`.

---

## 트러블슈팅 테이블

| 증상 | 원인 | 해결 |
|------|------|------|
| `/v1/chat/completions`에 `access_token`으로 요청 시 **HTTP 429** | `access_token`은 모델 조회 전용 — 채팅 완료에는 `agent_key` 필요 | `agent_key`로 교체 (`probes/step5_probe.py`가 자동 처리) |
| 토큰 만료 (~1시간) | `expires_in` 3602초 경과 | `hermes auth refresh` 또는 `hermes portal login` |
| 모델이 `hermes model` 피커에 안 보임 | 피커 디스크 캐시가 낡음 | `hermes model --refresh` (캐시를 지우고 라이브 `/v1/models` 재펫치) |
| 프로브가 인증 파일을 못 찾음 | `HERMES_HOME` 미설정 + 비표준 경로 | `HERMES_HOME=/path/to/hermes` 환경변수 설정 (프로브가 `$HERMES_HOME/auth.json`을 읽음; 기본 `%LOCALAPPDATA%/hermes/auth.json`) |
| 응답 `content`가 비어 있음 | 추론 모델이 `reasoning_content`에 예산을 모두 소모 | `max_tokens`를 400 이상으로 |
| `hermes proxy status`에 업스트림이 `not logged in` | 해당 프로바이더 자격증명 없음 | `hermes portal login` 후 재시도 |
| 포트 4747 충돌 | Spark 프록시가 이미 점유 | `bash "$LOCALAPPDATA/hermes/scripts/spark-proxy-watchdog.sh"` 실행 (기존 인스턴스는 재사용) |

---

## 검증 체크리스트

- [ ] `hermes auth add nous --type oauth` 완료 및 `auth.json` 생성 확인
- [ ] `hermes model --refresh`로 `stepfun/step-5-preview:free` 확인
- [ ] `bash probes/verify.sh` 전체 통과 (`RESULT: 8/8 passed`)
- [ ] `python probes/step5_probe.py --list-models`에 Step 계열 5종 출력
- [ ] `config.yaml`에 `model.default: stepfun/step-5-preview:free` 및 `delegation`·`moa` 블록 적용
- [ ] `hermes proxy status`에서 `nous` 업스트림이 `ready`
- [ ] 토큰 갱신(`hermes auth refresh`) 절차 숙지
- [ ] `auth.json`이 `.gitignore`에 의해 추적 제외됨을 확인

---
*작성일: 2026-10-12* — verified facts live-tested on this date.