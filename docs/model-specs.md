# Step-Fun Step-5 Preview 참조 문서

한국어 참조 페이지: Step-5 Preview의 기능, 한계, 가격 책정 및 Nous 포털에서 이용 가능한 전체 Step 모델 패밀리

---

## 1. Step 5 Preview 한눈에 보기

| 파라미터 | 값 |
|---|---|
| 모델명 | stepfun/step-5-preview |
| 아키텍처 | Sparse MoE (전체 600B, 활성화 27B) |
| 컨텍스트 창 | 1,048,576 토큰 (1M) |
| 최대 출력 | 65,536 토큰 |
| 입력 모달리티 | 텍스트, 이미지, 비디오 (내장 멀티모달) |
| 출력 모달리티 | 텍스트만 |
| 추론 지원 | true (effort: low / medium / high) |
| interleaved reasoning | `reasoning_content` 필드 (content 앞섭) |
| 툴 콜 | true |
| 구조화된 출력 | true |
| 어텐디션 | false (오픈웨이트 아니지만 상업적 이용 제한 적용) |
| 출시일 | 2026-09-16 |
| 마지막 업데이트 | 2026-09-20 |
| Nous 포털 무료 변형 | stepfun/step-5-preview:free (cost=0) |
| 추론 엔드포인트 | https://inference-api.nousresearch.com/v1 |

---

## 2. 아키텍처

- **Sparse MoE**: 전체 600억 파라미터 중 27B가 각 토큰에 대해 활성화됨
- **실질적 효율**: 전체 규모의 모델이지만, 매 토큰 처리는 활성화된 27B만 수행하므로 메모리 효율이 일반적인 밀도 모델보다 높음
- **상용용도**: 오픈웨이트 아니므로 Nous 포털이나 API를 통해 접근해야 함

---

## 3. 컨텍스트 & 출력 한도

| 항목 | 값 |
|---|---|
| 입력 컨텍스트 | 1,048,576 토큰 (1M) |
| 최대 출력 토큰 | 65,536 토큰 |
| 권장 max_tokens | ≥ 400 (추론 모델의 경우 reasoning_content가 전체 예산을 소모해 content가 비어나는 현상 방지) |

> **IMPORTANT**: 추론 모델은 `reasoning_content`가 `content`보다 먼저 위치함. `max_tokens`가 너무 낮으면 reasoning pass가 전체 예산을 소비하고 `finish_reason='length'`와 함께 비어있는 `content`를 반환할 수 있음. 반드시 `max_tokens >= 400`을 사용하시오.

---

## 4. 멀티모달 입력

- **지원되는 입력**: 텍스트, 이미지, 비디오 (내장 멀티모달 지원)
- **실무적 의미**: 이미지나 비디오가 포함된 프롬프트를 처리할 수 있으나, 출력은 항상 텍스트만 반환됨
- **주의**: 비디오 입력의 경우 토큰 소비가 크게 증가하므로 컨텍스트 예산 내에서 제한적인 길이만 사용 권장

---

## 5. 추론(reasoning) 모드

| effort | 설명 |
|---|---|
| low | 기본 추론 경로, 간단한 논증에 적합 |
| medium | 중간 복잡도 추론, 다단계 문제 해결에 적합 |
| high | 고심 깊은 추론, 복잡한 수학/코딩 증명에 적합 |

### `reasoning_content` 필드 구조

추론 모델은 응답을 두 단계로 구분해서 반환함:

```json
{
  "reasoning_content": "<사고 과정 및 중간 결과>",
  "content": "<최종 답변>"
}
```

**주의사항**:
- `reasoning_content`가 `content`보다 먼저 옴
- `max_tokens`가 부족하면 `reasoning_content`가 전체 예산을 차지해 `content`가 빈 문자열이 될 수 있음
- 반드시 `max_tokens >= 400`을 지정하여 두 필드 모두 충분한 공간을 확보하도록 함

### 코드 예시 (Python)

```python
import openai

client = openai.OpenAI(
    base_url="https://inference-api.nousresearch.com/v1",
    api_key="your_key_here"
)

response = client.chat.completions.create(
    model="stepfun/step-5-preview",
    messages=[{"role": "user", "content": "수학 문제 풀이 요청..."}],
    max_tokens=500,  # 반드시 400 이상
    reasoning_effort="high"
)

# reasoning_content와 content를 모두 확인
print("reasoning_content:", response.choices[0].message.reasoning_content)
print("content:", response.choices[0].message.content)
finish_reason = response.choices[0].finish_reason
print("finish_reason:", finish_reason)
```

---

## 6. 도구 호출 & 구조화된 출력

| 기능 | 지원 여부 |
|---|---|
| 툴 콜 | true |
| 구조화된 출력 (`response_format: {type: "json_object"}`) | true |
| 어텐디션/이미지 어텐디션 | false (텍스트 전용 출력) |

구조화된 출력을 사용할 경우, 모델은 `{"key": "value"}` 형태의 유효한 JSON을 `content` 필드에 반환함. `response_format` 매개변수를 지정해 JSON 스키마를 제한할 수 있음.

---

## 7. 요금

### Nous 포털 변형

| 변형 | 가격 | 비고 |
|---|---|---|
| stepfun/step-5-preview:free | $0 | 무료 변형, verified cost=0, usage.cost_details.source='free_path' |
| stepfun/step-5-preview (유료) | API 기반 가격 | Nous 포털 API를 통한 유료 이용 |

### 제3자 어그리게이터 가격 (비교용, 명확히 라벨링)

| 모델 | 입력 | 출력 | 캐시 읽기 |
|---|---|---|---|
| step-5-preview (OpenRouter) | $1 / M 토큰 | $2.7 / M 토큰 | $0.05 / M 토큰 |
| step-5-preview (nano-gpt) | $1 / M 토큰 | $2.7 / M 토큰 | — |
| step-5-preview (kilo) | $1 / M 토큰 | $2.7 / M 토큰 | $0.05 / M 토큰 |

> **NOTE**: 위 어그리게이터 가격은 Nous 포털 공식 가격이 아니며, OpenRouter/nano-gpt/kilo 등 제3자 플랫폼에서의 가격을 나타냄. Nous 포털의 무료 변형(`:free`)는 $0 비용이 적용됨.

---

## 8. Step 패밀리 비교표 (Nous 포털 기준)

| 모델 | 컨텍스트 | 최대 출력 | 활성 파라미터 | 전체 파라미터 | 멀티모달 | 무료 변형 | 주요 용도 |
|---|---|---|---|---|---|---|---|
| stepfun/step-5-preview | 1M 토큰 | 65,536 토큰 | 27B | 600B | text/image/video | — | 플래그십, 고성능 추론 |
| stepfun/step-5-preview:free | 1M 토큰 | 65,536 토큰 | 27B | 600B | text/image/video | ✅ | 무료 실험 및 개발 |
| stepfun/step-3.7-flash | 128K 토큰 | 8,192 토큰 | 활성화된 값 (추정) | — | text/image | — | 고속 플래시 추론 |
| stepfun/step-3.5-flash | 128K 토큰 | 8,192 토큰 | 활성화된 값 (추정) | — | text/image | — | 경량 플래시 모델 |
| stepfun/step-3.7-flash:free | 128K 토큰 | 8,192 토큰 | 활성화된 값 (추정) | — | text/image | ✅ | 무료 플래시 변형 |

> **요약**: step-5-preview가 플래그십 최상위 모델이며, step-3.7-flash와 step-3.5-flash는 속도와 비용 절감을 위해 짧은 컨텍스트가 필요한 경우에 적합함. 무료 변형은 `:free` 접미사가 붙음.

---