#!/bin/bash

# Script to download Docker AI models
# Based on: https://commbank.atlassian.net/wiki/spaces/SBD/pages/1838219833/Import+GGUF+in+Ollama

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if docker command exists
if ! command -v docker &> /dev/null; then
    print_message "$RED" "❌ Error: Docker command not found!"
    print_message "$YELLOW" "Please install Docker Desktop first: https://www.docker.com/products/docker-desktop"
    exit 1
fi

print_message "$GREEN" "✅ Docker command found!"
echo

# Display introduction
print_message "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
print_message "$GREEN" "║            GGUF Model Downloader via Docker                    ║"
print_message "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
echo
print_message "$YELLOW" "📖 What this script does:"
echo "   • Lists all available Docker AI models (52+ models)"
echo "   • Lets you select a model interactively"
echo "   • Downloads the selected GGUF model using Docker"
echo "   • Shows you where the downloaded GGUF files are located"
echo
print_message "$YELLOW" "ℹ️  Note: GGUF models are downloaded to ~/.docker/models/blobs/sha256/"
echo "   You can then use these GGUF files with Ollama or other LLM runtimes."
echo
print_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# List of available Docker AI models (as of 18-Dec-2025)
# Format: "model_name|stars|pulls|description"
declare -a models=(
    "qwen3|85|344746|Qwen3 is the latest Qwen LLM, built for top-tier coding, math, reasoning, and language tasks."
    "deepseek-r1-distill-llama|72|153814|Distilled LLaMA by DeepSeek, fast and optimized for real-world tasks"
    "gemma3|48|427501|Google's latest Gemma, small yet strong for chat and generation"
    "gpt-oss|29|297938|OpenAI's open-weight models designed for powerful reasoning, agentic tasks"
    "smollm2|28|234268|Tiny LLM built for speed, edge devices, and local development"
    "llama3.2|22|286477|Solid LLaMA 3 update, reliable for coding, chat, and Q&A tasks"
    "phi4|20|76250|Microsoft's compact model, surprisingly capable at reasoning and code"
    "mistral|19|49067|Efficient open model with top-tier performance and fast inference"
    "gemma3-qat|19|80086|Google's latest Gemma, in its QAT (quantization aware trained) variant"
    "llama3.3|17|59094|Newest LLama 3 release with improved reasoning and generation quality"
    "qwen3-coder|15|55484|Qwen3-Coder is Qwen's new series of coding agent models"
    "deepcoder-preview|10|33680|DeepCoder-14B-Preview is a code reasoning LLM fine-tuned to scale up to long context lengths"
    "gemma3n|10|87133|Efficient multimodal AI for text, image, audio, and video on low-resource devices"
    "qwen2.5|8|73684|Versatile Qwen update with better language skills and wider support"
    "smollm3|5|29536|SmolLM3 is a 3.1B model for efficient on-device use, with strong performance in chat"
    "qwen3-vl|5|60381|The most advanced Qwen model yet, with major gains in text, vision, video, and reasoning"
    "llama3.1|4|19395|Meta's LLama 3.1: Chat-focused, benchmark-strong, multilingual-ready"
    "mistral-nemo|3|8784|Mistral fine-tuned via NVIDIA NeMo for smoother enterprise use"
    "mxbai-embed-large|3|8140|mxbai-embed-large-v1 is a top English embed model by Mixedbread AI, great for RAG"
    "qwq|3|5925|Experimental Qwen variant—lean, fast, and a bit mysterious"
    "nomic-embed-text-v1.5|3|6907|Nomic Embed Text v1 is an open‑source, fully auditable text embedding model"
    "embeddinggemma|3|10384|Embedding Gemma is a state-of-the-art text embedding model from Google DeepMind"
    "devstral-small|3|6009|Agentic coding LLM (24B) fine-tuned from Mistral-Small-3.1 with a 128K context window"
    "smolvlm|3|8078|SmolVLM: lightweight multimodal model for video, image, and text analysis"
    "deepseek-v3.2-vllm|3|7039|DeepSeek-V3.2 boosts efficiency and reasoning with DSA, scalable RL, agentic data"
    "granite-embedding-multilingual|2|4816|Granite Embedding Multilingual is a 278M parameter encoder‑only XLM‑RoBERTa‑style"
    "granite-4.0-h-micro|2|3264|3B long-context instruct model with RL alignment, IF, tool calling, and enterprise readiness"
    "granite-4.0-h-tiny|2|5378|7B long-context instruct model with RL alignment, IF, tool use, and enterprise optimization"
    "moondream2|2|5283|An open-source visual language model that interprets images via text prompts"
    "seed-oss|1|9049|Designed for reasoning, agent and general capabilities, versatile developer-friendly features"
    "magistral-small-3.2|1|9004|24B multimodal instruction model by Mistral AI, tuned for accuracy, tool use"
    "granite-4.0-h-small|1|4649|32B long-context instruct model with RL alignment, IF, tool use, and enterprise optimization"
    "granite-docling|1|15787|Granite Docling is a multimodal model for efficient document conversion"
    "all-minilm-l6-v2-vllm|1|1157|all-MiniLM-L6-v2 is a sentence-transformers model"
    "granite-4.0-h-nano|1|2355|Granite-4.0-h-nano: lightweight instruct model trained via SFT, RL, and merging"
    "gpt-oss-safeguard|1|9036|Safety reasoning models for policy-based text classification and foundational safety tasks"
    "ministral3-vllm|1|6158|Ministral 3: compact vision-enabled model with near-24B performance"
    "granite-4.0-micro|0|2247|3B long-context instruct model with RL alignment, IF, tool use, and enterprise optimization"
    "smollm2-vllm|0|3834|SmolVLM: lightweight multimodal model for video, image, and text analysis"
    "qwen3-vllm|0|5968|Qwen3 is the latest Qwen LLM, built for top-tier coding, math, reasoning, and language tasks"
    "embeddinggemma-vllm|0|1193|Embedding Gemma is a state-of-the-art text embedding model from Google DeepMind"
    "gpt-oss-vllm|0|5777|OpenAI's open-weight models designed for powerful reasoning, agentic tasks"
    "gemma3-vllm|0|15198|Google's latest Gemma, small yet strong for chat and generation"
    "granite-4.0-nano|0|5186|Granite-4.0-nano: lightweight instruct model trained via SFT, RL, and merging"
    "qwen3-embedding|0|9956|Qwen3 Embedding: multilingual models for advanced text/ranking tasks"
    "qwen3-embedding-vllm|0|6962|Qwen3 Embedding: multilingual models for advanced text/ranking tasks"
    "snowflake-arctic-embed-l-v2-vllm|0|2635|Snowflake's Arctic-Embed v2.0 boosts multilingual retrieval and efficiency"
    "qwen3-reranker|0|2831|Multilingual reranking model for text retrieval, scoring document relevance"
    "qwen3-reranker-vllm|0|6215|Multilingual reranking model for text retrieval, scoring document relevance"
    "ministral3|0|15441|Ministral 3: compact vision-enabled model with near-24B performance"
    "kimi-k2-vllm|0|3971|Kimi K2 Thinking: open-source agent with deep reasoning, stable tool use"
    "kimi-k2|0|8792|Kimi K2 Thinking: open-source agent with deep reasoning, stable tool use"
)

