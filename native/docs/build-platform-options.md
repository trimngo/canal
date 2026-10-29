# Faster build hosting for Dash

Assessed 2026-10-29 after the user asked about moving CI while retaining agent
control. No provider migration, subscription, or runner registration has happened.
Keep the active GitHub validation/release work running while considering this.

## Recommendation

Benchmark dedicated Apple Silicon Mac workers registered with GitHub Actions
first. This preserves the existing workflow controls, check results, and log access.
Prepared Xcode/tools and reusable compilation outputs may reduce cold setup. An
alternative managed service is Codemagic; choose based on a measured run and the
cost of sufficient parallel workers, rather than advertised CPU speed alone.
Xcode 26 compilation caching is also worth benchmarking on the current host;
Codemagic documents that feature, and adopting a different provider is not a
prerequisite for measuring its benefit. No compilation-cache change is enabled
by this assessment.

Dash currently runs four phone UI shards and Watch on five separate Mac workers.
Replacing this with one sequential worker would lose that parallelism. A dedicated
pool must retain isolated simulator environments. The current scripts select the
first available phone/pair; several jobs cannot safely share those same simulators.
Warm tools/caches should not mean inheriting test app data or permission state.

Build 84's successful full validation took about 52 minutes; signed delivery,
upload, Apple processing, and internal distribution took about 12 minutes. One
later phone retry spent about 13 minutes before its UI suite started and 28 minutes
executing 34 UI tests; it failed a status assertion, so it is not a successful
release benchmark. A new host could reduce setup and some execution time. The
UI workload and Apple's processing still remain. Do not promise a speedup before
running the same source and assertions on the candidate host.

## Options and control

| Option | How the agent can control it | Main tradeoff |
| --- | --- | --- |
| Dedicated Mac workers with GitHub Actions | Existing GitHub connection manages repo workflows and reads job logs after the owner registers the runners. | Hardware/provider cost and ongoing Xcode/OS maintenance; preserve parallelism and simulator isolation. |
| Codemagic M4 | Repository YAML plus its build API after account/API access is configured. | New service setup; sufficient concurrency is essential. Published pay-as-you-go guidance directs users needing more than three concurrent builds to annual/Enterprise options. |
| GitHub larger Mac runners | Existing workflow/log tools after owner setup. | Larger runners require an organization on Team or Enterprise Cloud. This repo is currently under a personal account. Larger runners can also have cold queue allocation. |

Codemagic's documentation lists M4 VM usage at **$0.114 per worker-minute** and
M2 at **$0.095**, with plan-dependent concurrency. For illustration, 200 total M4
worker-minutes would be $22.80 before subscription/concurrency charges or any
allowance. This is not a quote for a Dash run. Its Xcode 26.3 image lists a watchOS
runtime; Dash's actual Watch UI and packaging checks still need to pass there.

Xcode Cloud and Bitrise are other candidates, but their current account access,
required Xcode/runtime availability, and full Watch UI execution have not been
verified for Dash. Do not claim that a platform migration is ready based solely
on a generic iOS build succeeding.

## Benchmark and cutover

1. Select a fully validated commit. Keep existing GitHub CI and delivery active.
2. Compare one complete phone shard and all Watch tests on the same Xcode/runtime
   versions, then the full suite: 501 core, 138 phone UI, and 18 Watch UI tests for the calendar-plan candidate.
   Record queue time, compilation/boot, UI time, exports, failures, and total cost.
   Compare cold and warm runs while keeping simulator test data isolated.
3. Preserve the `Native validation` gate and meaningful assertions. Verify logs
   and results remain readable through the access actually configured for agents.
4. Before moving delivery, validate the signed phone/Watch/extension package on
   the new host. Preserve existing signing settings and allocate a monotonically
   increasing build number; a provider's fresh counter must not restart at 1.
5. Have one uploader per release, retain the existing path as a fallback, and
   verify Apple processing plus internal distribution after cutover. A benchmark
   does not require another TestFlight upload of unchanged application code.

## Evidence

Provider documentation inspected through its official source repositories:

- [GitHub self-hosted runners](https://github.com/github/docs/blob/main/content/actions/concepts/runners/self-hosted-runners.md)
- [Larger Mac runner specifications and allocation](https://github.com/github/docs/blob/main/content/actions/reference/runners/larger-runners.md)
- [Larger runner account requirements](https://github.com/github/docs/blob/main/data/reusables/actions/larger-runner-permissions.md)
- [Codemagic pricing and concurrency](https://github.com/codemagic-ci-cd/codemagic-docs/blob/master/content/billing/pricing.md)
- [Codemagic Builds API](https://github.com/codemagic-ci-cd/codemagic-docs/blob/master/content/rest-api/builds.md)
- [Codemagic Xcode 26.3 image](https://github.com/codemagic-ci-cd/codemagic-docs/blob/master/content/specs-macos/xcode-26-3.md)
- [Codemagic compilation caching](https://github.com/codemagic-ci-cd/codemagic-docs/blob/master/content/knowledge-codemagic/caching.md)

Existing release proof: [build 84 validation](https://github.com/trimngo/canal/actions/runs/40780444339)
and [completed delivery](https://github.com/trimngo/canal/actions/runs/40831279483).
