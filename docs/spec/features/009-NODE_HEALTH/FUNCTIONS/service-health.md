# Home service health — NET / YouTube / OpenAI / Gemini reachability per node

The Home node list can run an explicit service-level check through every visible real node without changing the active selector. The result is shown as four compact independent badges beside the normal latency value.

## Trigger and scope

- The list-wide check starts only from the Home service-check action while the VPN tunnel is up.
- Selecting/opening a group automatically checks only its currently active real node once per tunnel session. This is four requests, not a background list sweep.
- A second tap on the list-wide action cancels the current generation. New nodes are no longer scheduled and late replies from the cancelled generation are ignored.
- `block`, `selector` and `urltest` control nodes are skipped. Ordinary proxy/endpoint nodes and `direct` may be checked.
- At most four nodes are checked in parallel during the list-wide sweep. For one node the four requests run in order: NET → YT → GPT → GEM.
- Neither the active-node check nor the list-wide action switches the selected node or mutates group selection.

## Services and verdicts

| Badge | Probe | Available | Blocked | Technical failure |
|---|---|---|---|---|
| `NET` | Cloudflare `generate_204` | an HTTP response below 500 | — | transport/TLS error, timeout, 5xx |
| `YT` | YouTube `generate_204` | an HTTP response below 500 except explicit deny | HTTP 403/451 | transport/TLS error, timeout, 5xx |
| `GPT` | OpenAI API `/v1/models` without credentials | 2xx/3xx, 401 or 429 | 403 whose body reports `unsupported_country_region_territory` / unsupported-country text | other 403, other HTTP anomaly, transport/TLS error, timeout |
| `GEM` | `gemini.google.com/app` credential-free shell | only a manual/strong authenticated verdict may be green | explicit Gemini country/region block text or saved manual blocked verdict | generic 4xx/5xx, transport/TLS error, timeout; ordinary 2xx/3xx is indeterminate (`~`) |

The GPT badge is a network/region sentinel, not an authenticated ChatGPT session test. Gemini Apps is different: the credential-free web shell may return HTTP 200 before the signed-in account is rejected for country/region. Therefore a bare 2xx/3xx is deliberately `indeterminate` (`GEM~`), never green. `GEM×` requires explicit block evidence or an owner-confirmed manual verdict; `GEM✓` requires an explicit confirmed-available override/strong authenticated verdict.

## UI states

Each service has one of six states: `untested`, `checking`, `available`, `indeterminate`, `blocked`, `failed`. The Home row keeps latency as a separate right-edge value and renders the four service badges immediately before it. The compact labels make the state explicit even before color is noticed: `NET?/YT?/GPT?/GEM?` = untested, `…` = checking, `✓` = confirmed available, `~` = technically reachable but region not proven, `×` = blocked and `!` = technical failure.

The live result map lives only in memory. Stopping or losing the VPN clears all live service-health badges and invalidates every in-flight generation so an answer from the old path cannot repaint the new session. Optional Gemini manual verdicts are normal settings data and persist separately from the live map.

## Guarantees

- No automatic list-wide check on connect, resume, timer, scroll or background lifecycle. The only automatic work is the four-request check of the currently active real node when its group becomes selected.
- Live probe results are not persisted. Only explicit Gemini manual verdict overrides are stored in settings/backup.
- No automatic disabling, filtering or Auto-group mutation based on service results.
- A generic HTTP 403 is never enough to label GPT as a regional block; the unsupported-region response must be recognized explicitly.

## Implementation

- State/classification: `app/lib/models/service_health.dart`
- Orchestration: `app/lib/controllers/home_controller/service_health.dart`
- Home action: `app/lib/screens/home/widgets/home_controls.dart`
- Row rendering: `app/lib/widgets/node_row.dart`
- Classifier tests: `app/test/models/service_health_test.dart`

Revision: task [693](../../../tasks/693-home-service-health-indicators.md).
