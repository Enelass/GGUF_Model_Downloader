#!/usr/bin/env bash
set -euo pipefail

# scripts/release.sh
# Generate release notes from CHANGELOG.md and create a GitHub release via `gh`.
# Usage: ./scripts/release.sh <version|Unreleased> [--notes-file FILE] [--no-tag] [--tag-prefix v] [--draft] [--prerelease] [--yes] [--dry-run] [--skip-gh]

usage() {
    echo "Usage: $0 <version|Unreleased> [--notes-file FILE] [--no-tag] [--tag-prefix v] [--draft] [--prerelease] [--yes] [--dry-run] [--skip-gh]"
    exit 1
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
    usage
fi

version=""
notes_file=""
create_tag=1
tag_prefix="v"
draft_flag="false"
prerelease_flag="false"
assume_yes=0
dry_run=0
skip_gh=0

# Simple arg parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes-file)
            notes_file="$2"; shift 2;;
        --no-tag)
            create_tag=0; shift;;
        --tag-prefix)
            tag_prefix="$2"; shift 2;;
        --draft)
            draft_flag="true"; shift;;
        --prerelease)
            prerelease_flag="true"; shift;;
        --yes)
            assume_yes=1; shift;;
        --dry-run)
            dry_run=1; shift;;
        --skip-gh)
            skip_gh=1; shift;;
        -h|--help)
            usage;;
        *)
            if [[ -z "$version" ]]; then
                version="$1"; shift
            else
                echo "Unknown argument: $1" >&2; usage
            fi
            ;;
    esac
done

if [[ -z "$version" ]]; then
    usage
fi

changelog_file="CHANGELOG.md"
if [[ ! -f "$changelog_file" ]]; then
    echo "ERROR: $changelog_file not found in repository root." >&2
    exit 1
fi

# Extract the changelog section for the requested version.
# We look for a second-level heading (starts with '##') containing the version text.
tmp_notes="$(mktemp -t release-notes.XXXXXX)"
awk -v ver="$version" '
    BEGIN {found=0}
    /^##\s*/ {
        if (found) exit
        # if the heading line contains the version string, start collecting on following lines
        if (index($0, ver) > 0) { found=1; next }
    }
    found { print }
' "$changelog_file" > "$tmp_notes"

# If the extracted notes file is empty, warn and fail.
if [[ ! -s "$tmp_notes" ]]; then
    echo "ERROR: Could not extract notes for version '$version' from $changelog_file." >&2
    rm -f "$tmp_notes"
    exit 1
fi

# Default notes file name if not provided
if [[ -z "$notes_file" ]]; then
    notes_file="release-notes-${version}.md"
fi

mv "$tmp_notes" "$notes_file"

echo "Generated notes -> $notes_file"

if [[ $assume_yes -eq 0 ]]; then
    echo "---"
    echo "Release notes preview:"; echo
    sed -n '1,200p' "$notes_file"
    echo "---"
    read -r -p "Proceed to create tag/release for version '$version'? [y/N] " ans || true
    case "$ans" in
        [Yy]*) ;;
        *) echo "Aborted by user"; exit 1;;
    esac
fi

# Prepare tag name
tag_name="${tag_prefix}${version}"

# Create and push git tag if requested
if [[ $create_tag -eq 1 ]]; then
    if git rev-parse --verify "refs/tags/$tag_name" >/dev/null 2>&1; then
        echo "Tag $tag_name already exists locally. Skipping tag creation."
    else
        echo "Creating git tag $tag_name"
        git tag -a "$tag_name" -m "Release $version"
        if [[ $dry_run -eq 0 ]]; then
            echo "Pushing tag $tag_name to origin"
            git push origin "$tag_name"
        else
            echo "Dry-run: not pushing tag"
        fi
    fi
else
    echo "Skipping git tag creation (--no-tag)."
fi

# Run gh release create unless skip_gh or dry-run
if [[ $skip_gh -eq 1 ]]; then
    echo "Skipping gh release creation (--skip-gh)."
    exit 0
fi

if [[ $dry_run -eq 1 ]]; then
    echo "Dry-run: would run: gh release create '$tag_name' --title '$version' --notes-file '$notes_file' $( [[ $draft_flag == "true" ]] && echo "--draft" ) $( [[ $prerelease_flag == "true" ]] && echo "--prerelease" )"
    exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: GitHub CLI 'gh' not found in PATH. Install it or run with --skip-gh to only generate notes." >&2
    exit 1
fi

gh_args=("$tag_name" "--title" "$version" "--notes-file" "$notes_file")
if [[ "$draft_flag" == "true" ]]; then gh_args+=("--draft"); fi
if [[ "$prerelease_flag" == "true" ]]; then gh_args+=("--prerelease"); fi

echo "Creating GitHub release for $tag_name"
exec gh release create "${gh_args[@]}"
