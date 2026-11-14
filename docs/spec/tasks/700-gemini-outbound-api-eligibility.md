# Task 700 — Gemini API eligibility of a physical LBox outbound

Status: **draft implementation; redirect leak fixed in sing-box-lx, Go tests PASS; Android/device QA pending**.

## Problem
Monitor currently verifies Gemini API only through the selected node. The
requested inventory must ping every physical server approximately hourly and
check Gemini API only for reachable nodes with unknown/stale regional verdict.
Ping success is NOT evidence of Gemini availability; anonymous web success
is NOT evidence of authenticated Gemini Web eligibility.

Related: issue #6 — per-server Gemini eligibility registry; a clean
mainline branch replaces the obsolete PR #4 route-status stack. The
sing-box-lx security fix is PR #1 — prevent custom-header leaks on redirects.

## Opt-in diagnostic bridge
A new authenticated localhost POST action accepts a known physical node tag,
a kind (ping or API), and for API checks an ephemeral credential parameter.
It allows neither user-provided URLs nor arbitrary proxy operations.
- Core groups and outbounds are read fresh. SELECTOR, URLTEST, DIRECT, BLOCK
  and unknown nodes are rejected.
- Ping uses the active core's URLTest through that physical outbound.
- Gemini verification uses a fixed Google metadata-list endpoint with the
  user key from Monitor's local encrypted store, sent as an HTTPS header.
  The key is transient and never saved, returned, or logged.
- Results are sanitized: actual outbound tag, timestamp, HTTP code, duration,
  and categorical API verdict; raw Google bodies and secrets stay private.
- No selector writes, VPN restarts, NORMAL/WHITELIST changes, Tailscale
  changes or additional Android VPN.
- A successful 200 with model metadata means API available. Only an explicit
  Google unsupported-location response constitutes a regional denial.
  Rate limits, auth/project errors, transport errors and ambiguous responses
  remain separate, and no result proves authenticated web-chat access.

## Native credential safety and rollout gate
The vulnerable sing-box-lx `GetURLViaOutbound` followed cross-origin HTTP
redirects and could forward `x-goog-api-key` to another authority. Core fix
`71063e6` rejects cross-scheme/authority redirects when custom request
headers are present; three new Go regression tests plus full `daemon` tests
pass. An isolated arm64 AAR containing the fix was built on Home PC.

The Android bridge **fails closed**: before sending an API key it hashes the
installed `libbox.so` and only accepts the SHA-256 of the tested arm64 build.
Other/older cores return `core_security_update_required`, surfaced as HTTP
conflict by the authenticated Debug endpoint. The native fingerprint is
cached for the process; headerless diagnostics are unaffected. Future ABI or
release builds must update the fingerprint **only after validating a new
protected native artifact**. Android packaging strips symbols: the raw AAR
`libbox.so` hash differs from the APK's `lib/arm64-v8a/libbox.so` hash. The
runtime guard pins the **APK-packaged** hash from a debug build that uses the
protected core, not the pre-strip hash; any unknown build fails closed.

Android debug APK compilation on Home PC completed after selecting the working
Gradle cache and disabling Kotlin incremental compilation (cross-drive cache
bug). Repeat after this pinned-fingerprint change and compare the APK-native
hash, then perform Pixel A/B checks before installation in production. Confirm
fail-closed when VPN is down, selector remains unchanged, and no POST body/key
appears in Debug access logs.

## Acceptance / evidence
- LBox API only permits core-listed physical outbounds and a fixed host.
- Correctly associates results with the outbound actually tested.
- Does not alter the user's live Gemini/Chrome routing.
- Regression: known good node returns API metadata and known blocked node
  returns an explicit region marker; 429 and generic 403 are not region blocks.
- Companion build/JS unit tests belong to the separate private Monitor PR;
  Flutter/native targeted tests and Pixel QA remain release gates.