# Prepare arrays for select menu
declare -a model_names=()
declare -a model_stars=()
declare -a model_pulls=()
declare -a model_descriptions=()

# Parse and store model data
for model in "${models[@]}"; do
    IFS='|' read -r name stars pulls description <<< "$model"
    model_names+=("$name")
    model_stars+=("$stars")
    model_pulls+=("$pulls")
    model_descriptions+=("$description")
done

# Sort models alphabetically by name
# Create array of indices
declare -a indices=()
for i in "${!model_names[@]}"; do
    indices+=("$i")
done

# Sort indices based on model names
IFS=$'\n' sorted_indices=($(
    for i in "${indices[@]}"; do
        echo "$i|${model_names[$i]}"
    done | sort -t'|' -k2 | cut -d'|' -f1
))

# Create sorted arrays
declare -a sorted_names=()
declare -a sorted_stars=()
declare -a sorted_pulls=()
declare -a sorted_descriptions=()

for idx in "${sorted_indices[@]}"; do
    sorted_names+=("${model_names[$idx]}")
    sorted_stars+=("${model_stars[$idx]}")
    sorted_pulls+=("${model_pulls[$idx]}")
    sorted_descriptions+=("${model_descriptions[$idx]}")
done

# Replace original arrays with sorted ones
model_names=("${sorted_names[@]}")
model_stars=("${sorted_stars[@]}")
model_pulls=("${sorted_pulls[@]}")
model_descriptions=("${sorted_descriptions[@]}")

