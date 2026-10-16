#!/usr/bin/env python3
"""
patch_hermes_yaml.py — ~/.hermes/config.yaml 구조 패치 (백업 + diff 출력)
  1) providers: 아래 zen-proxy(cli-opencode-proxy) 등록
  2) MoA reference 의 사망 항목 재배선:
       provider: nous + stepfun/step-5-preview:free  → zen-proxy/big-pickle
       provider: opencode-free + muse-spark-1.3...   → zen-proxy/muse-spark-1.3-contributor-free
  3) delegation.fallback_providers 맨 앞에 zen-proxy/muse-spark-1.3-contributor-free 추가
텍스트 기반(비파괴) 변환 — secret 을 읽지 않고, 건드리지 않는다.
用法: python3 patch_hermes_yaml.py ~/.hermes/config.yaml
"""
import re, sys, shutil, difflib, time, os

path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.hermes/config.yaml")
src = open(path, encoding="utf-8").read()
orig = src
changes = []

ZEN_BLOCK = """  zen-proxy:
    name: OpenCode Zen Free (cli-opencode-proxy)
    base_url: http://127.0.0.1:18080/v1
    api_key: zen-local
    api_mode: chat_completions
    discover_models: true
    models:
      mimo-v2.6-flash-free:
        context_length: 262144
      glm-5.3-flash-free:
        context_length: 131072
      muse-spark-1.3-contributor-free:
        context_length: 131072
      big-pickle:
        context_length: 131072
"""

# 1) providers: 섹션에 zen-proxy 추가 (이미 있으면 스킵)
if re.search(r"^  zen-proxy:", src, re.M):
    changes.append("zen-proxy: 이미 존재 — 스킵")
elif re.search(r"^providers:", src, re.M):
    src = re.sub(r"^providers:\n", "providers:\n" + ZEN_BLOCK, src, count=1, flags=re.M)
    changes.append("providers.zen-proxy 등록")
else:
    src = "providers:\n" + ZEN_BLOCK + src
    changes.append("providers: 섹션 신설 + zen-proxy 등록")

# 2) MoA 사망 reference 교체 (두 들여쓰기 변형 모두 처리)
pat_nous = re.compile(
    r"( *)- provider: nous\n( *)model: stepfun/step-5-preview:free\n( *)enabled: true")
def rep_nous(m):
    i = m.group(1)
    return f"{i}- provider: zen-proxy\n{m.group(2)}model: big-pickle\n{m.group(3)}enabled: true"
src, n1 = pat_nous.subn(rep_nous, src)

pat_ocfree = re.compile(
    r"( *)- provider: opencode-free\n( *)model: muse-spark-1\.3-contributor-free\n( *)enabled: true")
def rep_ocfree(m):
    i = m.group(1)
    return (f"{i}- provider: zen-proxy\n{m.group(2)}model: muse-spark-1.3-contributor-free\n"
            f"{m.group(3)}enabled: true")
src, n2 = pat_ocfree.subn(rep_ocfree, src)
changes.append(f"MoA reference 교체: nous/step-5-free ×{n1}, opencode-free ×{n2}")

# 3) delegation.fallback_providers 첫 항목으로 zen-proxy 추가
if "model: muse-spark-1.3-contributor-free\n" in src and re.search(
        r"delegation:\n(?:.*\n)*?  fallback_providers:\n    - provider: zen-proxy", src):
    changes.append("delegation.fallback zen-proxy: 이미 존재 — 스킵")
else:
    src, n3 = re.subn(r"(delegation:\n(?:[^\n]*\n)*?  fallback_providers:\n)",
                      r"\1    - provider: zen-proxy\n      model: muse-spark-1.3-contributor-free\n",
                      src, count=1)
    changes.append(f"delegation.fallback_providers zen-proxy 선두 추가 ×{n3}")

if src == orig:
    print("변경 없음 (이미 패치됨 또는 대상 패턴 없음)"); sys.exit(0)

bak = f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
shutil.copy2(path, bak)
open(path, "w", encoding="utf-8").write(src)

print(f"백업: {bak}")
print("변경 내역:")
for c in changes: print("  -", c)
print("\n--- diff ---")
sys.stdout.writelines(difflib.unified_diff(orig.splitlines(keepends=True),
                                           src.splitlines(keepends=True),
                                           "before", "after", n=2))
print("\n✔ 패치 완료 — hermes config check 로 검증하세요")
