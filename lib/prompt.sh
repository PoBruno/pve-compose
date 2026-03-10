#!/bin/sh
# lib/prompt.sh - Interactive prompt helpers for pve-compose
# Sourced by commands - never executed directly.
# Depends: lib/output.sh
#
# Uses whiptail TUI when available (arrow-key menus), falls back to plain text.
# whiptail is pre-installed on all Debian/Proxmox systems.

# _prompt_has_tui - check if whiptail is available and terminal supports it
_prompt_has_tui() {
    command -v whiptail >/dev/null 2>&1 && [ -t 2 ]
}

# prompt_loading MESSAGE - show non-blocking "loading" screen in TUI
# Keeps whiptail alternate buffer active while data loads in background.
# Falls back to stderr message if no TUI.
prompt_loading() {
    _pl_msg="${1:-Loading...}"
    if _prompt_has_tui; then
        whiptail --title "pve-compose" --infobox "$_pl_msg" 7 50 2>/dev/null
    else
        printf "  %s\n" "$_pl_msg" >&2
    fi
}

# prompt_input LABEL DEFAULT - ask for text input with default
# Output: user input or default (stdout)
prompt_input() {
    _label="$1"
    _default="${2:-}"
    if _prompt_has_tui; then
        _val=$(whiptail --inputbox "$_label" 10 60 "$_default" 3>&1 1>&2 2>&3) || _val="$_default"
    else
        if [ -n "$_default" ]; then
            printf "%s [%s]: " "$_label" "$_default" >&2
        else
            printf "%s: " "$_label" >&2
        fi
        read -r _val </dev/tty
        [ -n "$_val" ] || _val="$_default"
    fi
    printf '%s' "$_val"
}

# prompt_select LABEL OPTION1 OPTION2 ... - menu selection, returns selected value
# Output: selected option text (stdout)
prompt_select() {
    _label="$1"
    shift

    if _prompt_has_tui; then
        # Build whiptail menu args: TAG DESCRIPTION pairs
        _wt_args=""
        _n=0
        for _opt in "$@"; do
            _n=$(( _n + 1 ))
            _wt_args="$_wt_args $_n \"$_opt\""
        done
        _wt_height=$(( _n + 8 ))
        [ "$_wt_height" -gt 24 ] && _wt_height=24
        _wt_menu=$(( _n ))
        [ "$_wt_menu" -gt 16 ] && _wt_menu=16
        _choice=$(eval "whiptail --title 'pve-compose' --menu '$_label' $_wt_height 70 $_wt_menu $_wt_args" 3>&1 1>&2 2>&3) || _choice="1"

        # Return the option matching the tag number
        _i=0
        for _opt in "$@"; do
            _i=$(( _i + 1 ))
            if [ "$_i" = "$_choice" ]; then
                printf '%s' "$_opt"
                return 0
            fi
        done
        # Fallback to first
        printf '%s' "$1"
    else
        printf "\n%s${_C_BOLD}%s${_C_RESET}\n" "" "$_label" >&2
        _n=0
        for _opt in "$@"; do
            _n=$(( _n + 1 ))
            printf "  %s${_C_BLUE}%d${_C_RESET}%s %s\n" "" "$_n" ")" "$_opt" >&2
        done
        printf "\nChoice [1]: " >&2
        read -r _choice </dev/tty
        [ -n "$_choice" ] || _choice=1
        case "$_choice" in
            *[!0-9]*) _choice=1 ;;
        esac
        if [ "$_choice" -lt 1 ] || [ "$_choice" -gt "$_n" ]; then
            _choice=1
        fi
        _i=0
        for _opt in "$@"; do
            _i=$(( _i + 1 ))
            if [ "$_i" = "$_choice" ]; then
                printf '%s' "$_opt"
                return 0
            fi
        done
    fi
}

# prompt_password LABEL - read password without echo
# Output: password text (stdout)
prompt_password() {
    _label="$1"
    if _prompt_has_tui; then
        _pass=$(whiptail --passwordbox "$_label" 10 60 3>&1 1>&2 2>&3) || _pass=""
    else
        printf "%s: " "$_label" >&2
        stty -echo 2>/dev/null || true
        read -r _pass </dev/tty
        stty echo 2>/dev/null || true
        printf "\n" >&2
    fi
    printf '%s' "$_pass"
}

