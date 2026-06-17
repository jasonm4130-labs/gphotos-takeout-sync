# Security Policy

## Supported Versions

Only the latest published `0.1.x` image receives security updates. Pin by tag or
digest and update when a new release is published.

| Version          | Supported          |
|------------------|--------------------|
| 0.1.x (latest)   | :white_check_mark: |
| < latest 0.1.x   | :x:                |

## Reporting a Vulnerability

Please report security issues **privately** — do not open a public issue for an
unfixed vulnerability.

- **Preferred:** open a private advisory via GitHub →
  [**Security → Report a vulnerability**](https://github.com/jasonm4130-labs/gphotos-takeout-sync/security/advisories/new).
- **Alternative:** email **jasonm4130@gmail.com** with `gphotos-takeout-sync` in
  the subject line.

Please include the image tag/digest, your deployment method (Compose or `docker
run`), and steps to reproduce. Expect an initial acknowledgement within a few
days; this is a personal-time open-source project, so fixes are best-effort.

## Scope & credential handling

This image handles two long-lived credentials — treat both as secrets:

- **`rclone.conf`** carries a **live Google OAuth refresh token**, equivalent to
  a password for your Google Drive. Anyone with the file can read your Drive.
- **The Immich API key** grants write access to your Immich library.

Design notes relevant to security (see the README's *Security* section for the
full rationale):

- Credentials are read from **files** under `/run/secrets`, never from
  environment variables, so `docker inspect` cannot leak them.
- The container drops privileges to `PUID:PGID` via `su-exec` for the actual
  workload; it runs as root only briefly to fix `/work` ownership and re-stage
  the file secrets readable to the run user.
- The re-staged secret copies live only in the container's ephemeral layer and
  vanish on recreate; your host secret files stay `root:root 0600`.

Never commit `rclone.conf` or your API key. The repo's `.gitignore` excludes
`*.conf`, and secrets should always be supplied at runtime.
