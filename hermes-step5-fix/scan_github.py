#!/usr/bin/env python3
"""
GitHub 계정 스캐너 — hermes/opencode/zen/step-5 관련 자산 전수 조사
用法: GITHUB_TOKEN=ghp_xxx python3 scan_github.py
  - 토큰은 환경변수로만 사용, 어떤 파일에도 기록하지 않음
  - 산출물: github-scan-report.md (토큰 미포함)
표준도서관만 사용.
"""
import json, os, re, sys, time, urllib.request, urllib.error, urllib.parse, base64
from datetime import datetime, timezone

TOKEN = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
if not TOKEN:
    print("GITHUB_TOKEN 환경변수 필요: GITHUB_TOKEN=... python3 scan_github.py"); sys.exit(2)

API = "https://api.github.com"
HDRS = {"User-Agent": "hermes-asset-scanner/1.0", "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {TOKEN}", "X-GitHub-Api-Version": "2022-11-28"}
KEYWORDS = ["hermes", "opencode", "zen", "step-5", "step5", "stepfun", "llm-agent", "auxiliary"]
CODE_QUERIES = ["OPENCODE_GO_API_KEY", "OPENCODE_ZEN_API_KEY", "step-5-preview", "opencode-zen",
                "fallback_providers", "hermes config", "opencode run", "zen/go/v1"]
FILE_PATTERNS = re.compile(r"(config\.ya?ml|\.env\.example|\.sh$|hermes|opencode|zen|delegate|setup|README)", re.I)
report = []
def log(s=""):
    print(s); report.append(s)

def get(url, raw=False, retries=3):
    for a in range(retries):
        req = urllib.request.Request(url, headers=HDRS)
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                remaining = r.headers.get("X-RateLimit-Remaining")
                body = r.read().decode(errors="replace")
                if remaining is not None and int(remaining) < 3:
                    reset = int(r.headers.get("X-RateLimit-Reset", "0"))
                    wait = max(reset - time.time(), 1)
                    if wait < 120: print(f"  (rate limit — {wait:.0f}s 대기)"); time.sleep(wait + 1)
                return body if raw else json.loads(body)
        except urllib.error.HTTPError as e:
            if e.code in (403, 429) and a < retries - 1:
                ra = e.headers.get("Retry-After")
                wait = int(ra) if ra and ra.isdigit() else 20 * (a + 1)
                print(f"  (secondary rate limit — {wait}s 대기)"); time.sleep(wait); continue
            return {"__error__": e.code, "__body__": e.read(300).decode(errors="replace")}
        except Exception as e:
            if a < retries - 1: time.sleep(3); continue
            return {"__error__": str(e)}
    return {"__error__": "retries exhausted"}

log(f"# GitHub 스캔 보고서 — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}")

# ---- 1) 계정 확인 ----
me = get(f"{API}/user")
if "__error__" in me:
    log(f"\n[FAIL] 토큰 인증 실패: {me}"); open("github-scan-report.md","w").write("\n".join(report)); sys.exit(1)
login = me.get("login","?")
log(f"\n계정: **{login}** ({me.get('name') or ''}) · 공개레포 {me.get('public_repos')} · 플랜 {(me.get('plan') or {}).get('name','?')}")

# ---- 2) 전체 레포 (fork/private 포함) ----
repos, page = [], 1
while True:
    batch = get(f"{API}/user/repos?per_page=100&sort=pushed&page={page}&affiliation=owner,collaborator,organization_member")
    if not isinstance(batch, list) or not batch: break
    repos += batch
    if len(batch) < 100: break
    page += 1