# prompt_yesno LABEL DEFAULT - ask yes/no question
# DEFAULT: "y" or "n" (default: "y")
# Returns: 0 for yes, 1 for no
prompt_yesno() {
    _label="$1"
    _default="${2:-y}"
    if _prompt_has_tui; then
        if [ "$_default" = "n" ]; then
            whiptail --yesno "$_label" 10 60 --defaultno 3>&1 1>&2 2>&3
        else
            whiptail --yesno "$_label" 10 60 3>&1 1>&2 2>&3
        fi
        return $?
    else
        if [ "$_default" = "y" ]; then
            printf "%s [Y/n]: " "$_label" >&2
        else
            printf "%s [y/N]: " "$_label" >&2
        fi
        read -r _val </dev/tty
        [ -n "$_val" ] || _val="$_default"
        case "$_val" in
            [yY]|[yY][eE][sS]) return 0 ;;
            *) return 1 ;;
        esac
    fi
}

# prompt_select_lines LABEL - read lines from stdin, present as menu, return selected line
# Output: selected line text (stdout)
prompt_select_lines() {
    _ps_label="$1"
    _ps_tmpfile="${TMPDIR:-/tmp}/pvc_select.$$"
    cat > "$_ps_tmpfile"
    _ps_count=$(wc -l < "$_ps_tmpfile")

    if _prompt_has_tui; then
        _wt_args=""
        _ps_i=0
        while IFS= read -r _ps_line; do
            [ -n "$_ps_line" ] || continue
            _ps_i=$(( _ps_i + 1 ))
            _wt_args="$_wt_args $_ps_i \"$_ps_line\""
        done < "$_ps_tmpfile"
        _wt_height=$(( _ps_i + 8 ))
        [ "$_wt_height" -gt 24 ] && _wt_height=24
        _wt_menu="$_ps_i"
        [ "$_wt_menu" -gt 16 ] && _wt_menu=16
        _ps_choice=$(eval "whiptail --title 'pve-compose' --menu '$_ps_label' $_wt_height 70 $_wt_menu $_wt_args" 3>&1 1>&2 2>&3) || _ps_choice="1"
        sed -n "${_ps_choice}p" "$_ps_tmpfile"
    else
        printf "\n%s${_C_BOLD}%s${_C_RESET}\n" "" "$_ps_label" >&2
        _ps_i=0
        while IFS= read -r _ps_line; do
            [ -n "$_ps_line" ] || continue
            _ps_i=$(( _ps_i + 1 ))
            printf "  %s${_C_BLUE}%d${_C_RESET}%s %s\n" "" "$_ps_i" ")" "$_ps_line" >&2
        done < "$_ps_tmpfile"
        printf "\nChoice [1]: " >&2
        read -r _ps_choice </dev/tty
        [ -n "$_ps_choice" ] || _ps_choice=1
        case "$_ps_choice" in
            *[!0-9]*) _ps_choice=1 ;;
        esac
        if [ "$_ps_choice" -lt 1 ] || [ "$_ps_choice" -gt "$_ps_count" ]; then
            _ps_choice=1
        fi
        sed -n "${_ps_choice}p" "$_ps_tmpfile"
    fi
    rm -f "$_ps_tmpfile"
}

# list_storages_rootdir - list storage names that support rootdir content
# Output: one storage per line "NAME (TYPE)" 
list_storages_rootdir() {
    _cfg="/etc/pve/storage.cfg"
    [ -f "$_cfg" ] || return 1
    awk '
        /^[a-z]/ { stype=$1; sub(/:$/,"",stype); sname=$2 }
        /content/ && /rootdir/ { printf "%s (%s)\n", sname, stype }
    ' "$_cfg"
}

# list_os_templates - list available OS templates from all vztmpl storages
# Output: one template per line "STORAGE:vztmpl/FILENAME"
# Reads filesystem directly for speed (avoids pveam list which can hang on CIFS).
list_os_templates() {
    _cfg="/etc/pve/storage.cfg"
    [ -f "$_cfg" ] || return 1

    # Parse storages with vztmpl content - extract name and path
    _st_map=$(awk '
        /^[a-z]/ { stype=$1; sub(/:$/,"",stype); sname=$2; spath="" }
        /^\tpath / { spath=$2 }
        /content/ && /vztmpl/ {
            if (spath != "") print sname, spath
        }
    ' "$_cfg")

    printf '%s\n' "$_st_map" | while read -r _st _path; do
        if [ -z "$_st" ] || [ -z "$_path" ]; then continue; fi
        _cache_dir="$_path/template/cache"
        if [ -d "$_cache_dir" ]; then
            for _f in "$_cache_dir"/*.tar.*; do
                [ -f "$_f" ] || continue
                _fname=$(basename "$_f")
                printf '%s:vztmpl/%s\n' "$_st" "$_fname"
            done
        fi
    done
}
