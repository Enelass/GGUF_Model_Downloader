#!/bin/bash
set -e
clear
# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Scanning performance tuning (bytes)
HEADER_BYTES=${HEADER_BYTES:-4194304}  # 4 MiB
MIN_SIZE_BYTES=${MIN_SIZE_BYTES:-1024}  # ignore tiny files
DOWNLOAD_RETRY_DELAY_SECONDS=${DOWNLOAD_RETRY_DELAY_SECONDS:-5}
DOWNLOAD_MAX_RETRIES=${DOWNLOAD_MAX_RETRIES:-10}
PATH_DISPLAY_WIDTH=${PATH_DISPLAY_WIDTH:-80}
ACTIVE_PULL_PID=""
DOWNLOAD_CANCELLED=0

IS_MACOS=0
if [ "$(uname -s)" = "Darwin" ]; then
    IS_MACOS=1
fi


# Extract a GGUF KV value from header (header-limited, safe locale)
extract_kv_header() {
    local file="$1"
    local key="$2"
    LC_ALL=C head -c "$HEADER_BYTES" "$file" 2>/dev/null | LC_ALL=C strings | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C awk -v k="$key" 'BEGIN{f=0} index($0, k){f=1; next} f && NF{print; exit}'
}

extract_kv_exact() {
    local file="$1"
    local key="$2"
    LC_ALL=C head -c "$HEADER_BYTES" "$file" 2>/dev/null | LC_ALL=C strings | LC_ALL=C awk -v k="$key" '$0 == k { getline; print; exit }'
}

extract_arch_kv() {
    local file="$1"
    local arch="$2"
    local suffix="$3"

    if [ -z "$arch" ] || [ "$arch" = "-" ]; then
        return
    fi

    extract_kv_exact "$file" "${arch}.${suffix}"
}

extract_gguf_metadata() {
    local file="$1"

    case "$GGUF_TOOL" in
        gguf_dump)
            LC_ALL=C gguf_dump "$file" 2>/dev/null || true
            ;;
        llama-gguf)
            LC_ALL=C llama-gguf "$file" r n 2>/dev/null || true
            ;;
    esac

    LC_ALL=C head -c "$HEADER_BYTES" "$file" 2>/dev/null | LC_ALL=C strings || true
}

extract_tensor_count() {
    local file="$1"
    local output=""

    case "$GGUF_TOOL" in
        gguf_dump)
            output=$(LC_ALL=C gguf_dump "$file" 2>/dev/null || true)
            ;;
        llama-gguf)
            output=$(LC_ALL=C llama-gguf "$file" r n 2>/dev/null || true)
            ;;
    esac

    printf "%s" "$output" | LC_ALL=C awk '/n_tensors:/ { print $NF; exit }'
}

normalize_alnum_lower() {
    printf "%s" "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -d "[:space:]" | LC_ALL=C tr -cd "[:alnum:]"
}

is_incompatible_model_for_platform() {
    local name="$1"
    local lower_name

    if [ "$IS_MACOS" -eq 1 ]; then
        lower_name=$(printf "%s" "$name" | LC_ALL=C tr '[:upper:]' '[:lower:]')
        case "$lower_name" in
            *vllm*) return 0 ;;
        esac
    fi

    return 1
}

# Normalize token to letters-only (lowercase)
normalize_letters() {
    printf "%s" "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed 's/[^a-z]//g'
}

format_size_gb() {
    local bytes="$1"
    if ! [[ "$bytes" =~ ^[0-9]+$ ]]; then
        printf "-"
        return
    fi

    awk -v bytes="$bytes" 'BEGIN {
        gb = bytes / 1024 / 1024 / 1024
        rounded = int(gb * 10 + 0.5) / 10
        if (rounded == int(rounded)) {
            printf "%d GB", rounded
        } else {
            printf "%.1f GB", rounded
        }
    }'
}

truncate_text() {
    local value="$1"
    local width="$2"

    if [ "${#value}" -le "$width" ]; then
        printf "%s" "$value"
        return
    fi

    if [ "$width" -le 3 ]; then
        printf "%.*s" "$width" "$value"
        return
    fi

    printf "%.*s..." "$((width - 3))" "$value"
}

