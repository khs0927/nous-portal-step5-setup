# StepFun Step-5 구현 런북 (Hermes Agent + Nous Research Portal)

Hermes Agent와 Nous Research Portal을 통해 StepFun의 Step-5 모델(`stepfun/step-5-preview`, `stepfun/step-5-preview:free` 등)을 통합하고 사용하는 방법을 정리한 한국어 실무 런북입니다. OAuth 인증, 모델 선택, 직접 API 호출, 로컬 프록시, 서브에이전트 위임(delegation), Mixture-of-Agents(MoA) 교차 검증 구성까지 단계별로 다룹니다.

- 무료 변형 `stepfun/step-5-preview:free`가 이 리포지토리의 주 대상입니다 (verified cost=0).
- 본 문서의 수치는 2026-10-12에 Nous 포털 실측 기준으로 검증되었습니다.

## 디렉터리 구조

```
nous-portal-step5-setup/
├── README.md                     # 이 문서
├── LICENSE                       # MIT License
├── .gitignore                    # 시크릿·캐시 추적 제외
├── config.yaml.sanitized         # 민감정보 제거 설정 예시 (model/delegation/moa 블록)
├── docs/
│   ├── setup-guide.md            # 메인 가이드 (6단계 런북)
│   ├── model-specs.md            # Step-5 모델 스펙 참조 문서
│   └── operations.md             # 운영(Spark 브리지 등) 노트
├── probes/
│   ├── step5_probe.py            # OAuth 토큰 자동 해석 + 채팅 프로브 (stdlib 전용)
│   └── verify.sh                 # 스모크 테스트 (RESULT: N/N passed)
└── scripts/                      # 보조 스크립트 (delegation-switch 등)
```

> `scripts/` 디렉터리는 보조 스크립트가 들어가는 위치로, 현재 구성은 [docs/setup-guide.md](docs/setup-guide.md) 5단계를 참고하십시오.

## 퀵스타트

1. `hermes auth add nous --type oauth`로 포털 로그인 (OAuth 디바이스 코드 플로우).
2. `hermes model --refresh`로 모델 캐시를 갱신하고 `stepfun/step-5-preview:free`를 확인.
3. `python probes/step5_probe.py`로 첫 응답 확인 — `bash probes/verify.sh`로 전체 검증.

전체 절차는 **[docs/setup-guide.md](docs/setup-guide.md)** (6단계: 로그인 → 모델 설정 → 직접 호출 → 프록시 → delegation → MoA)에 정리되어 있습니다.

## 핵심 사실

### Step-5 Preview 스펙 (출처: [docs/model-specs.md](docs/model-specs.md))

| 파라미터 | 값 |
|---|---|
| 아키텍처 | Sparse MoE (전체 600B, 활성화 27B) |
| 컨텍스트 창 | 1,048,576 토큰 (1M) |
| 최대 출력 | 65,536 토큰 |
| 입력 모달리티 | 텍스트, 이미지, 비디오 (내장 멀티모달) |
| 출력 모달리티 | 텍스트만 |
| 추론 지원 | true (effort: low / medium / high, `reasoning_content` 필드) |
| 툴 콜 / 구조화된 출력 | true / true |
| 가격 (Nous 포털) | `stepfun/step-5-preview:free` → $0 (verified); 유료 변형은 API 기반 가격 |
| 제3자 어그리게이터 참고가 (비교용, 비공식) | 입력 $1/M · 출력 $2.7/M · 캐시 읽기 $0.05/M 토큰 (OpenRouter/nano-gpt/kilo) |
| 추론 엔드포인트 | https://inference-api.nousresearch.com/v1 |

> 추론 모델이므로 `max_tokens`는 반드시 400 이상으로 지정하십시오. 낮으면 `reasoning_content`가 예산을 모두 소모해 `content`가 비어 있고 `finish_reason='length'`가 반환됩니다.

### ⚠️ /v1/chat/completions 429 Gotcha

`access_token`은 모델 조회(`/v1/models`)에만 통과하고, 채팅 완료(`/v1/chat/completions`)에서는 **HTTP 429**로 거부됩니다 — 반드시 short-lived `agent_key`(수명 약 3602초)를 사용하십시오. `probes/step5_probe.py`는 이를 자동으로 처리합니다. 만료 시 `hermes auth refresh`로 갱신.

## 프로브 사용법

```bash
python probes/step5_probe.py                # 기본 모델(stepfun/step-5-preview:free)로 핑
python probes/step5_probe.py --list-models  # Step 계열 모델 목록 조회
bash probes/verify.sh                       # 전체 스모크 테스트 (RESULT: 8/8 passed 목표)
```

주요 옵션: `--model MODEL` · `--max-tokens N` (기본 800) · `--prompt TEXT` · `--timeout SECONDS` · `--list-models` (인증 파일 경로는 `HERMES_HOME` 환경변수로 지정; 기본 `%LOCALAPPDATA%/hermes/auth.json`)

## 문서

- [docs/setup-guide.md](docs/setup-guide.md) — 메인 설정 가이드 (6단계 런북 + 트러블슈팅)
- [docs/model-specs.md](docs/model-specs.md) — Step-5 모델 스펙 참조 문서
- [docs/operations.md](docs/operations.md) — 운영 노트 (Spark 브리지 등)

## 검증 체크리스트

아래 항목은 [docs/setup-guide.md](docs/setup-guide.md)의 "검증 체크리스트"와 동일합니다:

- [ ] `hermes auth add nous --type oauth` 완료 및 `auth.json` 생성 확인
- [ ] `hermes model --refresh`로 `stepfun/step-5-preview:free` 확인
- [ ] `bash probes/verify.sh` 전체 통과 (`RESULT: 8/8 passed`)
- [ ] `python probes/step5_probe.py --list-models`에 Step 계열 5종 출력
- [ ] `config.yaml`에 `model.default: stepfun/step-5-preview:free` 및 `delegation`·`moa` 블록 적용
- [ ] `hermes proxy status`에서 `nous` 업스트림이 `ready`
- [ ] 토큰 갱신(`hermes auth refresh`) 절차 숙지
- [ ] `auth.json`이 `.gitignore`에 의해 추적 제외됨을 확인

## 보안

- `auth.json`(라이브 `access_token`·`agent_key` 포함)과 `.env`는 절대 커밋하지 마십시오 — `.gitignore`에 등록되어 있습니다.
- 이 리포지토리에는 민감정보를 제거한 `config.yaml.sanitized`만 포함합니다.

---

*작성일: 2026-10-12*