log(f"\n## 레포 인벤토리 ({len(repos)}개, push순)")
interesting = []
for r in repos:
    name = r["full_name"]; desc = (r.get("description") or "")[:80]
    fork = "(fork)" if r.get("fork") else ""
    hay = f"{name} {desc}".lower()
    hit = [k for k in KEYWORDS if k in hay]
    starred = " ★관련" if hit or r.get("fork") else ""
    log(f"- {name} {fork} — {desc}{starred}")
    if hit or (r.get("fork") and any(k in (r.get("parent",{}).get("full_name","")).lower() for k in ["hermes","opencode"])):
        interesting.append(r)

# ---- 3) 코드 검색 (인증 필요 — 지금이 그 용도) ----
log(f"\n## 코드 검색")
found_code = {}
for q in CODE_QUERIES:
    res = get(f"{API}/search/code?q={urllib.parse.quote(q)}+user:{login}&per_page=20")
    items = res.get("items", []) if isinstance(res, dict) else []
    if items:
        log(f"\n### `{q}` → {res.get('total_count', len(items))}건")
        for it in items[:20]:
            log(f"- {it['repository']['full_name']} :: `{it['path']}`")
            found_code.setdefault(it['repository']['full_name'], set()).add(it['path'])
    else:
        log(f"- `{q}` → 0건")
    time.sleep(7)   # code search: 10 req/min (authenticated)

# ---- 4) 관심 레포 파일 탐색 (hermes/opencode 설정·스크립트 회수) ----
log(f"\n## 관심 레포 파일 내용")
targets = {r["full_name"] for r in interesting} | set(found_code.keys())
salvaged = []
for full in sorted(targets):
    tree = get(f"{API}/repos/{full}/git/trees/HEAD?recursive=1")
    paths = [t["path"] for t in (tree.get("tree") or []) if t.get("type") == "blob"] if isinstance(tree, dict) else []
    if not paths:
        log(f"- {full}: 트리 조회 불가 ({tree.get('__error__') if isinstance(tree,dict) else '?'})"); continue
    cand = [p for p in paths if FILE_PATTERNS.search(p) and not p.startswith(("node_modules",".git"))][:40]
    if cand:
        log(f"\n### {full} ({len(paths)}파일 중 후보 {len(cand)})")
        for p in cand[:15]: log(f"  - `{p}`")
        # config.yaml / .env.example 류는 내용 회수 (작은 파일만)
        for p in cand:
            if re.search(r"(config\.ya?ml|\.env\.example|delegate|setup.*\.sh$)", p, re.I):
                content = get(f"{API}/repos/{full}/contents/{urllib.parse.quote(p)}")
                if isinstance(content, dict) and content.get("content"):
                    try:
                        txt = base64.b64decode(content["content"]).decode(errors="replace")
                        if len(txt) < 20000:
                            fn = f"recovered/{full.replace('/','__')}__{p.replace('/','_')}"
                            os.makedirs("recovered", exist_ok=True)
                            # 회수 파일에서 비밀값은 마스킹
                            txt = re.sub(r"(?i)(key|token|secret|password)\s*[:=]\s*\S+", r"\1=<REDACTED>", txt)
                            open(fn, "w").write(txt)
                            salvaged.append(fn)
                            log(f"  ↳ 회수: `{fn}` (비밀값 마스킹됨)")
                    except Exception as e:
                        log(f"  ↳ 디코드 실패 {p}: {e}")
                time.sleep(1)

# ---- 5) gists ----
g = get(f"{API}/gists?per_page=30")
if isinstance(g, list) and g:
    log(f"\n## Gists ({len(g)}건)")
    for x in g:
        files = ", ".join(list((x.get("files") or {}).keys())[:4])
        log(f"- {(x.get('description') or '(무제)')[:70]} :: {files}")

log(f"\n---\n회수 파일 {len(salvaged)}개 (recovered/ 디렉토리, 비밀값 마스킹 적용).")
log("⚠️ 스캔 완료 후 토큰은 github.com/settings/tokens 에서 즉시 revoke 권장.")
open("github-scan-report.md", "w").write("\n".join(report))
print("\n[OK] github-scan-report.md 저장 완료")
