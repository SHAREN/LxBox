# Home service health — NET / YouTube / OpenAI reachability per node

The Home node list can run an explicit service-level check through every visible real node without changing the active selector. The result is shown as three compact independent badges beside the normal latency value.

## Trigger and scope

- The list-wide check starts only from the Home service-check action while the VPN tunnel is up.
- Selecting/opening a group automatically checks only its currently active real node once per tunnel session. This is three requests, not a background list sweep.
- A second tap on the list-wide action cancels the current generation. New nodes are no longer scheduled and late replies from the cancelled generation are ignored.
- `block`, `selector` and `urltest` control nodes are skipped. Ordinary proxy/endpoint nodes and `direct` may be checked.
- At most four nodes are checked in parallel during the list-wide sweep. For one node the three requests run in order: NET → YT → GPT.
- Neither the active-node check nor the list-wide action switches the selected node or mutates group selection.

## Services and verdicts

| Badge | Probe | Available | Blocked | Technical failure |
|---|---|---|---|---|
| `NET` | Cloudflare `generate_204` | an HTTP response below 500 | — | transport/TLS error, timeout, 5xx |
| `YT` | YouTube `generate_204` | an HTTP response below 500 except explicit deny | HTTP 403/451 | transport/TLS error, timeout, 5xx |
| `GPT` | OpenAI API `/v1/models` without credentials | 2xx/3xx, 401 or 429 | 403 whose body reports `unsupported_country_region_territory` / unsupported-country text | other 403, other HTTP anomaly, transport/TLS error, timeout |

The GPT badge is a network/region sentinel, not an authenticated ChatGPT session test. It deliberately does not depend on account cookies or API keys.

## UI states

Each service has one of five states: `untested`, `checking`, `available`, `blocked`, `failed`. The Home row keeps latency as a separate right-edge value and renders the three service badges immediately before it. The compact labels make the state explicit even before color is noticed: `NET?/YT?/GPT?` = untested, `…` = checking, `✓` = available, `×` = blocked and `!` = technical failure.

The result map lives only in memory. Stopping or losing the VPN clears all service-health badges and invalidates every in-flight generation so an answer from the old path cannot repaint the new session.

## Guarantees

- No automatic list-wide check on connect, resume, timer, scroll or background lifecycle. The only automatic work is the three-request check of the currently active real node when its group becomes selected.
- No persistence in settings or backup.
- No automatic disabling, filtering or Auto-group mutation based on service results.
- A generic HTTP 403 is never enough to label GPT as a regional block; the unsupported-region response must be recognized explicitly.

## Implementation

- State/classification: `app/lib/models/service_health.dart`
- Orchestration: `app/lib/controllers/home_controller/service_health.dart`
- Home action: `app/lib/screens/home/widgets/home_controls.dart`
- Row rendering: `app/lib/widgets/node_row.dart`
- Classifier tests: `app/test/models/service_health_test.dart`

Revision: task [693](../../../tasks/693-home-service-health-indicators.md).
