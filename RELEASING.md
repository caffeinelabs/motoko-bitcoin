# Releasing `motoko-bitcoin`

The package is published to Mops as [`bitcoin`](https://mops.one/bitcoin).
Releases are automated: merging a version bump tags, releases, and publishes.

## Release a new version

1. In `mops.toml`, update `version` in the `[package]` section.
2. In `CHANGELOG.md`, add a `## [x.y.z] - YYYY-MM-DD` section for the new
   version.
3. Open a PR with these changes. The `Release tag` workflow
   (`.github/workflows/release-tag.yml`) checks that the version is `x.y.z`,
   that the tag `vx.y.z` doesn't exist yet, and that `CHANGELOG.md` has the
   matching section.
4. Merge the PR. `Release tag` pushes the annotated tag `vx.y.z` on the merge
   commit and creates the GitHub release from the changelog section.
5. The tag push starts `Publish on Mops` (`.github/workflows/mops-publish.yml`).
   It checks that the tag matches `mops.toml`, then runs `mops publish`, which
   runs the tests and benchmarks before uploading.
6. Check that the new version shows on [Mops](https://mops.one/bitcoin), or run
   `mops search bitcoin`.

## Publish an existing tag

`Publish on Mops` checks out the tag, so a re-run from the failed run's page
reuses the workflow file as it was at that tag. To publish a tag again after a
fix to the workflow, merge the fix to `main`, then dispatch the workflow from
`main` with the tag as input:

```bash
gh workflow run "Publish on Mops" --ref main -f tag=v1.2.3
```

The published package is the tagged tree. Only the workflow definition comes
from `main`.

## Setup the workflows depend on

- **`MOPS_IDENTITY_PEM` repo secret.** The Mops identity that publishes. It's
  the DFINITY identity `uajwy-…-tae`, which owns `bitcoin` and `core` on Mops,
  and the same key as `motoko-core`'s secret. It isn't in BWS, so infra doesn't
  manage it: a repo admin sets it by hand, and infra allowlists it
  ([caffeinelabs/infra#4260](https://github.com/caffeinelabs/infra/pull/4260)).
  To list the package owners, run `mops owner list`.
- **`caffeine-ci-generic-rw` GitHub App.** `Release tag` pushes the tag with
  this app's token, because a tag pushed with `GITHUB_TOKEN` doesn't trigger
  other workflows. `GENERIC_CI_RW_APP_ID` and `GENERIC_CI_RW_APP_PRIVATE_KEY`
  are org-wide; the app must also be installed on this repo.
- **Pinned mops version.** `Publish on Mops` pins the mops CLI in
  `mops-version`. mops 3.4.2 and earlier fail to benchmark on `moc` 2 during
  publish (`unknown option '--legacy-persistence'`), so keep it at 3.5.0 or
  later.

## Troubleshooting

- **No tag after merging a release PR.** Check the `Release tag` run on the
  merged PR. If the token step fails, the GitHub App isn't installed on this
  repo, which an org admin has to fix. Until then, push the tag yourself:
  `git tag -a vx.y.z -m "bitcoin x.y.z" <merge-sha> && git push origin vx.y.z`.
- **`mops publish` fails.** Read the run log: the tests or benchmarks failing
  under the pinned mops and `moc` are the usual cause. To reproduce locally,
  run `mops install --locked`, then `mops publish --dry-run`.