# Pagination settings
MODELS_PER_PAGE=10
total_models=${#model_names[@]}
total_pages=$(( (total_models + MODELS_PER_PAGE - 1) / MODELS_PER_PAGE ))
current_page=1

# Function to display models for current page
display_page() {
    clear
    print_message "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
    print_message "$GREEN" "║            GGUF Model Downloader via Docker                    ║"
    print_message "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
    echo
    print_message "$GREEN" "📋 Available Docker AI Models (Page $current_page of $total_pages):"
    echo

    local start_idx=$(( (current_page - 1) * MODELS_PER_PAGE ))
    local end_idx=$(( start_idx + MODELS_PER_PAGE ))

    if [ $end_idx -gt $total_models ]; then
        end_idx=$total_models
    fi

    # Display header
    printf "\n"
    printf "%-4s %-35s %6s %8s   %s\n" "#" "Model Name" "Stars" "Pulls" "Description"
    printf "%-4s %-35s %6s %8s   %s\n" "----" "-----------------------------------" "------" "--------" "-------------------------------------------------"

    # Display models
    for (( i=start_idx; i<end_idx; i++ )); do
        local display_num=$((i + 1))
        # Format pulls with comma separators for readability
        local formatted_pulls=$(printf "%'d" "${model_pulls[$i]}" 2>/dev/null || echo "${model_pulls[$i]}")
        printf "%-4s %-35s %6s %8s   %s\n" \
            "$display_num)" \
            "${model_names[$i]}" \
            "${model_stars[$i]}" \
            "$formatted_pulls" \
            "${model_descriptions[$i]}"
    done

    echo
    print_message "$YELLOW" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local start_num=$((start_idx + 1))
    local end_num=$end_idx
    print_message "$YELLOW" "Navigation: [↑] Previous  [↓] Next  [Type number 1-$total_models + Enter] Select  [q] Quit"
    print_message "$YELLOW" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to read a single keypress including arrow keys
read_key() {
    local key
    IFS= read -rsn1 key 2>/dev/null

    # Check if it's an escape sequence (arrow keys)
    if [[ $key == $'\x1b' ]]; then
        # Read the next two characters
        read -rsn2 key 2>/dev/null
        case "$key" in
            '[D') echo "LEFT" ;;      # Left arrow
            '[C') echo "RIGHT" ;;     # Right arrow
            '[A') echo "UP" ;;        # Up arrow
            '[B') echo "DOWN" ;;      # Down arrow
            *) echo "$key" ;;
        esac
    else
        echo "$key"
    fi
}

# Interactive selection loop
selected_model=""
while true; do
    display_page

    echo
    printf "Enter choice: "

    # Read first character to detect arrow keys or regular input
    first_char=$(read_key)

    case "$first_char" in
        # Arrow keys for navigation
        LEFT|UP)
            echo
            if [ $current_page -gt 1 ]; then
                ((current_page--))
            else
                print_message "$YELLOW" "Already on first page"
                sleep 0.5
            fi
            ;;
        RIGHT|DOWN)
            echo
            if [ $current_page -lt $total_pages ]; then
                ((current_page++))
            else
                print_message "$YELLOW" "Already on last page"
                sleep 0.5
            fi
            ;;
        # Quit
        q|Q)
            echo
            print_message "$YELLOW" "Exiting..."
            exit 0
            ;;
        # Number input - read the rest of the line
        [0-9])
            # Echo the first digit so user can see it
            echo -n "$first_char"
            # Read the rest of the input
            read -r rest_of_input
            input="${first_char}${rest_of_input}"

            # Validate it's a number
            if [[ "$input" =~ ^[0-9]+$ ]]; then
                selected_idx=$((input - 1))

                # Check if selection is valid (between 1 and total_models)
                if [ "$input" -ge 1 ] && [ "$input" -le "$total_models" ]; then
                    selected_model="${model_names[$selected_idx]}"
                    break
                else
                    print_message "$RED" "❌ Invalid selection. Please enter a number between 1 and $total_models"
                    sleep 1
                fi
            else
                print_message "$RED" "❌ Invalid input. Please enter a number."
                sleep 1
            fi
            ;;
        p|P)
            echo
            if [ $current_page -gt 1 ]; then
                ((current_page--))
            else
                print_message "$YELLOW" "Already on first page"
                sleep 0.5
            fi
            ;;
        n|N)
            echo
            if [ $current_page -lt $total_pages ]; then
                ((current_page++))
            else
                print_message "$YELLOW" "Already on last page"
                sleep 0.5
            fi
            ;;
        *)
            echo
            print_message "$RED" "❌ Invalid input. Use ←→ arrows, p/n, type number + Enter, or 'q' to quit"
            sleep 1
            ;;
    esac
