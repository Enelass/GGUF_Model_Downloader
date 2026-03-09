#!/bin/bash
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

# Check if jq command exists
if ! command -v jq &> /dev/null; then
    print_message "$RED" "❌ Error: jq command not found!"
    print_message "$YELLOW" "This script uses jq to parse Docker Hub's API responses. Install it with:"
    print_message "$YELLOW" "  • macOS (Homebrew): brew install jq"
    print_message "$YELLOW" "  • Ubuntu/Debian:    sudo apt-get update && sudo apt-get install -y jq"
    exit 1
fi

print_message "$GREEN" "✅ jq command found!"
echo

# Display introduction
print_message "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
print_message "$GREEN" "║            GGUF Model Downloader via Docker                    ║"
print_message "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
echo
print_message "$YELLOW" "📖 What this script does:"
echo "   • Fetches the latest Docker Hub AI models each run"
echo "   • Lets you select a model interactively"
echo "   • Downloads the selected GGUF model using Docker"
echo "   • Shows you where the downloaded GGUF files are located"
echo
print_message "$YELLOW" "ℹ️  Note: GGUF models are downloaded to ~/.docker/models/blobs/sha256/"
echo "   You can then use these GGUF files with Ollama or other LLM runtimes."
echo
print_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

fetch_models_from_dockerhub() {
    model_names=()
    model_stars=()
    model_pulls=()
    model_descriptions=()

    local page=1
    local page_size=100
    local max_attempts=3

    print_message "$YELLOW" "🔄 Fetching latest model list from Docker Hub..."

    while true; do
        local url="https://hub.docker.com/v2/repositories/ai?page_size=${page_size}&page=${page}&ordering=last_updated"

        local response=""
        local attempt
        for attempt in $(seq 1 "$max_attempts"); do
            if response=$(curl -fsSL "$url" -H 'accept: */*' 2>/dev/null); then
                break
            fi
            sleep 0.4
        done

        if [ -z "$response" ]; then
            print_message "$RED" "❌ Failed to fetch model list from Docker Hub (page $page)."
            print_message "$YELLOW" "Check your internet connection and try again."
            exit 1
        fi

        if ! echo "$response" | jq -e '.results and (.results|type=="array")' >/dev/null 2>&1; then
            print_message "$RED" "❌ Docker Hub returned an unexpected response (page $page)."
            print_message "$YELLOW" "Try again later (you may be rate-limited)."
            exit 1
        fi

        local page_count
        page_count=$(echo "$response" | jq -r '.results | length')
        if [ "$page_count" -eq 0 ]; then
            break
        fi

        while IFS='|' read -r name stars pulls description; do
            model_names+=("$name")
            model_stars+=("$stars")
            model_pulls+=("$pulls")
            model_descriptions+=("$description")
        done < <(
            echo "$response" | jq -r '.results[] | "\(.name)|\(.star_count // 0)|\(.pull_count // 0)|\(.description // "")"'
        )

        local next_url
        next_url=$(echo "$response" | jq -r '.next')
        if [ "$next_url" = "null" ] || [ -z "$next_url" ]; then
            break
        fi

        page=$((page + 1))
    done

    if [ ${#model_names[@]} -eq 0 ]; then
        print_message "$RED" "❌ No models returned from Docker Hub."
        print_message "$YELLOW" "Try again later."
        exit 1
    fi
}

fetch_models_from_dockerhub

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
    printf "%-4s %-35s %6s %10s   %s\n" "#" "Model Name" "Stars" "Pulls" "Description"
    printf "%-4s %-35s %6s %10s   %s\n" "----" "-----------------------------------" "------" "----------" "-------------------------------------------------"

    # Display models
    for (( i=start_idx; i<end_idx; i++ )); do
        local display_num=$((i + 1))
        # Format pulls with comma separators for readability
        local formatted_pulls=$(printf "%'d" "${model_pulls[$i]}" 2>/dev/null || echo "${model_pulls[$i]}")
        printf "%-4s %-35s %6s %10s   %s\n" \
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
