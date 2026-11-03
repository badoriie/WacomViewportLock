---
name: check-quality
description: After pushing to GitHub, wait for the SonarCloud analysis of that commit (and the Release workflow on main), list every failure, open issue and security hotspot, and fix them. Use after every push to main or a PR branch of WacomViewportLock, or when the user asks about release or SonarCloud status.
---

# Check SonarCloud (and releases) after a push

SonarCloud analyses every push automatically through its GitHub app (project key `badoriie_WacomViewportLock`, public). It has no config in the repo. The quality gate fails on any new issue that lowers the security, reliability or maintainability rating.

Run from the repo root.

## 1. Wait for the checks on the pushed commit

```sh
sha=$(git rev-parse HEAD)
gh api "repos/badoriie/WacomViewportLock/commits/$sha/check-runs" \
  -q '.check_runs[] | "\(.name) | \(.status) | \(.conclusion)"'
```

Expect `SonarCloud Code Analysis`. There is no CI workflow on pushes or PRs; lint, build and tests run in the pre-commit hook. On `main`, the `Release` workflow also runs: it updates the release PR, and after a release PR merge it builds and publishes. Wait for it with `gh run watch <id> --exit-status` (find the ID with `gh run list --limit 3`), and read a failed run with `gh run view <id> --log-failed`.

## 2. SonarCloud quality gate, issues and hotspots

Wait until SonarCloud's `analysisDate` is at or after the push, so you don't read stale results:

```sh
curl -s "https://sonarcloud.io/api/components/show?component=badoriie_WacomViewportLock" | jq -r .component.analysisDate
```

Then:

```sh
curl -s "https://sonarcloud.io/api/qualitygates/project_status?projectKey=badoriie_WacomViewportLock" \
  | jq '.projectStatus | {status, failing: [.conditions[] | select(.status != "OK")]}'
curl -s "https://sonarcloud.io/api/issues/search?componentKeys=badoriie_WacomViewportLock&resolved=false&ps=500" \
  | jq -r '"total=\(.total)", (.issues[] | "\(.severity) \(.type) \(.rule) \(.component | sub(".*:";"")):\(.line // "-") | \(.message)")'
curl -s "https://sonarcloud.io/api/hotspots/search?projectKey=badoriie_WacomViewportLock&status=TO_REVIEW&ps=500" \
  | jq -r '"hotspots=\(.paging.total)", (.hotspots[]? | "\(.vulnerabilityProbability) \(.component | sub(".*:";"")):\(.line // "-") | \(.message)")'
```

## 3. Fix everything

- Fix **all** open issues and hotspots, not only the ones that fail the gate. Then run lint, build and tests (`swift format lint --strict -r Sources Tests scripts Package.swift`, `swift build`, `swift test`), commit, push, and repeat this skill until the gate is `OK` with 0 open issues (and, on `main`, the `Release` workflow is green).
- Known fixes:
  - `githubactions:S7694` (unpinned dependency): pin every `uses:` to a full commit SHA with a `# vX.Y.Z` comment. Resolve the SHA with `gh api repos/<owner>/<repo>/commits/<tag> -q .sha`. Dependabot updates SHA pins.
    The same rule flags `swift build` / `swift test` without locked resolution: always pass `--only-use-versions-from-resolved-file` (works even with no dependencies and no `Package.resolved`).
  - `swift:S1075` (hard-coded path): don't embed absolute tool paths; look tools up on `PATH` (see `findExecutable` in `scripts/make_icon.swift`).
  - `swift:S1172` (unused parameter) in overrides, delegate methods and C callbacks: keep the argument label and drop the internal name (`with _: NSEvent`, `_: Notification`, `init?(coder _: NSCoder)`, `proxy _: CGEventTapProxy`).
- If a finding is a genuine false positive, explain why to the user. Marking issues as false positives needs a SonarCloud token, which isn't available here, so the user does that in the SonarCloud UI.

## Report

Tell the user the Release workflow result (if one ran), the quality-gate status, what was fixed, and anything left for them.
