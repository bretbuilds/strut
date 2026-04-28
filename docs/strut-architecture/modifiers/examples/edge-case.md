# Example: edge case — "just a bug fix" fires trust

## Change request

Fix the bug where invited team members are redirected to a 404 after confirming their email.

## Why this is an edge case

This looks like a straightforward bug fix — no new features, no schema changes, small scope. The instinct is `standard`. But the scan finds the actual files involved, and trust fires from evidence, not intent.

## Scan result (abbreviated)

```json
{
  "skill": "truth-repo-impact-scan",
  "status": "passed",
  "what": "Fix the bug where invited team members are redirected to a 404 after confirming their email",
  "files_to_modify": [
    {
      "path": "app/api/auth/callback/route.ts",
      "reason": "Auth callback handler — processes the email confirmation redirect, currently points to a non-existent route",
      "layer": "server",
      "is_new_file": false
    },
    {
      "path": "app/lib/middleware.ts",
      "reason": "Route middleware — redirect logic after auth events must be updated to match the corrected callback destination",
      "layer": "server",
      "is_new_file": false
    }
  ],
  "risk_signals": {
    "auth": true,
    "rls": false,
    "schema": false,
    "security": false,
    "immutability": false,
    "multi_tenant": false
  },
  "complexity_signals": {
    "layers_touched": ["server"],
    "boundary_crossings": 0,
    "new_file_count": 0
  },
  "summary": "Two server-layer files: the auth callback route and the middleware that redirects after auth events. One risk signal: auth."
}
```

## Classification result

```json
{
  "skill": "truth-classify",
  "status": "classified",
  "what": "Fix the bug where invited team members are redirected to a 404 after confirming their email",
  "modifiers": {
    "trust": true,
    "decompose": false
  },
  "execution_path": "guarded",
  "what_breaks": "A wrong redirect after email confirmation locks out newly invited users, or a misconfigured middleware rule bypasses auth for affected routes",
  "evidence": {
    "risk_signals_true": ["auth"],
    "boundary_crossings": 0,
    "layers_touched": ["server"],
    "trust_rule": "auth true → trust ON",
    "decompose_rule": "boundary_crossings < 2 → decompose OFF"
  }
}
```

## Execution summary

```
CLASSIFICATION COMPLETE
What: Fix the bug where invited team members are redirected to a 404 after confirming their email
What breaks: A wrong redirect after email confirmation locks out newly invited users, or a misconfigured middleware rule bypasses auth for affected routes

Modifiers:
  Trust:     ON — auth
  Decompose: OFF — 0 boundary crossings: [server]

Execution path: guarded
```

## Why this path — and where the instinct goes wrong

The change request frames this as a small bug fix, and the scan confirms it: two files, no schema change, no new files, single layer. Everything points to `standard` — except the files themselves. Both `app/api/auth/callback/route.ts` and `app/lib/middleware.ts` are auth-handling code. The `auth` signal fired from evidence.

The anti-rationalization rule applies here directly: *"the risk signal is true but the change is small, so trust should be OFF — STOP. Any true signal = trust ON. Size doesn't reduce risk."* A mis-aimed redirect in an auth callback can lock out legitimate users or — depending on what the redirect guards — silently skip a check that was supposed to run. Small code change, large blast radius.

Decompose stays OFF because both files are in the same server layer (boundary_crossings: 0). The result is `guarded`: a single implementation pass with a security reviewer and deeper review before merge.
