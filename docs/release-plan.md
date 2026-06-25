# A-Brain Release Plan

## Public Release

- Track name: `Public`
- Repository target: Arryn GitHub account
- First trial version: `v0.1.0-beta.1`
- Goal: let new users clone the repo, wire `AGENTS.example.md`, run `smoke-test`, and experience the seven-module workflow without any private dependencies

### Public Release Checklist

1. Ensure `README.md`, `AGENTS.example.md`, `examples/`, and `scripts/smoke-test.*` are current.
2. Run `.\scripts\smoke-test.cmd`.
3. Confirm runtime directories remain `.gitkeep`-only.
4. Confirm no private paths, old product names, or local secrets appear in docs or examples.
5. Initialize git, create the GitHub repo, push `main`, and create tag `v0.1.0-beta.1`.
6. Publish release notes from `docs/releases/v0.1.0-beta.1.md`.

## Personal Release

- Track name: `Personal`
- Distribution: private repo, private branch, or local-only overlay
- Versioning suggestion: `0.1.0-dev.YYYYMMDD.N`
- Goal: keep fast iteration for personal adapters, session importers, experimental learn flows, and private operating knowledge without contaminating the public template

### Personal Track Boundaries

- May include private adapters and agent-specific automation.
- May move faster than public docs and semver promises.
- Should not be pushed back into public unless generalized, de-identified, and smoke-tested.

## Recommended Near-Term Version Line

- `v0.1.0-beta.1`: first public trial release
- `v0.1.0`: after first external feedback and doc polish
- `v0.2.0`: stronger adapters and deeper ingest / learn refinement
- `v1.0.0`: stable public contracts for template structure, commands, and review flow
