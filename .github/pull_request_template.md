## What & why

<!-- What does this change do, and what problem does it solve? -->

## How to test

<!-- Steps to verify the behaviour by hand, if applicable. -->

## Checklist

- [ ] `shellcheck -x --severity=warning scripts/*.sh` passes
- [ ] `bats tests/` passes
- [ ] Added or updated tests for the change
- [ ] Updated `README.md` **and** `README_ja.md` if behaviour or config changed
- [ ] Bumped `version` in `herdr-plugin.toml` if this is a user-facing change
      (a merge to `main` publishes a release for that version)