crop_middle() {
    local value="$1"
    local width="$2"
    local value_len=${#value}
    local prefix_len
    local suffix_len

    if [ "$value_len" -le "$width" ]; then
        printf "%s" "$value"
        return
    fi

    if [ "$width" -le 3 ]; then
        printf "%.*s" "$width" "$value"
        return
    fi

    prefix_len=$(( (width - 3) / 2 ))
    suffix_len=$(( width - 3 - prefix_len ))
    printf "%s...%s" "${value:0:$prefix_len}" "${value:$((value_len - suffix_len)):$suffix_len}"
}

pull_model_with_retries() {
    local model_reference="$1"
    local attempt=0
    local status=0

    cancel_active_download() {
        DOWNLOAD_CANCELLED=1
        echo
        print_message "$YELLOW" "Download cancellation requested. Stopping docker model pull..."
        if [ -n "${ACTIVE_PULL_PID:-}" ] && kill -0 "$ACTIVE_PULL_PID" 2>/dev/null; then
            kill -TERM "$ACTIVE_PULL_PID" 2>/dev/null || true
        fi
    }

    while true; do
        DOWNLOAD_CANCELLED=0

        if [ "$attempt" -eq 0 ]; then
            print_message "$YELLOW" "Running: docker model pull $model_reference"
        else
            print_message "$YELLOW" "Retry $attempt/$DOWNLOAD_MAX_RETRIES: docker model pull $model_reference"
        fi

        trap cancel_active_download INT
        docker model pull "$model_reference" &
        ACTIVE_PULL_PID=$!
        if wait "$ACTIVE_PULL_PID"; then
            status=0
        else
            status=$?
        fi
        ACTIVE_PULL_PID=""
        trap - INT

        if [ "$DOWNLOAD_CANCELLED" -eq 1 ] || [ "$status" -eq 130 ] || [ "$status" -eq 143 ]; then
            print_message "$YELLOW" "Download cancelled."
            return 130
        fi

        if [ "$status" -eq 0 ]; then
            return 0
        fi

        if [ "$attempt" -ge "$DOWNLOAD_MAX_RETRIES" ]; then
            return 1
        fi

        attempt=$((attempt + 1))
        print_message "$YELLOW" "Download failed. Retrying in ${DOWNLOAD_RETRY_DELAY_SECONDS}s..."
        sleep "$DOWNLOAD_RETRY_DELAY_SECONDS"
    done
}


# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

SPINNER_PID=""

start_spinner() {
    local message="$1"

    stop_spinner

    if [ ! -t 1 ]; then
        print_message "$YELLOW" "$message"
        return
    fi

    (
        while true; do
            for frame in "-" "\\" "|" "/"; do
                printf "\r${YELLOW}%s${NC} %s" "$frame" "$message"
                sleep 0.12
            done
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [ -n "${SPINNER_PID:-}" ]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        SPINNER_PID=""

        if [ -t 1 ]; then
            printf "\r\033[K"
        fi
    fi
}

print_banner() {
    print_message "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
    print_message "$GREEN" "║                 Docker Model Downloader                        ║"
    print_message "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
}

# Check if docker command exists
if ! command -v docker &> /dev/null; then
    print_message "$RED" "❌ Error: Docker command not found!"
    print_message "$YELLOW" "Please install Docker Desktop first: https://www.docker.com/products/docker-desktop"
    exit 1
fi

#print_message "$GREEN" "✅ Docker command found!"

# Check if jq command exists
if ! command -v jq &> /dev/null; then
    print_message "$RED" "❌ Error: jq command not found!"
    print_message "$YELLOW" "This script uses jq to parse Docker Hub's API responses. Install it with:"
    print_message "$YELLOW" "  • macOS (Homebrew): brew install jq"
    print_message "$YELLOW" "  • Ubuntu/Debian:    sudo apt-get update && sudo apt-get install -y jq"
    exit 1
fi

#print_message "$GREEN" "✅ jq command found!"
#echo

# Detect optional GGUF tooling: prefer gguf_dump when present; Homebrew llama.cpp provides llama-gguf.
GGUF_TOOL=""
GGUF_TOOL_MESSAGE=""
GGUF_TOOL_COLOR="$GREEN"
if command -v gguf_dump >/dev/null 2>&1; then
    GGUF_TOOL="gguf_dump"
    GGUF_TOOL_MESSAGE="✅ GGUF metadata: gguf_dump"
elif command -v llama-gguf >/dev/null 2>&1; then
    GGUF_TOOL="llama-gguf"
    GGUF_TOOL_MESSAGE="✅ GGUF metadata: llama-gguf"
else
    GGUF_TOOL_MESSAGE="⚠️  GGUF metadata tools not found. Downloads still work; install llama.cpp for richer local metadata."
    GGUF_TOOL_COLOR="$YELLOW"
fi

render_startup_menu() {
    local selected="$1"
    local remaining="$2"
    local interacted="$3"

    clear
    print_banner
    echo
    echo "   Select a Docker AI model and variant, download it, then locate the GGUF blob."
    echo "   Docker stores model blobs in: ~/.docker/models/blobs/sha256/"
    echo
    print_message "$GREEN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    print_message "$GGUF_TOOL_COLOR" "$GGUF_TOOL_MESSAGE"
    echo

    if [ "$selected" -eq 1 ]; then
        echo " > (*) Download models"
        echo "   ( ) Check downloaded models"
    else
        echo "   ( ) Download models"
        echo " > (*) Check downloaded models"
    fi

    echo
    if [ "$interacted" -eq 1 ]; then
        print_message "$YELLOW" "Use ↑/↓ then Enter. [q] Quit"
    else
        print_message "$YELLOW" "Use ↑/↓ then Enter. Auto-starting downloader in ${remaining}s. [q] Quit"
    fi
}

select_startup_action() {
    local selected=1
    local deadline=$((SECONDS + 5))
    local interacted=0
    local remaining
    local key
    local rest

    while true; do
        if [ "$interacted" -eq 0 ]; then
            remaining=$((deadline - SECONDS))
            if [ "$remaining" -le 0 ]; then
                APP_ACTION="download"
                return
            fi
        else
            remaining=0
        fi

        render_startup_menu "$selected" "$remaining" "$interacted"

        if [ "$interacted" -eq 0 ]; then
            if ! IFS= read -t "$remaining" -r -s -n 1 key 2>/dev/null; then
                APP_ACTION="download"
                return
            fi
        else
            IFS= read -r -s -n 1 key 2>/dev/null
        fi

        case "$key" in
            "")
                if [ "$selected" -eq 1 ]; then
                    APP_ACTION="download"
                else
                    APP_ACTION="check"
                fi
                return
                ;;
            $'\x1b')
                if [ -t 0 ]; then
                    IFS= read -t 0.5 -r -s -n 2 rest 2>/dev/null || true
                else
                    IFS= read -r -s -n 2 rest 2>/dev/null || true
                fi
                case "$rest" in
                    '[A'|'[B')
                        interacted=1
                        if [ "$selected" -eq 1 ]; then
                            selected=2
                        else
                            selected=1
                        fi
                        ;;
                esac
                ;;
            '[')
                IFS= read -r -s -n 1 rest 2>/dev/null || true
                case "$rest" in
                    A|B)
                        interacted=1
                        if [ "$selected" -eq 1 ]; then
                            selected=2
                        else
                            selected=1
                        fi
                        ;;
                esac
                ;;
            1)
                APP_ACTION="download"
                return
                ;;
            2)
                APP_ACTION="check"
                return
                ;;
            q|Q)
                print_message "$YELLOW" "Exiting..."
                exit 0
                ;;
        esac
    done
}

