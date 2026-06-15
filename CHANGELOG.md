# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-06-15

### Added
- Startup action menu for downloading models or checking locally downloaded Docker GGUF blobs.
- Docker Hub variant listing so users can pick tags beyond `latest`.
- Download retry handling for `docker model pull` with a 5 second delay and 10 attempts by default.
- Spinner feedback while retrieving model lists, variants, and local metadata.
- Local GGUF inventory view with grouped model metadata, cropped paths, and incomplete-download skipping.
- Support for `llama-gguf` from Homebrew's `llama.cpp` package, while keeping `gguf_dump` support when available.

### Changed
- Renamed the project and documentation to Docker Model Downloader.
- Show 20 models per page and crop long model names to keep the table readable.
- Use left/right arrows for model-list pagination.
- Filter vLLM-only Docker model entries on macOS because they are not compatible there.
- README now documents the full downloader, retry, local-inspection, and GGUF reuse capabilities.

## [0.5.2] - 2026-03-10

### Changed
- README now uses images from `assets/` (banner, logo, demo GIF).

## [0.5.1] - 2026-03-10

### Added
- MIT license file.

## [0.1.0] - 2025-12-18

### Added
- Initial interactive downloader script (`download_docker_model.sh`).
- Basic README with one-line install/run instructions.

## [0.2.0] - 2025-12-18

### Changed
- README updates (demo/wording).

## [0.3.0] - 2025-12-18

### Changed
- README updates (demo/wording).

## [0.4.0] - 2025-12-18

### Changed
- README updates (demo/wording).

## [0.5.0] - 2026-03-10

### Added
- `.gitignore` for common OS/editor/temp files.
- `jq` prerequisite documented.

### Changed
- Script now fetches the Docker Hub `ai/*` model list on each run (no hardcoded list).
- README now embeds the animated demo GIF.
