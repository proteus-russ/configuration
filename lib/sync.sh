#!/usr/bin/env bash
# Shared helpers for sync-home. Source this file; do not execute directly.
# shellcheck shell=bash

SYNC_COPIED=0
SYNC_FAILED=0

confirm() {
    local prompt="$1" reply
    read -rp "$prompt [yn] " -n 1 reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

_copy_one() {
    local src="$1" dest="$2"
    printf 'Copying %s -> %s\n' "$src" "$dest"
    mkdir -p "$(dirname "$dest")"
    if cp "$src" "$dest"; then
        SYNC_COPIED=$((SYNC_COPIED + 1))
    else
        printf 'FAILED: %s -> %s\n' "$src" "$dest" >&2
        SYNC_FAILED=$((SYNC_FAILED + 1))
    fi
}

# usage: sync_list <manifest> <repo_dir> <home_dir> <direction>
# manifest lines: one filename per line
# direction: to-home | from-home
sync_list() {
    local manifest="$1" repo_dir="$2" home_dir="$3" direction="$4"
    local name
    while read -r name _rest || [[ -n $name ]]; do
        [[ -z $name || $name == \#* ]] && continue
        if [[ $direction == to-home ]]; then
            _copy_one "$repo_dir/$name" "$home_dir/$name"
        else
            _copy_one "$home_dir/$name" "$repo_dir/$name"
        fi
    done < "$manifest"
    echo
}

# usage: sync_mapped <manifest> <repo_dir> <home_dir> <direction>
# manifest lines: "<name_in_repo> <name_relative_to_home>"
# direction: to-home | from-home
sync_mapped() {
    local manifest="$1" repo_dir="$2" home_dir="$3" direction="$4"
    local repo_name home_path
    while read -r repo_name home_path _rest || [[ -n $repo_name ]]; do
        [[ -z $repo_name || $repo_name == \#* ]] && continue
        if [[ -z $home_path ]]; then
            printf 'Invalid manifest entry (expected 2 columns): %s\n' "$repo_name" >&2
            SYNC_FAILED=$((SYNC_FAILED + 1))
            continue
        fi
        if [[ $direction == to-home ]]; then
            _copy_one "$repo_dir/$repo_name" "$home_dir/$home_path"
        else
            _copy_one "$home_dir/$home_path" "$repo_dir/$repo_name"
        fi
    done < "$manifest"
    echo
}

sync_summary() {
    if (( SYNC_FAILED > 0 )); then
        printf '%d copied, %d failed\n' "$SYNC_COPIED" "$SYNC_FAILED" >&2
        return 1
    fi
    printf '%d copied\n' "$SYNC_COPIED"
}
