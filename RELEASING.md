# Releases

A merged `release/X.Y.Z` PR approves a release.
The release App creates an annotated `vX.Y.Z` tag at the merge commit.
The tag starts the existing publishing workflow.

## Request a release

1. Run this command with an authenticated GitHub CLI:

   ```sh
   ./scripts/release.sh patch
   ```

   Use `minor`, `major`, or a stable `X.Y.Z` version instead of `patch` when needed.
   The command dispatches `release-pr.yml` on `main`.

2. Ask another `marimo-eng` member to approve the `release` environment request.
3. Review the version changes and CI results in the generated PR.
4. Merge the PR with its `release/X.Y.Z` branch and `release: X.Y.Z` title intact.
5. Ask another `marimo-eng` member to approve the tagging workflow's environment request.
6. Monitor the tagging and publishing workflows in GitHub Actions.

Repository writers can request a release.
The protected environment requires a different `marimo-eng` reviewer for each workflow run.
Repository rules control who can merge the PR.
The App key belongs only to the `release` environment, which permits `main` deployments.

## Retry

If preparation fails because `main` advanced, dispatch it again.
If the release branch already has different changes, inspect the existing PR before continuing.
The workflow does not overwrite conflicting branches or tags.

If tagging fails, rerun the failed tagging workflow after correcting the cause.
If publication fails, rerun the failed publisher jobs.
An existing tag at the same commit is safe to reuse.
A published version or tag must never move to another commit.

The shared [release actions](https://github.com/marimo-team/internal-gh-actions#release-actions)
own PR creation, tag creation, and release identity checks.
