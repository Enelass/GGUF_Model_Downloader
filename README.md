# GGUF Model Downloader

**macOS 14+ · MIT · v0.5.0**

Interactive script to download GGUF AI models via Docker and import them into Ollama.

![GGUF Model Downloader demo](GGUF%20Model%20Downloader-medium.gif)

## Prerequisites

- **Docker Desktop** must be installed and running
- **jq** is required (used to parse the Docker Hub API)
- **Ollama** (optional) to run the downloaded models

## Installation & Usage

Run with a single command:

```bash
bash <(curl -s https://raw.githubusercontent.com/Enelass/GGUF_Model_Downloader/refs/heads/main/download_docker_model.sh)
```

## Changelog / Releases

- Changelog: `CHANGELOG.md`
- Release process: `RELEASING.md`

## Features

- Fetches an up-to-date list of Docker Hub `ai/*` models every run
- Browse dozens of AI models (Qwen, DeepSeek, Gemma, LLaMA, Mistral, etc.)
- Interactive menu with arrow key navigation
- Automatic GGUF file detection
- Ready-to-use Ollama import commands

## Navigation

- **Arrow keys**: Navigate pages
- **Number + Enter**: Select model
- **q**: Quit

That's it. Run the script, pick a model, and follow the on-screen instructions.
