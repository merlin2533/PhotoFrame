# Contributing

## One-time setup: enable the repo's git hooks

This repo ships git hooks under `.githooks/` (not `.git/hooks/`, which git
never tracks/clones). They are **not active until you run this once per
clone**:

```sh
git config core.hooksPath .githooks
```

What they do, on every commit:

- **`pre-commit`** bumps `mobile_app/pubspec.yaml`'s build number (the `+N`
  after the semver, e.g. `0.1.0+1` → `0.1.0+2`) and `relay_server/package.json`'s
  patch version, then stages both so the bump is part of the same commit.
  Only the build number/patch is automatic — bump the semver `X.Y.Z` in
  `mobile_app/pubspec.yaml` yourself when you actually cut a release.
- **`commit-msg`** appends a one-line entry to `CHANGELOG.md` (newest on
  top) using your commit message's summary line and the just-bumped
  version, and stages that too.

Both hooks are best-effort and exit non-fatally if something's missing
(e.g. `node` unavailable) — they will never block a commit outright.

If you ever need to skip them for one commit (e.g. an automated/CI commit
that shouldn't bump versions), use `git commit --no-verify`.