APP_ACTION="download"
select_startup_action

display_downloaded_models() {
    clear
    print_banner
    echo
    print_message "$GREEN" "📁 Downloaded Docker GGUF models"
    echo

    local blobs_dir="$HOME/.docker/models/blobs/sha256"
    if [ ! -d "$blobs_dir" ]; then
        print_message "$YELLOW" "⚠️  Docker models directory not found: $blobs_dir"
        return
    fi

    start_spinner "Scanning local Docker model blobs..."

    declare -a downloaded_gguf_files=()
    declare -a incomplete_download_files=()
    local incomplete_count=0
    while IFS= read -r file; do
        case "$file" in
            *.incomplete)
                incomplete_count=$((incomplete_count + 1))
                incomplete_download_files+=("$file")
                continue
                ;;
        esac

        if [ -f "$file" ]; then
            magic=$(head -c 4 "$file" 2>/dev/null | xxd -p 2>/dev/null)
            if [ "$magic" = "47475546" ]; then
                downloaded_gguf_files+=("$file")
            fi
        fi
    done < <(find "$blobs_dir" -type f 2>/dev/null)

    stop_spinner

    if [ ${#downloaded_gguf_files[@]} -eq 0 ] && [ "$incomplete_count" -eq 0 ]; then
        print_message "$YELLOW" "No GGUF files found in $blobs_dir."
        return
    fi

    if [ ${#downloaded_gguf_files[@]} -eq 0 ]; then
        print_message "$YELLOW" "No completed GGUF files found in $blobs_dir."
        echo
    else
    IFS=$'\n' sorted_downloaded_gguf_files=($(
        for f in "${downloaded_gguf_files[@]}"; do
            echo "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)|$f"
        done | sort -rn | cut -d'|' -f2
    ))

    if [ -n "$GGUF_TOOL" ]; then
        start_spinner "Reading GGUF metadata..."
    else
        start_spinner "Reading GGUF headers..."
    fi

    declare -a group_names=()
    declare -a record_groups=()
    declare -a record_roles=()
    declare -a record_arches=()
    declare -a record_sizes=()
    declare -a record_contexts=()
    declare -a record_quants=()
    declare -a record_tensors=()
    declare -a record_paths=()

    for gguf_file in "${sorted_downloaded_gguf_files[@]}"; do
        local file_size
        local model_name
        local arch
        local role
        local context_length
        local file_type
        local quant_version
        local quantization
        local tensor_count
        local cropped_path
        local group_exists=0
        local group_name

        file_size=$(du -h "$gguf_file" | awk '{print $1}')
        model_name=$(extract_kv_exact "$gguf_file" "general.name")
        if [ -z "$model_name" ]; then
            model_name=$(extract_kv_exact "$gguf_file" "general.basename")
        fi
        if [ -z "$model_name" ]; then
            model_name="Unknown GGUF model"
        fi

        arch=$(extract_kv_exact "$gguf_file" "general.architecture")
        if [ -z "$arch" ]; then
            arch="-"
        fi

        role=$(extract_kv_exact "$gguf_file" "general.type")
        if [ "$arch" = "clip" ]; then
            role="projector"
        elif [ -z "$role" ]; then
            role="model"
        fi

        context_length=$(extract_arch_kv "$gguf_file" "$arch" "context_length")
        if ! [[ "$context_length" =~ ^[0-9]+$ ]]; then
            context_length="-"
        fi

        file_type=$(extract_kv_exact "$gguf_file" "general.file_type")
        quant_version=$(extract_kv_exact "$gguf_file" "general.quantization_version")
        if ! [[ "$file_type" =~ ^[0-9]+$ ]]; then
            file_type=""
        fi
        if ! [[ "$quant_version" =~ ^[0-9]+$ ]]; then
            quant_version=""
        fi
        if [ -n "$file_type" ] && [ -n "$quant_version" ]; then
            quantization="type ${file_type}/v${quant_version}"
        elif [ -n "$file_type" ]; then
            quantization="type ${file_type}"
        elif [ -n "$quant_version" ]; then
            quantization="v${quant_version}"
        else
            quantization="-"
        fi

        tensor_count=$(extract_tensor_count "$gguf_file")
        if [ -z "$tensor_count" ]; then
            tensor_count="-"
        fi

        cropped_path=$(crop_middle "$gguf_file" "$PATH_DISPLAY_WIDTH")

        for group_name in "${group_names[@]}"; do
            if [ "$group_name" = "$model_name" ]; then
                group_exists=1
                break
            fi
        done
        if [ "$group_exists" -eq 0 ]; then
            group_names+=("$model_name")
        fi

        record_groups+=("$model_name")
        record_roles+=("$role")
        record_arches+=("$arch")
        record_sizes+=("$file_size")
        record_contexts+=("$context_length")
        record_quants+=("$quantization")
        record_tensors+=("$tensor_count")
        record_paths+=("$cropped_path")
    done

    stop_spinner

    print_message "$GREEN" "Found ${#sorted_downloaded_gguf_files[@]} GGUF file(s) across ${#group_names[@]} model group(s):"
    if [ "$incomplete_count" -gt 0 ]; then
        print_message "$YELLOW" "Skipped $incomplete_count incomplete download file(s)."
    fi
    echo

    for group_name in "${group_names[@]}"; do
        print_message "$GREEN" "$group_name"
        printf "  %-10s %-10s %-7s %-9s %-13s %-8s %s\n" "Role" "Arch" "Size" "Context" "Quant" "Tensors" "Path"

        local idx
        for idx in "${!record_groups[@]}"; do
            if [ "${record_groups[$idx]}" = "$group_name" ]; then
                printf "  %-10s %-10s %-7s %-9s %-13s %-8s %s\n" \
                    "$(truncate_text "${record_roles[$idx]}" 10)" \
                    "$(truncate_text "${record_arches[$idx]}" 10)" \
                    "${record_sizes[$idx]}" \
                    "$(truncate_text "${record_contexts[$idx]}" 9)" \
                    "$(truncate_text "${record_quants[$idx]}" 13)" \
                    "${record_tensors[$idx]}" \
                    "${record_paths[$idx]}"
            fi
        done
        echo
    done
    fi

    if [ "$incomplete_count" -gt 0 ]; then
        print_message "$YELLOW" "Incomplete downloads"
        printf "  %-7s %s\n" "Size" "Path"

        local incomplete_file
        for incomplete_file in "${incomplete_download_files[@]}"; do
            printf "  %-7s %s\n" \
                "$(du -h "$incomplete_file" 2>/dev/null | awk '{print $1}')" \
                "$(crop_middle "$incomplete_file" "$PATH_DISPLAY_WIDTH")"
        done
        echo

        print_message "$YELLOW" "Press [p] to purge incomplete downloads, or Enter/[q] to exit."
        printf "Enter choice: "

        local purge_choice
        if ! read -r purge_choice; then
            return
        fi

        case "$purge_choice" in
            p|P)
                print_message "$YELLOW" "Delete $incomplete_count incomplete download file(s)? [y/N]"
                printf "Confirm: "
                local confirm_purge
                if ! read -r confirm_purge; then
                    print_message "$YELLOW" "Purge cancelled."
                    return
                fi

                case "$confirm_purge" in
                    y|Y|yes|YES)
                        local purged_count=0
                        for incomplete_file in "${incomplete_download_files[@]}"; do
                            if rm -f -- "$incomplete_file"; then
                                purged_count=$((purged_count + 1))
                            fi
                        done
                        print_message "$GREEN" "Purged $purged_count incomplete download file(s)."
                        ;;
                    *)
                        print_message "$YELLOW" "Purge cancelled."
                        ;;
                esac
                ;;
        esac
    fi
}

