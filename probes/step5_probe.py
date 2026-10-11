"""Hermes Step-5 probe: OAuth-token resolver + Step-5 chat probe (stdlib-only).

Usage:
    python probes/step5_probe.py [--model MODEL] [--max-tokens N] [--prompt TEXT] [--timeout SECONDS] [--list-models]

Options:
    --model MODEL           Model ID to use (default: stepfun/step-5-preview:free)
    --max-tokens N          Max tokens to generate (default: 800)
    --prompt TEXT           Prompt to send (default: PING)
    --timeout SECONDS       Request timeout in seconds (default: 180)
    --list-models           List step* model IDs from /v1/models and exit
"""

import argparse
import json
import os
import sys
import time

# Patch: use datetime for ISO format parsing
from datetime import datetime

# ──────────────────────────────────────────────────────────────────────
# Path resolution: HERMES_HOME env, else %LOCALAPPDATA%/hermes (Win), else ~/.local/share/hermes (POSIX)
# ──────────────────────────────────────────────────────────────────────
def resolve_auth_path() -> str:
    """Return absolute path to auth.json."""
    home = os.environ.get("HERMES_HOME", "")
    if not home:
        # Windows
        local = os.environ.get("LOCALAPPDATA", "")
        if local:
            home = os.path.join(local, "hermes")
        else:
            home = os.path.join(os.path.expanduser("~"), ".local", "share", "hermes")
    return os.path.join(home, "auth.json")


