# Contributing to gphotos-takeout-sync

Thank you for considering a contribution. This document covers the local dev
workflow, coding conventions, how to test changes, and how to open a PR.

## Local dev setup

You need:

- **Docker** (BuildKit enabled — `DOCKER_BUILDKIT=1`)
- **shellcheck** — `brew install shellcheck` / `apt install shellcheck`
- **hadolint** — `brew install hadolint` / download from
  [github.com/hadolint/hadolint](https://github.com/hadolint/hadolint/releases)

No other toolchain is required; everything runs inside the image.

## Building the image locally

```bash
docker build -t gphotos-takeout-sync:dev .
```

The build downloads `immich-go` and `supercronic` from GitHub Releases and
verifies their checksums. It requires internet access.

## Testing a change

### 1 — Lint before anything else

```bash
shellcheck sync.sh entrypoint.sh
hadolint Dockerfile
```

Both must pass clean (zero findings). The CI lint job will reject any PR that
does not.

### 2 — Dry-run backfill against a sample Takeout

Extract a small Google Takeout archive (or use a folder of photos with `.json`
sidecars) and run a one-shot import with `DRY_RUN=1`:

```bash
docker run --rm \
  -e DRY_RUN=1 \
  -e IMMICH_SERVER=http://<your-immich-host>:2283 \
  -v /path/to/extracted-takeout:/backfill:ro \
  -v /path/to/immich_api_key.txt:/run/secrets/immich_api_key:ro \
  -v gphotos-work:/work \
  gphotos-takeout-sync:dev backfill
```

Confirm in the output that assets are discovered and that `last-import.log` and
`state/metrics` are written to the volume. With `DRY_RUN=1` no assets are
uploaded to Immich.

### 3 — Metrics sanity check

```bash
docker run --rm -v gphotos-work:/work alpine cat /work/state/metrics
```

You should see four `KEY=value` lines: `gphotos_sync_exit_code`,
`gphotos_sync_assets_imported`, `gphotos_sync_last_success`,
`gphotos_sync_last_run`.

### 4 — rclone drive mode (optional, needs Drive credentials)

If you are testing the `drive` source path, mount your `rclone.conf` and set
`SYNC_SOURCE=drive`:

```bash
docker run --rm \
  -e SYNC_SOURCE=drive \
  -e DRY_RUN=1 \
  -e RCLONE_REMOTE=gdrive:Takeout \
  -e IMMICH_SERVER=http://<your-immich-host>:2283 \
  -v /path/to/rclone.conf:/run/secrets/rclone_conf:ro \
  -v /path/to/immich_api_key.txt:/run/secrets/immich_api_key:ro \
  -v gphotos-work:/work \
  gphotos-takeout-sync:dev
```

## Coding conventions

### Shell scripts (`sync.sh`, `entrypoint.sh`)

- `#!/bin/bash` with `set -euo pipefail` at the top of every script.
- 4-space indentation.
- All variable expansions quoted (`"${VAR}"`); use `:?` guards for variables
  that must be set (`"${ZIP_DIR:?}/file"`).
- `log()` helper for all output — never raw `echo` for diagnostic messages.
- Secrets are read from files; never stored in variables longer than necessary;
  never passed on command lines if an env-var alternative exists.
- Run `shellcheck` before committing. No `# shellcheck disable` without a
  comment explaining why.

### Dockerfile

- 4-space indentation, per `.editorconfig` (YAML/JSON elsewhere in the repo use
  2-space).
- Minimise layers: group related `RUN` steps.
- Every tool download must verify a checksum.
- No `ADD` for remote URLs — use `curl` inside `RUN`.
- Run `hadolint Dockerfile` before committing.

### Workflow YAML (`.github/workflows/`)

- 2-space indentation.
- Do not add secrets to workflow files; use `${{ secrets.* }}` references only.

### Commit messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Common types: `feat`, `fix`, `docs`, `ci`, `chore`, `refactor`.

Examples:

```
feat(sync): add arm64 support via TARGETARCH build arg
fix(entrypoint): log chown failure instead of silently continuing
docs: add docker-compose example to README
ci: pin action SHAs for supply-chain hardening
```

The commit message drives the changelog; keep the summary line under 72
characters.

## Release process

Releases are fully automated via GitHub Actions on Blacksmith runners:

1. Decide the next version following [semver](https://semver.org/):
   - **patch** (`0.1.x`) — bug fixes, dependency bumps, docs.
   - **minor** (`0.x.0`) — new features, new env vars, behaviour changes that
     are backward-compatible.
   - **major** (`x.0.0`) — breaking changes (removed env vars, changed secret
     paths, incompatible immich-go invocation).

2. Update `CHANGELOG.md` with the new version section before tagging.

3. Tag and push:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

4. The `build-and-push` workflow triggers automatically on the `v*` tag. It
   builds the image on Blacksmith, pushes to
   `ghcr.io/jasonm4130-labs/gphotos-takeout-sync`, and tags it with the full
   semver (`0.2.0`), the major.minor (`0.2`), and a short `sha-` prefix.
   `docker/metadata-action` strips the leading `v`, so the GHCR tag is `0.2.0`
   not `v0.2.0`.

5. Publish a GitHub Release (draft from the tag page) linking to the relevant
   `CHANGELOG.md` section.

## PR checklist

Before opening a PR, verify:

- [ ] `shellcheck sync.sh entrypoint.sh` passes with zero findings.
- [ ] `hadolint Dockerfile` passes with zero findings.
- [ ] The image builds locally (`docker build -t gphotos-takeout-sync:dev .`).
- [ ] A `DRY_RUN=1` backfill run completes and writes valid metrics.
- [ ] `CHANGELOG.md` has an entry in the `[Unreleased]` section.
- [ ] Commit messages follow the Conventional Commits format.

## Opening issues

Use the GitHub issue templates (bug report or feature request). For bugs,
include:

- Image tag or git SHA you are running.
- The `docker run` / Compose snippet (redact secrets).
- The relevant lines from `/work/state/last-import.log`.
- Expected vs. actual behaviour.
