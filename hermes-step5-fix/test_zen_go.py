#!/usr/bin/env python3
"""
Zen/Go 공급자 연결 검증기 (2026-10-17)
用法: python3 test_zen_go.py
  - 키 없이: T1~T3 (공개 엔드포인트 상태 + 앱 게이트 확인)
  - OPENCODE_GO_API_KEY 설정 시: T4 (Go 릴레이 실연결: models/usage/chat ping)
  - OPENCODE_ZEN_API_KEY 설정 시: T5 (Zen 콘솔 키 확인)
표준도서관만 사용. Hermes 설치 머신에서 실행 권장.
"""
import json, os, sys, time, urllib.request, urllib.error, uuid

ZEN = "https://opencode.ai/zen/v1"
GO = "https://opencode.ai/zen/go/v1"
UA = "hermes-agent-conn-test/1.0"          # Go는 자체 UA 요구 (범용 SDK명 금지)
SESSION = f"conn-test-{uuid.uuid4().hex[:12]}"

def call(url, method="GET", payload=None, key=None, session=False, timeout=60):
    req = urllib.request.Request(url, method=method, headers={"User-Agent": UA, "Accept": "application/json"})
    if key: req.add_header("Authorization", f"Bearer {key}")
    if session: req.add_header("x-opencode-session", SESSION)
    if payload is not None:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(payload).encode()
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read(4000).decode(errors="replace"), time.time()-t0
    except urllib.error.HTTPError as e:
        return e.code, e.read(2000).decode(errors="replace"), time.time()-t0
    except Exception as e:
        return None, str(e), time.time()-t0

def report(tag, ok, detail):
    print(f"[{'PASS' if ok else 'FAIL'}] {tag}: {detail}")
    return ok

def chat_ping(base, model, key=None):
    return call(f"{base}/chat/completions", "POST",
                {"model": model, "messages": [{"role": "user", "content": "Reply with exactly: pong"}], "max_tokens": 16},
                key=key, session=True)

results = []
print("=" * 62)
print(" T1. 익명 Zen /models (공개 리스팅)")
s, b, dt = call(f"{ZEN}/models")
if s == 200:
    ids = [m["id"] for m in json.loads(b if len(b) < 4000 else "{}").get("data", [])] if len(b) < 4000 else []
    results.append(report("T1", True, f"200 OK ({dt:.1f}s) — 릴레이 생존"))
else:
    results.append(report("T1", False, f"HTTP {s}: {b[:150]}"))

print(" T2. 익명 Zen chat (앱 게이트 확인 — 403 FreeTierError가 '정상' 현재 상태)")
s, b, dt = chat_ping(ZEN, "big-pickle")
gated = (s == 403 and "FreeTierError" in b)
results.append(report("T2", True, f"HTTP {s} → 앱 게이트 활성(zen free는 OpenCode 앱 전용)" if gated
                      else f"예상외 HTTP {s}: {b[:150]} — 게이트 정책 변경 가능성, 상태보고서 갱신 필요"))

print(" T3. Go 릴레이 /models (공개) — step-5-preview 존재 확인")
s, b, dt = call(f"{GO}/models")
if s == 200:
    try:
        ids = [m["id"] for m in json.loads(b)["data"]] if len(b) < 4000 else None
    except Exception:
        ids = None
    has = ("step-5-preview" in b)
    results.append(report("T3", has, f"200 OK, step-5-preview {'포함' if has else '미포함'} ({dt:.1f}s)"))
else:
    results.append(report("T3", False, f"HTTP {s}: {b[:150]}"))

go_key = os.environ.get("OPENCODE_GO_API_KEY", "").strip()
print(f" T4. Go 릴레이 실연결 (OPENCODE_GO_API_KEY {'있음' if go_key else '없음 — 건너뜀'})")
if go_key:
    s, b, dt = call(f"{GO}/models", key=go_key)
    results.append(report("T4a 인증/models", s == 200, f"HTTP {s} ({dt:.1f}s) {'' if s==200 else b[:150]}"))
    s, b, dt = call(f"{GO}/usage", key=go_key)
    if s == 200:
        try:
            u = json.loads(b).get("usage", {})
            win = {k: f"{v.get('percent')}%" for k, v in u.items() if isinstance(v, dict) and v.get("percent") is not None}
            results.append(report("T4b 구독 사용량", True, f"{win or '창 정보 없음'}"))
        except Exception:
            results.append(report("T4b 구독 사용량", True, "200 (파싱 스킵)"))
    else:
        results.append(report("T4b 구독 사용량", False, f"HTTP {s}: {b[:120]}"))
    s, b, dt = chat_ping(GO, "step-5-preview", key=go_key)
    ok = s == 200 and "pong" in b.lower()
    results.append(report("T4c step-5-preview chat ping", ok, f"HTTP {s} ({dt:.1f}s) {'응답 정상' if ok else b[:200]}"))
    s, b, dt = chat_ping(GO, "glm-5.3-flash", key=go_key)
    results.append(report("T4d aux용 glm-5.3-flash ping", s == 200, f"HTTP {s} ({dt:.1f}s)"))
else:
    print("[SKIP] T4: export OPENCODE_GO_API_KEY=... 후 재실행 (opencode.ai/console → Go $10/월 구독 → API 키)")

zen_key = os.environ.get("OPENCODE_ZEN_API_KEY", "").strip()
print(f" T5. Zen 콘솔 키 (OPENCODE_ZEN_API_KEY {'있음' if zen_key else '없음 — 건너뜀'})")
if zen_key:
    s, b, dt = call(f"{ZEN}/models", key=zen_key)
    results.append(report("T5a zen 키/models", s == 200, f"HTTP {s} ({dt:.1f}s)"))
else:
    print("[SKIP] T5")

print("=" * 62)
n_fail = sum(1 for r in results if not r)
print(f"결과: {len(results)-n_fail} pass / {n_fail} fail")
print("""
판정 가이드:
  - T2가 403 FreeTierError = zen free 앱 게이트 정상(예상된 현상). Hermes에서 zen free 직결은 불가.
  - T4 전체 PASS = Go 릴레이로 step-5-preview 실사용 가능 → config.zen-go.yaml 적용 ㄱ
  - T4a 401 = 키 오류/구독 만료. T4c 400 MissingSessionID = Hermes 구버전(v0.21.0) — 업데이트 필요.
  - Go 키가 없는데 무료로 쓰고 싶다면 → setup_opencode_delegate.sh (OpenCode 앱 내 free + Hermes 위임)
""")
sys.exit(1 if n_fail else 0)
