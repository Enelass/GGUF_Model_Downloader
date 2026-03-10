<p align="center">
  <img src="assets/logo.png" alt="GGUF Model Downloader logo" width="160" />
</p>

# GGUF Model Downloader

![Bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnu-bash&logoColor=white)
![Docker](https://img.shields.io/badge/docker-required-2496ED?logo=docker&logoColor=white)
![jq](https://img.shields.io/badge/jq-required-000000?logo=jq&logoColor=white)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/Enelass/GGUF_Model_Downloader?display_name=tag)](https://github.com/Enelass/GGUF_Model_Downloader/releases)

Interactive script to download GGUF AI models via Docker and import them into Ollama.

![GGUF Model Downloader demo](assets/DockerGGUFDownloader-demo.gif)

## Prerequisites

- **Bash** (macOS ships Bash 3.2)
- **Docker Desktop** must be installed and running
- **jq** (used to parse the Docker Hub API)
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

![GGUF Model Downloader banner](assets/banner.png)