# ──────────────────────────────────────────────────────────────────────
# Token loading + expiry detection
# ──────────────────────────────────────────────────────────────────────
def load_auth(auth_path: str) -> dict:
    """Load and return the parsed auth.json dict."""
    with open(auth_path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data


def resolve_token(auth: dict) -> tuple[str, bool]:
    """Resolve the bearer token.

    Returns (token_masked, had_fallback).
    If providers.nous.agent_key exists → use it, masked prefix shown.
    Otherwise fall back to providers.nous.access_token with a warning
    about the 429 gotcha on /v1/chat/completions.
    """
    providers = auth.get("providers", {})
    nous = providers.get("nous", {})

    # Try agent_key first
    agent_key = nous.get("agent_key")
    access_token = nous.get("access_token")

    had_fallback = False
    token = None

    if agent_key:
        token = agent_key
    elif access_token:
        token = access_token
        had_fallback = True
    else:
        print("ERROR: No agent_key or access_token found in auth.json", file=sys.stderr)
        sys.exit(1)

    # Mask: first 6 chars + '...'
    masked = token[:6] + "..." if len(token) > 6 else token + "..."

    if had_fallback:
        print(
            "WARNING: Using access_token as fallback. /v1/chat/completions returns "
            "HTTP 429 when given access_token — you MUST pass agent_key instead. "
            "Run `hermes portal login` to obtain a proper agent_key.",
            file=sys.stderr,
        )

    # Expiry detection
    now = time.time()
    # Check agent_key_expires_at first, then expires_at
    expires_key = None
    expires_val = None
    if agent_key and nous.get("agent_key_expires_at"):
        expires_key = "agent_key_expires_at"
        expires_val = nous[expires_key]
    elif access_token and nous.get("expires_at"):
        expires_key = "expires_at"
        expires_val = nous[expires_key]

    if expires_val:
        try:
            # Use datetime.fromisoformat for reliable ISO 8601 parsing
            dt = datetime.fromisoformat(expires_val)
            exp_time = dt.timestamp()
        except Exception:
            exp_time = 0
        if now >= exp_time:
            print(
                f"ERROR: Token has expired (expires_at={expires_val}). "
                "Run `hermes portal login` to refresh your tokens.",
                file=sys.stderr,
            )
            sys.exit(1)

    return masked, had_fallback


# ──────────────────────────────────────────────────────────────────────
# /v1/models helper (for --list-models)
# ──────────────────────────────────────────────────────────────────────
def list_step_models(auth: dict) -> list[str]:
    """Fetch /v1/models and return sorted step* model IDs."""
    import urllib.request

    token = auth.get("providers", {}).get("nous", {}).get("agent_key") or \
            auth.get("providers", {}).get("nous", {}).get("access_token")

    base = auth.get("providers", {}).get("nous", {}).get("inference_base_url", "https://inference-api.nousresearch.com/v1")
    url = base + "/models"

    req = urllib.request.Request(url)
    # Add Authorization header
    if token:
        req.add_header("Authorization", f"Bearer {token}")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.load(resp)
    except Exception as e:
        print(f"WARN: Could not fetch /v1/models: {e}", file=sys.stderr)
        return []

    models = data.get("data", [])
    step_ids = sorted([m["id"] for m in models if m["id"].startswith("step")])
    return step_ids


# ──────────────────────────────────────────────────────────────────────
# Chat completion helper
# ──────────────────────────────────────────────────────────────────────
def chat_probe(auth: dict, model: str, max_tokens: int, prompt: str, timeout: int) -> dict:
    """Send a chat completion and return the response dict.

    Uses agent_key when available; otherwise access_token (may 429).
    """
    import urllib.request
    import urllib.error

    providers = auth.get("providers", {})
    nous = providers.get("nous", {})
    token = nous.get("agent_key") or nous.get("access_token")

    base = nous.get("inference_base_url", "https://inference-api.nousresearch.com/v1")
    url = base + "/chat/completions"

    payload = {
        "model": model,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers={
        "Content-Type": "application/json",
    })

    if token:
        req.add_header("Authorization", f"Bearer {token}")

    start = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8")
            result = json.loads(body)
    except urllib.error.HTTPError as e:
        print(f"HTTP ERROR {e.code}: {e.reason}", file=sys.stderr)
        if e.code == 429:
            print("Got 429 — this may mean access_token was used instead of agent_key.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"REQUEST FAILED: {e}", file=sys.stderr)
        sys.exit(1)
    elapsed = time.time() - start

    return {
        "latency": elapsed,
        "result": result,
    }


# ──────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────
def main() -> None:
    parser = argparse.ArgumentParser(description="Hermes Step-5 probe")
    parser.add_argument("--model", default="stepfun/step-5-preview:free",
                        help="Model ID (default: stepfun/step-5-preview:free)")
    parser.add_argument("--max-tokens", type=int, default=800,
                        help="Max tokens to generate (default: 800)")
    parser.add_argument("--prompt", default="PING",
                        help="Prompt to send (default: PING)")
    parser.add_argument("--timeout", type=int, default=180,
                        help="Request timeout in seconds (default: 180)")
    parser.add_argument("--list-models", action="store_true",
                        help="List step* models from /v1/models and exit")
    args = parser.parse_args()

    auth_path = resolve_auth_path()
    if not os.path.exists(auth_path):
        print(f"ERROR: auth.json not found at {auth_path}", file=sys.stderr)
        print("Set HERMES_HOME or ensure %LOCALAPPDATA%/hermes/auth.json exists.", file=sys.stderr)
        sys.exit(1)

    auth = load_auth(auth_path)

    # --list-models path
    if args.list_models:
        step_ids = list_step_models(auth)
        for sid in step_ids:
            print(sid)
        sys.exit(0)

    # Token resolution + expiry check
    masked, had_fallback = resolve_token(auth)

    # Re-resolve token for the chat call (resolve_token already checked expiry)
    token = auth.get("providers", {}).get("nous", {}).get("agent_key") or \
            auth.get("providers", {}).get("nous", {}).get("access_token")

    # Proceed to chat probe

    probe = chat_probe(auth, args.model, args.max_tokens, args.prompt, args.timeout)
    result = probe["result"]

    latency = probe["latency"]
    finish_reason = result.get("finish_reason", "unknown")
    usage = result.get("usage", {})
    cost_details = usage.get("cost_details", {})
    source = cost_details.get("source", "unknown")

    # Extract content and reasoning_content
    choices = result.get("choices", [])
    content = ""
    reasoning_content = ""

    if choices:
        msg = choices[0].get("message", {})
        content = msg.get("content", "")
        # reasoning_content may be at the top level or in a special field
        rc = result.get("reasoning_content", "")
        if rc:
            reasoning_content = rc[:200]  # truncate
        else:
            # Some models emit reasoning_content as a choice role
            # Try to find it
            for c in choices:
                if c.get("role") == "assistant" and "reasoning_content" in c:
                    reasoning_content = c.get("reasoning_content", "")[:200]

    # Print results — never print the raw token
    print(f"latency: {latency:.2f}s")
    print(f"finish_reason: {finish_reason}")
    print(f"usage: {json.dumps(usage)}")
    print(f"cost_details.source: {source}")
    if reasoning_content:
        print(f"reasoning_content (truncated): {reasoning_content}")
    print(f"content: {content}")
    print(f"token_resolved: {masked}")

    # Verify we got a valid response
    if finish_reason == "length":
        print("NOTE: finish_reason='length' — consider increasing max_tokens >= 400 "
              "so content is not truncated.", file=sys.stderr)


if __name__ == "__main__":
    main()