fetch_models_from_dockerhub() {
    model_names=()
    model_stars=()
    model_pulls=()
    model_descriptions=()

    local page=1
    local page_size=100
    local max_attempts=3
    local skipped_incompatible_models=0

    start_spinner "Retrieving model list from Docker Hub..."

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
            stop_spinner
            print_message "$RED" "❌ Failed to fetch model list from Docker Hub (page $page)."
            print_message "$YELLOW" "Check your internet connection and try again."
            exit 1
        fi

        if ! echo "$response" | jq -e '.results and (.results|type=="array")' >/dev/null 2>&1; then
            stop_spinner
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
            if is_incompatible_model_for_platform "$name"; then
                skipped_incompatible_models=$((skipped_incompatible_models + 1))
                continue
            fi

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

    stop_spinner

    if [ "$skipped_incompatible_models" -gt 0 ]; then
        print_message "$YELLOW" "Filtered $skipped_incompatible_models vLLM model(s) on macOS."
    fi

    if [ ${#model_names[@]} -eq 0 ]; then
        print_message "$RED" "❌ No models returned from Docker Hub."
        print_message "$YELLOW" "Try again later."
        exit 1
    fi
}

fetch_variants_for_model() {
    local model="$1"
    local repo="ai/$model"
    local page=1
    local page_size=100
    local max_attempts=3

    variant_tags=()
    variant_params=()
    variant_quantizations=()
    variant_contexts=()
    variant_vrams=()
    variant_tool_callings=()
    variant_sizes=()

    start_spinner "Retrieving variants for ai/$model..."

    local token=""
    token=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repo}:pull" | jq -r '.token // empty' 2>/dev/null || true)

    while true; do
        local url="https://hub.docker.com/v2/repositories/${repo}/tags?page_size=${page_size}&page=${page}"
        local response=""
        local attempt

        for attempt in $(seq 1 "$max_attempts"); do
            if response=$(curl -fsSL "$url" -H 'accept: */*' 2>/dev/null); then
                break
            fi
            sleep 0.4
        done

        if [ -z "$response" ]; then
            break
        fi

        if ! echo "$response" | jq -e '.results and (.results|type=="array")' >/dev/null 2>&1; then
            break
        fi

        local page_count
        page_count=$(echo "$response" | jq -r '.results | length')
        if [ "$page_count" -eq 0 ]; then
            break
        fi

        while IFS='|' read -r tag full_size; do
            local params="-"
            local quantization="-"
            local context_window="-"
            local vram="-"
            local tool_calling="-"
            local formatted_size
            formatted_size=$(format_size_gb "$full_size")

            if [ -n "$token" ]; then
                local manifest=""
                local config_digest=""
                local config=""

                manifest=$(curl -fsSL "https://registry-1.docker.io/v2/${repo}/manifests/${tag}" \
                    -H "Authorization: Bearer ${token}" \
                    -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.cncf.model.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
                    2>/dev/null || true)

                if [ -n "$manifest" ]; then
                    config_digest=$(printf "%s" "$manifest" | jq -r '.config.digest // empty' 2>/dev/null || true)
                fi

                if [ -n "$config_digest" ]; then
                    config=$(curl -fsSL "https://registry-1.docker.io/v2/${repo}/blobs/${config_digest}" \
                        -H "Authorization: Bearer ${token}" \
                        2>/dev/null || true)
                fi

                if [ -n "$config" ]; then
                    params=$(printf "%s" "$config" | jq -r '.config.paramSize // .config.parameters // "-"' 2>/dev/null || echo "-")
                    quantization=$(printf "%s" "$config" | jq -r '.config.quantization // "-"' 2>/dev/null || echo "-")
                    context_window=$(printf "%s" "$config" | jq -r '.config.contextWindow // .config.contextLength // .config.context // "-"' 2>/dev/null || echo "-")
                    vram=$(printf "%s" "$config" | jq -r '.config.vram // .config.vramSize // "-"' 2>/dev/null || echo "-")
                    tool_calling=$(printf "%s" "$config" | jq -r '.config.toolCalling // .config.tool_calls // "-"' 2>/dev/null || echo "-")
                fi
            fi

            variant_tags+=("$tag")
            variant_params+=("$params")
            variant_quantizations+=("$quantization")
            variant_contexts+=("$context_window")
            variant_vrams+=("$vram")
            variant_tool_callings+=("$tool_calling")
            variant_sizes+=("$formatted_size")
        done < <(
            echo "$response" | jq -r '.results[] | "\(.name)|\(.full_size // 0)"'
        )

        local next_url
        next_url=$(echo "$response" | jq -r '.next')
        if [ "$next_url" = "null" ] || [ -z "$next_url" ]; then
            break
        fi

        page=$((page + 1))
    done

    stop_spinner

    if [ ${#variant_tags[@]} -eq 0 ]; then
        variant_tags=("latest")
        variant_params=("-")
        variant_quantizations=("-")
        variant_contexts=("-")
        variant_vrams=("-")
        variant_tool_callings=("-")
        variant_sizes=("-")
    fi
}

select_variant_for_model() {
    local model="$1"

    while true; do
        clear
        print_message "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
        print_message "$GREEN" "║                 Docker Model Downloader                        ║"
        print_message "$GREEN" "╚════════════════════════════════════════════════════════════════╝"
        echo
        print_message "$GREEN" "📋 Available variants for ai/$model"
        echo
        printf "%-4s %-28s %-12s %-18s %-15s %-10s %-14s %-10s\n" "#" "Variant" "Parameters" "Quantization" "Context Window" "VRAM" "Tool Calling" "Size"
        printf "%-4s %-28s %-12s %-18s %-15s %-10s %-14s %-10s\n" "----" "----------------------------" "------------" "------------------" "---------------" "----------" "--------------" "----------"

        local i
        for (( i=0; i<${#variant_tags[@]}; i++ )); do
            local display_num=$((i + 1))
            printf "%-4s %-28s %-12s %-18s %-15s %-10s %-14s %-10s\n" \
                "$display_num)" \
                "$model:${variant_tags[$i]}" \
                "${variant_params[$i]}" \
                "${variant_quantizations[$i]}" \
                "${variant_contexts[$i]}" \
                "${variant_vrams[$i]}" \
                "${variant_tool_callings[$i]}" \
                "${variant_sizes[$i]}"
        done

        echo
        print_message "$YELLOW" "Select a variant number, press Enter for 1, or [q] Quit"
        printf "Enter choice: "

        local input
        read -r input
        if [ -z "$input" ]; then
            input=1
        fi

        case "$input" in
            q|Q)
                print_message "$YELLOW" "Exiting..."
                exit 0
                ;;
        esac

        if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le "${#variant_tags[@]}" ]; then
            local selected_variant_idx=$((input - 1))
            selected_variant="${variant_tags[$selected_variant_idx]}"
            selected_model_reference="ai/$model"
            if [ "$selected_variant" != "latest" ]; then
                selected_model_reference="${selected_model_reference}:${selected_variant}"
            fi
            selected_ollama_model="$model"
            if [ "$selected_variant" != "latest" ]; then
                selected_ollama_model="${model}-${selected_variant}"
            fi
            break
        fi

        print_message "$RED" "❌ Invalid selection. Please enter a number between 1 and ${#variant_tags[@]}"
        sleep 1
    done
}

if [ "$APP_ACTION" = "check" ]; then
    display_downloaded_models
    exit 0
fi

fetch_models_from_dockerhub

# Pagination settings
MODELS_PER_PAGE=20
total_models=${#model_names[@]}
total_pages=$(( (total_models + MODELS_PER_PAGE - 1) / MODELS_PER_PAGE ))
current_page=1

# Function to display models for current page
display_page() {
    clear
    print_message "$GREEN" "╔════════════════════════════════════════════════════════════════╗"
    print_message "$GREEN" "║                 Docker Model Downloader                        ║"
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
    printf "%-4s %-27s %6s %10s   %s\n" "#" "Model Name" "Stars" "Pulls" "Description"
    printf "%-4s %-27s %6s %10s   %s\n" "----" "---------------------------" "------" "----------" "-----------------------------------------"

    # Display models
    for (( i=start_idx; i<end_idx; i++ )); do
        local display_num=$((i + 1))
        # Format pulls with comma separators for readability
        local formatted_pulls=$(printf "%'d" "${model_pulls[$i]}" 2>/dev/null || echo "${model_pulls[$i]}")
        local display_name
        display_name=$(truncate_text "${model_names[$i]}" 27)
        printf "%-4s %-27s %6s %10s   %s\n" \
            "$display_num)" \
            "$display_name" \
            "${model_stars[$i]}" \
            "$formatted_pulls" \
            "${model_descriptions[$i]}"
    done

    echo
    print_message "$YELLOW" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local start_num=$((start_idx + 1))
    local end_num=$end_idx
    print_message "$YELLOW" "Navigation: [←] Previous  [→] Next  [Type number 1-$total_models + Enter] Select  [q] Quit"
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
selected_variant=""
selected_model_reference=""
selected_ollama_model=""
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
print_message "$GREEN" "✅ You selected model: $selected_model"
fetch_variants_for_model "$selected_model"
select_variant_for_model "$selected_model"

echo
print_message "$GREEN" "✅ You selected variant: ${selected_model}:${selected_variant}"
print_message "$YELLOW" "📥 Starting download..."
echo

# Download the model using docker. Ctrl+C cancels the active pull and returns here.
while true; do
    if pull_model_with_retries "$selected_model_reference"; then
        break
    else
        pull_status=$?
    fi

    if [ "$pull_status" -eq 130 ]; then
        echo
        print_message "$YELLOW" "Select another variant for $selected_model, or [q] Quit."
        select_variant_for_model "$selected_model"
        echo
        print_message "$GREEN" "✅ You selected variant: ${selected_model}:${selected_variant}"
        print_message "$YELLOW" "📥 Starting download..."
        echo
        continue
    fi

    echo
    print_message "$RED" "❌ Failed to download model: $selected_model_reference"
    exit 1
done

    echo
    print_message "$GREEN" "✅ Successfully downloaded model: $selected_model_reference"
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

            declare -a matches=()
            if [ -n "$GGUF_TOOL" ]; then
                print_message "$YELLOW" "🔍 Using $GGUF_TOOL to match model metadata for '$selected_model'..."
                selected_norm=$(normalize_alnum_lower "$selected_model")
                for f in "${gguf_files[@]}"; do
                    meta=$(extract_gguf_metadata "$f")
                    if [ -n "${meta}" ]; then
                        meta_norm=$(normalize_alnum_lower "$meta")
                        if printf "%s" "$meta_norm" | grep -F -q "$selected_norm"; then
                            matches+=("$f")
                        fi
                    fi
                done
            else
                print_message "$YELLOW" "🔍 GGUF metadata tools not found; using recent GGUF files sorted by size."
            fi
            if [ ${#matches[@]} -gt 0 ]; then
                IFS=$'\n' sorted_gguf_files=($(
                    for f in "${matches[@]}"; do
                        echo "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)|$f"
                    done | sort -rn | cut -d'|' -f2
                ))
            else
                # fallback to size sorting of all candidates
                IFS=$'\n' sorted_gguf_files=($(
                    for f in "${gguf_files[@]}"; do
                        echo "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)|$f"
                    done | sort -rn | cut -d'|' -f2
                ))
            fi

            for gguf_file in "${sorted_gguf_files[@]}"; do
                file_size=$(du -h "$gguf_file" | cut -f1)
                echo "   • $gguf_file ($file_size)"
            done

            echo
            print_message "$GREEN" "📝 Next steps:
"

            # Decide FROM/ADAPTER files based on detected GGUF metadata
            if [ ${#sorted_gguf_files[@]} -eq 1 ]; then
                # Single GGUF file
                echo "   1. Create a Modelfile with:"
                echo "      FROM ${sorted_gguf_files[0]}"
                echo
            else
                # Detect adapters by checking general.file_type (header-only)
                declare -a is_adapter=()
                for idx in "${!sorted_gguf_files[@]}"; do
                    fpath="${sorted_gguf_files[$idx]}"
                    file_type=$(extract_kv_header "$fpath" "general.file_type")
                    # also check tags/basename for adapter hints
                    if [ -z "$file_type" ]; then
                        file_type=$(extract_kv_header "$fpath" "general.tags")
                    fi
                    if [ -z "$file_type" ]; then
                        file_type=$(extract_kv_header "$fpath" "general.basename")
                    fi
                    if [ -n "$file_type" ] && echo "$file_type" | LC_ALL=C grep -qi "adapter"; then
                        is_adapter[$idx]=1
                    else
                        is_adapter[$idx]=0
                    fi
                done

                # Print FROM for the largest (first) file
                echo "   1. Create a Modelfile with:"
                echo "      FROM ${sorted_gguf_files[0]}"

                # Print ADAPTER lines only for files that are detected as adapters
                adapter_count=0
                for (( i=1; i<${#sorted_gguf_files[@]}; i++ )); do
                    if [ "${is_adapter[$i]}" -eq 1 ]; then
                        echo "      ADAPTER ${sorted_gguf_files[$i]}"
                        adapter_count=$((adapter_count+1))
                    fi
                done

                if [ "$adapter_count" -eq 0 ]; then
                    echo
                    echo "   Note: No adapter GGUF files detected."
                fi
                echo
            fi

            echo "   2. Import to Ollama: ollama create $selected_ollama_model -f Modelfile"
            echo "   3. Run it: ollama run $selected_ollama_model"

            print_message "$YELLOW" "   ℹ️  Note: Ollama will copy the GGUF files to its own storage (~/.ollama/models)"

            echo "      After successful import, you can safely delete the Docker blobs to save space."
            echo
        else
            echo
        print_message "$YELLOW" "⚠️  No GGUF files found in recent downloads. Scanning all blobs in $blobs_dir..."

            declare -a gguf_files_all=()
            while IFS= read -r file; do
                if [ -f "$file" ]; then
                    magic=$(head -c 4 "$file" 2>/dev/null | xxd -p 2>/dev/null)
                    if [ "$magic" = "47475546" ]; then
                        gguf_files_all+=("$file")
                    fi
                fi
            done < <(find "$blobs_dir" -type f 2>/dev/null)

            if [ ${#gguf_files_all[@]} -gt 0 ]; then
                echo
                print_message "$GREEN" "📁 GGUF file(s) found: ${#gguf_files_all[@]} file(s)"

                declare -a matches_all=()
                if [ -n "$GGUF_TOOL" ]; then
                    print_message "$YELLOW" "🔍 Using $GGUF_TOOL to match model metadata for '$selected_model' (full scan)..."
                    selected_norm=$(normalize_alnum_lower "$selected_model")
                    for f in "${gguf_files_all[@]}"; do
                        meta=$(extract_gguf_metadata "$f")
                        if [ -n "${meta}" ]; then
                            meta_norm=$(normalize_alnum_lower "$meta")
                            if printf "%s" "$meta_norm" | grep -F -q "$selected_norm"; then
                                matches_all+=("$f")
                            fi
                        fi
                    done
                else
                    print_message "$YELLOW" "🔍 GGUF metadata tools not found; using all GGUF files sorted by size."
                fi
                if [ ${#matches_all[@]} -gt 0 ]; then
                    IFS=$'
' sorted_gguf_files_all=($(
                        for f in "${matches_all[@]}"; do
                            echo "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)|$f"
                        done | sort -rn | cut -d'|' -f2
                    ))
                else
                    IFS=$'
' sorted_gguf_files_all=($(
                        for f in "${gguf_files_all[@]}"; do
                            echo "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)|$f"
                        done | sort -rn | cut -d'|' -f2
                    ))
                fi

                for gguf_file in "${sorted_gguf_files_all[@]}"; do
                    file_size=$(du -h "$gguf_file" | cut -f1)
                    echo "   • $gguf_file ($file_size)"
                done

                echo
                print_message "$GREEN" "📝 Next steps:"

                if [ ${#gguf_files_all[@]} -eq 1 ]; then
                    echo "   1. Create a Modelfile with:"
                    echo "      FROM ${sorted_gguf_files_all[0]}"
                    echo
                else
                    declare -a is_adapter_all=()
                    for idx in "${!sorted_gguf_files_all[@]}"; do
                        fpath="${sorted_gguf_files_all[$idx]}"
                        file_type=$(extract_kv_header "$fpath" "general.file_type")
                        if [ -z "$file_type" ]; then
                            file_type=$(extract_kv_header "$fpath" "general.tags")
                        fi
                        if [ -z "$file_type" ]; then
                            file_type=$(extract_kv_header "$fpath" "general.basename")
                        fi
                        if [ -n "$file_type" ] && echo "$file_type" | LC_ALL=C grep -qi "adapter"; then
                            is_adapter_all[$idx]=1
                        else
                            is_adapter_all[$idx]=0
                        fi
                    done

                    echo "   1. Create a Modelfile with:"
                    echo "      FROM ${sorted_gguf_files_all[0]}"

                    adapter_count=0
                    for (( i=1; i<${#sorted_gguf_files_all[@]}; i++ )); do
                        if [ "${is_adapter_all[$i]}" -eq 1 ]; then
                            echo "      ADAPTER ${sorted_gguf_files_all[$i]}"
                            adapter_count=$((adapter_count+1))
                        fi
                    done

                    if [ "$adapter_count" -eq 0 ]; then
                        echo
                        echo "   Note: No adapter GGUF files detected."
                    fi
                    echo
                fi

                echo "   2. Import to Ollama: ollama create $selected_ollama_model -f Modelfile"
                echo "   3. Run it: ollama run $selected_ollama_model"

                print_message "$YELLOW" "   ℹ️  Note: Ollama will copy the GGUF files to its own storage (~/.ollama/models)"
                echo "      After successful import, you can safely delete the Docker blobs to save space."
                echo
            else
                echo
                print_message "$YELLOW" "⚠️  No GGUF files found in $blobs_dir."
                echo "   Models are stored in: $blobs_dir"
                echo "   You may need to ensure the model download completed and try again."
                echo
            fi

        fi
    else
        echo
        print_message "$YELLOW" "⚠️  Docker models directory not found: $blobs_dir"
        echo
    fi