done

echo
print_message "$GREEN" "✅ You selected: $selected_model"
print_message "$YELLOW" "📥 Starting download..."
echo

# Download the model using docker
docker_command="docker model pull ai/$selected_model"
print_message "$YELLOW" "Running: $docker_command"
echo

if eval "$docker_command"; then
    echo
    print_message "$GREEN" "✅ Successfully downloaded model: $selected_model"
    echo

    # Locate the downloaded GGUF files
    print_message "$YELLOW" "🔍 Locating GGUF files..."
    blobs_dir="$HOME/.docker/models/blobs/sha256"

    if [ -d "$blobs_dir" ]; then
        # Find GGUF files by checking for GGUF magic bytes (47 47 55 46 in hex)
        declare -a gguf_files=()

        # Get files modified in the last 5 minutes (recently downloaded)
        while IFS= read -r file; do
            # Check if file starts with GGUF magic bytes
            if [ -f "$file" ]; then
                magic=$(head -c 4 "$file" 2>/dev/null | xxd -p 2>/dev/null)
                if [ "$magic" = "47475546" ]; then
                    gguf_files+=("$file")
                fi
            fi
        done < <(find "$blobs_dir" -type f -mmin -5 2>/dev/null)

        if [ ${#gguf_files[@]} -gt 0 ]; then
            echo
            print_message "$GREEN" "📁 GGUF file(s) found: ${#gguf_files[@]} file(s)"

            # Sort files by size (largest first - usually the main model)
            IFS=$'\n' sorted_gguf_files=($(
                for f in "${gguf_files[@]}"; do
                    echo "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)|$f"
                done | sort -rn | cut -d'|' -f2
            ))

            for gguf_file in "${sorted_gguf_files[@]}"; do
                file_size=$(du -h "$gguf_file" | cut -f1)
                echo "   • $gguf_file ($file_size)"
            done

            echo
            print_message "$GREEN" "📝 Next steps:"

            if [ ${#gguf_files[@]} -eq 1 ]; then
                # Single GGUF file
                echo "   1. Create a Modelfile with:"
                echo "      FROM ${sorted_gguf_files[0]}"
                echo
            else
                # Multiple GGUF files (likely text + vision)
                echo "   1. Create a Modelfile with (for multimodal/vision models):"
                echo "      FROM ${sorted_gguf_files[0]}"
                echo "      ADAPTER ${sorted_gguf_files[1]}"
                if [ ${#gguf_files[@]} -gt 2 ]; then
                    for (( i=2; i<${#sorted_gguf_files[@]}; i++ )); do
                        echo "      ADAPTER ${sorted_gguf_files[$i]}"
                    done
                fi
                echo
                print_message "$YELLOW" "      Note: Largest file is usually the main model (FROM)"
                echo "            Smaller file(s) are typically vision/multimodal adapters (ADAPTER)"
                echo
            fi

            echo "   2. Import to Ollama: ollama create $selected_model -f Modelfile"
            echo "   3. Run it: ollama run $selected_model"
            echo
            print_message "$YELLOW" "   ℹ️  Note: Ollama will copy the GGUF files to its own storage (~/.ollama/models)"
            echo "      After successful import, you can safely delete the Docker blobs to save space."
            echo
        else
            echo
            print_message "$YELLOW" "⚠️  No GGUF files found in recent downloads."
            echo "   Models are stored in: $blobs_dir"
            echo "   You may need to manually identify the GGUF files using:"
            echo "   find $blobs_dir -type f -exec sh -c 'head -c 4 \"\$1\" | xxd | grep -q \"4747 5546\" && echo \"\$1\"' _ {} \\;"
            echo
        fi
    else
        echo
        print_message "$YELLOW" "⚠️  Docker models directory not found: $blobs_dir"
        echo
    fi
else
    echo
    print_message "$RED" "❌ Failed to download model: $selected_model"
    exit 1
fi
