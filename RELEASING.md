# Releases

Maintainers request a release with an authenticated GitHub CLI:

```sh
./scripts/release.sh patch
```

Accepts `patch`, `minor`, `major`, or a stable `X.Y.Z` version.
Review and merge the generated PR after CI passes. Then another `marimo-eng` member
approves tagging in the protected `release` environment. Preparation needs no environment approval.
See the [maintainer runbook](https://github.com/marimo-team/github-maintenance/blob/main/docs/releases.md) (internal).

## Local preparation

Install Node 22+, Git, Docker with a running local daemon, and the shared
[`gh release-control` command](https://github.com/marimo-team/internal-gh-actions#release-command).
Authenticate with `gh auth login`.

The shortcut prepares fresh `main` in a credential-free Docker container and opens the PR
using your GitHub login. Your checkout stays untouched. Normal PR review and CI still apply.
Use `gh release-control request patch --dry-run` to validate without creating a PR.
Use `gh release-control status` to follow the PR, final approval, and publication.
