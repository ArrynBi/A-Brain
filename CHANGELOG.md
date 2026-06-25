# Changelog

All notable changes to A-Brain will be documented in this file.

The format is based on Keep a Changelog, and this project uses Semantic Versioning.

## [Unreleased]

- Reserve this section for post-beta work on adapters, stronger ingest, and overlays.

## [0.1.0-beta.1] - 2026-06-25

### Added

- Seven first-class modules: `diary`, `library`, `ingest`, `knowledge`, `think`, `dream`, `learn`.
- Windows PowerShell command pairs for diary, think, ingest, dream, learn, and smoke verification.
- `examples/` with sanitized `sample-source.md` and `sample-note.md`.
- `AGENTS.example.md` for wiring A-Brain into an agent task loop.
- `scripts/smoke-test.cmd` and `scripts/smoke-test.ps1` for release verification in a temporary copy.

### Changed

- The text-index mode is labeled `local-text`.
- README, bootstrap, commands, and release docs now describe a beta-ready runnable template instead of a scaffold-only state.

### Safety

- Runtime output directories stay `.gitkeep`-only in the source tree after smoke verification.
- `learn` does not create `learn/reviews` and does not install runtime skills.
- Local private config patterns `config/*.local.json` are ignored.
