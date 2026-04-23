#!/usr/bin/env bash
# Shared helpers for sync-home. Source this file; do not execute directly.
# shellcheck shell=bash

SYNC_COPIED=0
SYNC_SKIPPED=0
SYNC_FAILED=0

SYNC_INTERACTIVE=0
SYNC_DRY_RUN=0
SYNC_ACCEPT_ALL=0
SYNC_QUIT=0
SYNC_PROMPT_LEGEND_SHOWN=0
SYNC_DIFF_COLOR=

confirm() {
    local prompt="$1" reply
    read -rp "$prompt [yn] " -n 1 reply
    echo
    [[ $reply =~ ^[Yy]$ ]]
}

_detect_diff_color() {
    if [[ -n $SYNC_DIFF_COLOR ]]; then
        return
    fi
    if diff --color=always -u /dev/null /dev/null >/dev/null 2>&1; then
        SYNC_DIFF_COLOR=1
    else
        SYNC_DIFF_COLOR=0
    fi
}

_files_identical() {
    local a="$1" b="$2"
    [[ -f $a && -f $b ]] && cmp -s "$a" "$b"
}

_show_diff() {
    local src="$1" dest="$2"
    if [[ ! -e $dest ]]; then
        local size="?"
        if [[ -f $src ]]; then
            size=$(wc -c < "$src" | tr -d ' ')
        fi
        printf 'NEW FILE (dest does not exist, %s bytes)\n' "$size"
        return
    fi
    _detect_diff_color
    if (( SYNC_DIFF_COLOR )); then
        diff --color=always -u "$dest" "$src" || true
    else
        diff -u "$dest" "$src" || true
    fi
}

_print_prompt_legend() {
    printf 'y - copy this file   n - skip   a - copy all remaining   q - quit now   d - show diff again   ? - help\n'
}

# Returns 0 to copy, 1 to skip. May set SYNC_ACCEPT_ALL or SYNC_QUIT.
_confirm_file() {
    local src="$1" dest="$2" reply
    printf '\n=== %s  ->  %s ===\n' "$src" "$dest"
    _show_diff "$src" "$dest"
    echo
    if (( ! SYNC_PROMPT_LEGEND_SHOWN )); then
        _print_prompt_legend
        SYNC_PROMPT_LEGEND_SHOWN=1
    fi
    while true; do
        if ! read -rp 'Copy this file? [y,n,a,q,d,?] ' reply; then
            echo
            SYNC_QUIT=1
            return 1
        fi
        reply="${reply:0:1}"
        case "$reply" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            a|A) SYNC_ACCEPT_ALL=1; return 0 ;;
            q|Q) SYNC_QUIT=1; return 1 ;;
            d|D) _show_diff "$src" "$dest"; echo ;;
            '?') _print_prompt_legend ;;
            *)   printf 'Unrecognized response. ' ; _print_prompt_legend ;;
        esac
    done
}

_copy_one() {
    local src="$1" dest="$2"

    if (( SYNC_QUIT )); then
        return
    fi

    if _files_identical "$src" "$dest"; then
        SYNC_SKIPPED=$((SYNC_SKIPPED + 1))
        return
    fi

    if (( SYNC_INTERACTIVE )) && (( ! SYNC_ACCEPT_ALL )); then
        if ! _confirm_file "$src" "$dest"; then
            SYNC_SKIPPED=$((SYNC_SKIPPED + 1))
            return
        fi
    fi

    if (( SYNC_DRY_RUN )); then
        printf 'would copy %s -> %s\n' "$src" "$dest"
        SYNC_COPIED=$((SYNC_COPIED + 1))
        return
    fi

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
    while read -r -u 3 name _rest || [[ -n $name ]]; do
        (( SYNC_QUIT )) && break
        [[ -z $name || $name == \#* ]] && continue
        if [[ $direction == to-home ]]; then
            _copy_one "$repo_dir/$name" "$home_dir/$name"
        else
            _copy_one "$home_dir/$name" "$repo_dir/$name"
        fi
    done 3< "$manifest"
    echo
}

# usage: sync_mapped <manifest> <repo_dir> <home_dir> <direction>
# manifest lines: "<name_in_repo> <name_relative_to_home>"
# direction: to-home | from-home
sync_mapped() {
    local manifest="$1" repo_dir="$2" home_dir="$3" direction="$4"
    local repo_name home_path
    while read -r -u 3 repo_name home_path _rest || [[ -n $repo_name ]]; do
        (( SYNC_QUIT )) && break
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
    done 3< "$manifest"
    echo
}

sync_summary() {
    local verb="copied"
    if (( SYNC_DRY_RUN )); then
        verb="would copy"
    fi
    local msg
    msg=$(printf '%d %s' "$SYNC_COPIED" "$verb")
    if (( SYNC_SKIPPED > 0 )); then
        msg+=$(printf ', %d skipped' "$SYNC_SKIPPED")
    fi
    if (( SYNC_FAILED > 0 )); then
        msg+=$(printf ', %d failed' "$SYNC_FAILED")
        printf '%s\n' "$msg" >&2
        return 1
    fi
    printf '%s\n' "$msg"
}
