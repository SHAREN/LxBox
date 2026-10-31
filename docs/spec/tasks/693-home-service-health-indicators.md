# 693 — Home node service-health indicators

| Field | Value |
|---|---|
| Status | Implemented locally — Flutter/CI/device verification blocked by environment |
| Start date | 2026-10-31 |
| Commits | `cb30073d` — `feat: add per-node service health indicators` |
| Source | Owner request: show per-node service availability directly in the Home VPN node list |
| Related specs | [007-NODE_LIST](../features/007-NODE_LIST/FEATURE.md), [009-NODE_HEALTH](../features/009-NODE_HEALTH/FEATURE.md), [392F node diagnostics](392F-node-diagnostics/) |

## Problem

A latency result only proves that the configured URLTest target can be reached. It does not tell the user whether a particular VPN node can actually reach services that may be filtered independently. In practice a node may have a good ping while YouTube or OpenAI/ChatGPT is unavailable, or OpenAI may return a regional restriction even though generic HTTPS works.

The Home list therefore lacks the service-level information needed to choose a node at a glance.

## Diagnosis

L×Box already has the required transport primitive: `CcChannel.getUrlViaOutbound()` performs an HTTP GET through a specific outbound tag in the live core without switching the active selector. `CcGetUrlResult` preserves HTTP status, response body, elapsed time and transport errors, so OpenAI's `unsupported_country_region_territory` response can be distinguished from a generic 403 or from TLS/network failures.

The core contract deliberately forbids background HTTP sweeps of all nodes. Service checks must therefore be initiated explicitly by the user. The Home mass-ping button is the existing precedent for an explicit list-wide measurement with a bounded concurrency.

## Solution

Add an in-memory service-health snapshot per node and three compact indicators to each ordinary Home node row:

- `NET` — basic HTTPS reachability through the node;
- `YT` — YouTube reachability through the node;
- `GPT` — OpenAI API reachability with semantic recognition of `unsupported_country_region_territory`.

States are `untested`, `checking`, `available`, `blocked`, and `failed`. The row renders them as small neutral/active/green/red/orange badges while keeping latency as a separate right-edge value.

Add an explicit Home action beside mass ping. One tap checks the currently displayed real nodes with a small concurrency cap. A second tap cancels scheduling and discards late results by run generation; already in-flight core requests may finish. No periodic or background sweep is introduced.

Service semantics:

- `NET`: any successful HTTP exchange below 500 is reachable; transport/TLS errors or 5xx are technical failure.
- `YT`: 2xx–4xx except explicit deny statuses are reachable; 403/451 are blocked; transport/TLS errors and 5xx are technical failure.
- `GPT`: 2xx, 401 and 429 are reachable; 403 containing `unsupported_country_region_territory` is region-blocked; other 403/HTTP anomalies are technical failure, not a regional verdict.

Results are session-only and are cleared when the VPN tunnel goes down or the app process restarts. They never disable or hide nodes and do not alter Auto composition.

## Files

- `app/lib/models/service_health.dart` — typed health states/results.
- `app/lib/models/home_state.dart` — per-node in-memory service-health map.
- `app/lib/controllers/home_controller.dart` / `home_controller/service_health.dart` — explicit bounded sweep through outbound tags.
- `app/lib/widgets/node_view_item.dart` / `node_row.dart` — row data and compact indicators.
- `app/lib/screens/home/widgets/node_list.dart` — wire health data into rows.
- `app/lib/screens/home/widgets/home_controls.dart` — explicit check/cancel action.
- `app/test/...` — classifier/state/widget coverage where practical.
- feature docs 007/009 — observable behavior and ownership.

## Risks and edge cases

- Three real HTTP requests per node are materially heavier than latency URLTest, so the feature must remain user-triggered and concurrency-limited.
- A non-2xx HTTP response can still prove reachability. OpenAI regional block must be determined from the response body, not from status 403 alone.
- Auto/selectors and other service/control outbounds are not meaningful service-test targets and must be skipped.
- Cancellation cannot abort an already executing unary `getUrlViaOutbound` call; its result must be ignored after the run generation changes.
- Narrow screens must preserve node name/protocol usefulness and the right-aligned ping; service badges are compact and the protocol remains the first element to yield.

## Verification

Completed locally on 2026-10-31:

1. `git diff --check` — pass.
2. `app/assets/l10n/{ru,zh}/ui.json` — valid JSON with Python's case-sensitive parser.
3. Source audit — `getUrlViaOutbound` is addressed by outbound tag and does not switch the active selector; the implementation has no connect/resume/timer/background trigger.
4. Classifier unit cases are added for NET success, transport failure, YouTube deny, OpenAI 401, unsupported-country 403 and generic 403.

Blocked in the current environment:

- `flutter analyze`, `flutter test` and APK build were not run: Flutter/Dart SDK is not installed in Home PC PATH and was not found in the project/workspace or targeted development directories.
- GitHub CI could not be started from this branch: `origin` is `Leadaxe/LxBox`, push as `SHAREN` is denied with HTTP 403, and `SHAREN/LxBox` does not currently exist as a fork.
- Device acceptance therefore remains pending: badge layout on the phone, real NET/YT/GPT responses, cancellation during live requests and tunnel-down clearing must be confirmed on an APK built from this commit.
