#!/bin/sh
# commands/overview.sh - Global view of Docker containers across all LXCs

# Strip IP prefixes from PORTS column, deduplicate IPv4/IPv6 entries
_ov_clean_ports() {
    awk '
    NR == 1 { pcol = index($0, "PORTS"); print; next }
    pcol > 0 && length($0) >= pcol {
        pre = substr($0, 1, pcol - 1)
        p = substr($0, pcol)
        gsub(/0\.0\.0\.0:/, "", p)
        gsub(/\[::\]:/, "", p)
        gsub(/:::/, "", p)
        n = split(p, a, ", ")
        r = ""
        for (i = 1; i <= n; i++) {
            d = 0
            for (j = 1; j < i; j++) if (a[j] == a[i]) { d = 1; break }
            if (!d && a[i] != "") {
                if (r != "") r = r ", "
                r = r a[i]
            }
        }
        print pre r
    }
    pcol > 0 && length($0) < pcol { print }
    pcol == 0 { print }'
}

# Draw a responsive Unicode box around content with colored border
_ov_draw_box() {
    _bt="$1"    # title text
    _bc="$2"    # content (multi-line)
    _bclr="$3"  # color escape code

    # Trim trailing whitespace for a tighter box
    _bc=$(printf '%s\n' "$_bc" | sed 's/ *$//')

    # Max content line width (ASCII → wc -L = byte length = display width)
    _mcw=$(printf '%s\n' "$_bc" | wc -L)

    # Title display width (wc -L handles UTF-8 em dash correctly)
    _tdw=$(printf '%s' "$_bt" | wc -L)

    # Inner width (between │ and │)
    _iw=$(( _mcw + 2 ))
    [ "$(( _tdw + 4 ))" -gt "$_iw" ] && _iw=$(( _tdw + 4 ))

    # Top: ┌─ TITLE ─────┐
    _rf=$(( _iw - _tdw - 3 ))
    _rd=$(printf '%*s' "$_rf" '' | sed 's/ /─/g')
    printf '%b┌─ %s %s┐%b\n' "$_bclr" "$_bt" "$_rd" "$_C_RESET"

    # Content: │ line...    │
    _pw=$(( _iw - 2 ))
    printf '%s\n' "$_bc" | while IFS= read -r _bl; do
        printf '%b│%b %-*s %b│%b\n' \
            "$_bclr" "$_C_RESET" "$_pw" "$_bl" "$_bclr" "$_C_RESET"
    done

    # Bottom: └─────────────┘
    _bd=$(printf '%*s' "$_iw" '' | sed 's/ /─/g')
    printf '%b└%s┘%b\n\n' "$_bclr" "$_bd" "$_C_RESET"
}

cmd_overview() {
    . "$PVC_LIB/lib/lxc.sh"

    # Use compact format + box when user didn't specify --format
    _use_compact=1
    for _arg in "$@"; do
        case "$_arg" in
            --format*) _use_compact=0 ;;
        esac
    done

    _found=0

    for _conf in /etc/pve/lxc/*.conf; do
        [ -f "$_conf" ] || continue

        _ctid=$(basename "$_conf" .conf)

        # Skip templates
        grep -q '^template: *1' "$_conf" && continue

        # Must be running
        lxc_is_running "$_ctid" || continue

        # Get docker ps output
        if [ "$_use_compact" = "1" ]; then
            _output=$(lxc_exec "$_ctid" docker ps \
                --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" \
                "$@" 2>/dev/null) || continue
            _output=$(printf '%s\n' "$_output" | _ov_clean_ports)
        else
            _output=$(lxc_exec "$_ctid" docker ps "$@" 2>/dev/null) || continue
        fi

        # Skip if only header line (no containers)
        _lines=$(printf '%s\n' "$_output" | wc -l)
        [ "$_lines" -gt 1 ] || continue

        # Extract hostname + IP
        _host=$(sed -n 's/^hostname: *//p' "$_conf")
        _ip=$(lxc_exec "$_ctid" hostname -I 2>/dev/null | awk '{print $1}')
        [ -n "$_ip" ] || _ip="no-ip"

        _title="CT $_ctid - $_host ($_ip)"

        if [ "$_use_compact" = "1" ]; then
            _ov_draw_box "$_title" "$_output" "${_C_CYAN}${_C_BOLD}"
        else
            # shellcheck disable=SC2059
            printf "${_C_CYAN}${_C_BOLD}── %s ──${_C_RESET}\n" "$_title"
            printf '%s\n\n' "$_output"
        fi
        _found=1
    done

    [ "$_found" = "1" ] || info "No running containers with Docker found."
}
