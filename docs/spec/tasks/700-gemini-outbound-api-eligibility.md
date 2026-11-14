# Task 700 — Gemini API eligibility of a physical LBox outbound

Status: **draft implementation; requires native redirect/security review and device QA**.

## Problem
Monitor currently verifies Gemini API only through the selected node. The
requested inventory must ping every physical server approximately hourly and
check Gemini API only for reachable nodes with unknown/stale regional verdict.
Ping success is NOT evidence of Gemini availability; anonymous web success
is NOT evidence of authenticated Gemini Web eligibility.

Related: PR #4 — live route status and manual tests; issue #6 — per-server
Gemini eligibility registry. This change is stacked onto the companion feature
branch, not the LBox release branch.

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

## Security gate — must pass before device rollout
The native/libbox HTTP redirect behavior must be audited to prevent a
credential-bearing request from forwarding its sensitive header to another
origin. Audit Debug API request logging, verify no request bodies are persisted,
and test fail-closed behavior on disconnection. This draft is **not** declared
ready for installation while that redirect question remains unresolved.

## Acceptance / evidence
- LBox API only permits core-listed physical outbounds and a fixed host.
- Correctly associates results with the outbound actually tested.
- Does not alter the user's live Gemini/Chrome routing.
- Regression: known good node returns API metadata and known blocked node
  returns an explicit region marker; 429 and generic 403 are not region blocks.
- Companion build/JS unit tests belong to the separate private Monitor PR;
  Flutter/native targeted tests and Pixel QA remain release gates.
