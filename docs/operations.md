# Spark 브리지 운영 문서 (operations.md)

## 개요

이 리포지토리에서 Spark(`muse-spark-1.3-contributor-free`)에 접근하는 유일한 경로는 로컬 OpenAI 호환 프록시입니다.

| 항목 | 값 |
|---|---|
| 엔드포인트 | http://127.0.0.1:4747/v1 |
| 모델 | muse-spark-1.3-contributor-free |
| 인증 | 불필요 (keyless) |
| 프록시 소스 | `$LOCALAPPDATA/hermes/spark-proxy/spark_proxy.py` |

---

## 왜 로컬 경유인가 (Cloudflare 1010)

`muse-spark-1.3`의 원격 서비스(opencode.ai)에 직접 HTTP 요청을 보내면 **Cloudflare 1010** 에러로 전면 차단됩니다. 따라서 프록시는 OpenAI 호환 요청을 받아 opencode CLI(`opencode run`)를 셸아웃하는 **브리지**로 동작합니다.

> **직접 HTTP는 동작하지 않습니다 — 시도하지 마십시오.** 로컬 프록시 경로만 유효합니다.

---

## 엔드포인트

| 메서드 | 경로 | 용도 |
|---|---|---|
| GET | /v1/models | 사용 가능한 모델 목록 (현재 `muse-spark-1.3-contributor-free` 1종) |
| POST | /v1/chat/completions | 채팅 완료 (OpenAI 호환 요청/응답 규격) |

연결 확인:

```bash
curl -s http://127.0.0.1:4747/v1/models
```

실측 응답 (2026-10-12):

```json
{"object": "list", "data": [{"id": "muse-spark-1.3-contributor-free", "object": "model", "created": 1791747295, "owned_by": "opencode", "display_name": "Muse Spark 1.3 (opencode CLI)"}]}
```

---

## 호출 특성: 동기 · 60~120초

모든 `/v1/chat/completions` 호출은 프록시가 opencode CLI를 셸아웃하고 완료를 기다리는 **동기 처리**입니다. 호출 1건에 약 **60~120초**가 소요됩니다.

- fan-out은 한 번에 **소수(4~5개 이하)**만 돌리십시오.
- 추론 워커(z-ai/glm-5.3)가 ~1~10초로 빠르므로, 배치의 대부분은 GLM에 맡기고 Spark는 에이전트형 도구작업이 필요한 슬라이스에 예약하십시오.

---

## 워치독 (자동 유지)

프록시는 Hermes cron 작업(2분 주기, no-agent)으로 유지됩니다. 수동 실행:

```bash
bash "$LOCALAPPDATA/hermes/scripts/spark-proxy-watchdog.sh"
```

- 이 머신 기준 전체 경로: `$LOCALAPPDATA/hermes/scripts/spark-proxy-watchdog.sh`
- 워치독은 포트 4747이 살아 있으면 `already up`으로 종료합니다 — **기존 인스턴스를 재사용**하므로 새로 띄우지 마십시오.
- 프록시가 죽어 있으면 재기동하고 최대 25초간 readiness를 기다립니다.
- Spark 호출이 `connection refused`로 실패하면 수동으로 워치독을 실행하십시오.

---

## 3모델 라우팅

| 역할 | 모델 | 프로바이더 / 엔드포인트 |
|---|---|---|
| 오케스트레이션·지시 | Atria-Dawn-Preview | atria (https://api.atria-asi.ai/v1) |
| 추론 워커 (교차 담당) | z-ai/glm-5.3 | nvidia (https://integrate.api.nvidia.com/v1) |
| 에이전트형 도구작업 워커 (교차 담당) | muse-spark-1.3-contributor-free | http://127.0.0.1:4747/v1 (Spark 프록시) |

- 두 워커는 배치 내에서 **교차 담당**합니다: fan-out 시 추론·실행 작업을 GLM과 Spark에 번갈아 할당하여 어느 한쪽이 단일 장애점이 되지 않게 하고 상호 교차 검증합니다.
- 오케스트레이션(무엇을 위임할지 결정, `goal`/`context` 작성, 결과 집계)은 Atria가 담당하며 워커에 넘기지 않습니다.

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| connection refused (연결 거부) | 프록시 미기동 또는 크래시 | 워치독 수동 실행: `bash "$LOCALAPPDATA/hermes/scripts/spark-proxy-watchdog.sh"` |
| Cloudflare 1010 | opencode.ai 직접 HTTP 호출 시도 | 로컬 프록시(http://127.0.0.1:4747/v1) 경유 — 직접 HTTP는 차단됨 |
| 응답이 60~120초 이상 지연 | CLI 경유 동기 처리의 고유 특성 | 정상 동작. 타임아웃을 넉넉히(120초 이상) 설정하고 fan-out을 4~5개 이하로 제한 |
| 포트 4747 점유 / 충돌 | 기존 프록시 인스턴스가 이미 점유 중 | 워치독 실행 — 이미 떠 있으면 기존 인스턴스를 재사용하고 종료하므로 새로 띄우지 말 것 |

---

## 보안 주의

- 이 프록시는 **keyless**입니다. API 키·토큰을 담은 헤더를 붙일 필요가 없습니다.
- `auth.json`(`$HERMES_HOME/auth.json` 또는 `$LOCALAPPDATA/hermes/auth.json`)과 `.env`는 이 문서의 어떤 절차에서도 읽거나 기록하지 않습니다. 시크릿 다룸일수록 프록시 경유가 안전합니다.

---

*작성일: 2026-10-12* — verified facts live-tested on this date (프록시 응답·워치독·`hermes config get` 실측 확인).
