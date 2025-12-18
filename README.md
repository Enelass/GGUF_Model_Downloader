# GGUF Model Downloader via Docker

A user-friendly bash script to download GGUF AI models using Docker and import them into Ollama.

## Overview

This script simplifies the process of downloading GGUF (GPT-Generated Unified Format) models via Docker's AI model repository. It provides an interactive interface to browse, select, and download from 52+ available AI models including popular options like Qwen3, DeepSeek, Gemma3, LLaMA, Mistral, and more.

Based on the official documentation: [Import GGUF in Ollama](https://commbank.atlassian.net/wiki/spaces/SBD/pages/1838219833/Import+GGUF+in+Ollama)

## Features

- 📋 Interactive menu with 52+ pre-configured AI models
- 🔍 Model details including stars, pull counts, and descriptions
- ⌨️ Keyboard navigation with arrow keys or number selection
- 📄 Paginated display (10 models per page)
- 📦 Automatic GGUF file detection after download
- 📝 Step-by-step import instructions for Ollama
- 🎨 Color-coded output for better readability
- ✅ Built-in Docker validation

## Prerequisites

- **Docker Desktop**: Must be installed and running
  - Download: https://www.docker.com/products/docker-desktop
- **Ollama** (optional): For running the downloaded models
  - Download: https://ollama.ai/
- **Bash**: macOS or Linux environment

## Installation

1. Clone or download this repository:
```bash
git clone <repository-url>
cd GGUF_Model_Downloader
```

2. Make the script executable:
```bash
chmod +x download_docker_model.sh
```

## Usage

Run the script:
```bash
./download_docker_model.sh
```

### Navigation

- **Arrow Keys** (↑/↓ or ←/→): Navigate between pages
- **p/n**: Previous/Next page
- **Number + Enter**: Select a model by typing its number (1-52)
- **q**: Quit the script

### Example Session

```bash
$ ./download_docker_model.sh

╔════════════════════════════════════════════════════════════════╗
║            GGUF Model Downloader via Docker                    ║
╚════════════════════════════════════════════════════════════════╝

📋 Available Docker AI Models (Page 1 of 6):

#    Model Name                          Stars   Pulls   Description
---- ----------------------------------- ------  -------- -------------------------------------------------
1)   all-minilm-l6-v2-vllm                   1     1,157   all-MiniLM-L6-v2 is a sentence-transformers model
2)   deepcoder-preview                      10    33,680   DeepCoder-14B-Preview is a code reasoning LLM...
...

Enter choice: 1
```

## What Happens During Download

1. **Docker Pull**: The script executes `docker model pull ai/<model-name>`
2. **File Storage**: Models are downloaded to `~/.docker/models/blobs/sha256/`
3. **GGUF Detection**: The script automatically identifies GGUF files using magic bytes (47 47 55 46)
4. **Import Instructions**: Provides ready-to-use commands for Ollama import

## After Download

The script will display the location of downloaded GGUF files and provide next steps:

### Single Model Files
```bash
# 1. Create a Modelfile
echo "FROM /path/to/model.gguf" > Modelfile

# 2. Import to Ollama
ollama create model-name -f Modelfile

# 3. Run the model
ollama run model-name
```

### Multimodal Models (Multiple GGUF Files)
For models with vision or multimodal capabilities:
```bash
# 1. Create a Modelfile with main model and adapters
FROM /path/to/main-model.gguf
ADAPTER /path/to/vision-adapter.gguf

# 2. Import to Ollama
ollama create model-name -f Modelfile

# 3. Run the model
ollama run model-name
```

## Available Models (52+)

The script includes popular models such as:

- **Qwen3**: Top-tier coding, math, reasoning (344K pulls)
- **DeepSeek R1 Distill LLaMA**: Fast and optimized (153K pulls)
- **Gemma3**: Google's latest small yet powerful model (427K pulls)
- **GPT-OSS**: OpenAI's open-weight reasoning models (297K pulls)
- **SmolLM2**: Tiny LLM for edge devices (234K pulls)
- **LLaMA 3.2/3.3**: Meta's latest chat-focused models
- **Phi4**: Microsoft's compact reasoning model
- **Mistral**: Efficient open model with fast inference

And many more including embedding models, multimodal models, and specialized variants.

## Storage Management

- GGUF files are initially stored in Docker's blob storage
- After importing to Ollama, files are copied to `~/.ollama/models`
- You can safely delete Docker blobs after successful import to save disk space

## Troubleshooting

### Docker Command Not Found
```bash
❌ Error: Docker command not found!
```
**Solution**: Install Docker Desktop from https://www.docker.com/products/docker-desktop

### No GGUF Files Found
If the script can't automatically detect GGUF files, manually search using:
```bash
find ~/.docker/models/blobs/sha256 -type f -exec sh -c 'head -c 4 "$1" | xxd | grep -q "4747 5546" && echo "$1"' _ {} \;
```

### Docker Pull Fails
- Ensure Docker Desktop is running
- Check your internet connection
- Verify disk space availability

## Technical Details

- **File Format**: GGUF (GPT-Generated Unified Format)
- **Magic Bytes**: GGUF files start with hex `47 47 55 46`
- **Storage Path**: `~/.docker/models/blobs/sha256/`
- **Detection Window**: Looks for files modified within last 5 minutes
- **Sorting**: Models alphabetically sorted, GGUF files sorted by size (largest first)

## Model Information

All model information (stars, pulls, descriptions) is current as of December 18, 2025.

## License

This script is provided as-is for downloading and using AI models via Docker.

## Contributing

Feel free to submit issues or pull requests to add new models or improve functionality.

## Related Resources

- [Docker AI Models](https://hub.docker.com/search?q=ai)
- [Ollama Documentation](https://github.com/ollama/ollama)
- [GGUF Format Specification](https://github.com/ggerganov/ggml/blob/master/docs/gguf.md)
