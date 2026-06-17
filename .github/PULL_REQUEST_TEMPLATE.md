## Summary

<!-- One or two sentences describing what this PR does and why. -->

## Type of change

- [ ] Bug fix
- [ ] New feature / enhancement
- [ ] Refactor (no behaviour change)
- [ ] Documentation only
- [ ] CI / build change
- [ ] Dependency update

## Checklist

- [ ] `shellcheck sync.sh entrypoint.sh` passes with no errors or warnings
- [ ] `hadolint Dockerfile` passes (or findings are acknowledged with inline `# hadolint ignore=` comments)
- [ ] Tested locally with `DRY_RUN=1` against a real or mock Immich server
- [ ] `docker compose config` validates without errors on any modified compose examples
- [ ] `CHANGELOG.md` updated with a summary of changes under `[Unreleased]`
- [ ] `README.md` updated if env variables, behaviour, or defaults changed
- [ ] Image version bumped in `Dockerfile` / release tag planned if image behaviour changed
- [ ] No secrets, API keys, tokens, or OAuth credentials committed

## Testing notes

<!-- Describe how you tested this change. Include relevant log output or
     /work/state/last-import.log snippets if applicable. -->

## Related issues

<!-- Closes #<issue number> -->
