#!/bin/sh
# lib/tags.sh - Tag template expansion for pve-compose
# Sourced by commands - never executed directly.
# Depends: lib/output.sh (for debug)

# tags_expand TAGS_STRING LXC_JSON
# Expands {var} placeholders in tag string using values from resolved lxc.json.
# Supported variables: {hostname}, {ctid}, {cores}, {memory}, {swap},
#   {storage}, {disk}, {bridge}, {ipv4} (strips CIDR), {gateway}, {dns}
# Unknown {var} are left as-is.
#
# Example:
#   tags_expand "pve-compose;{hostname};ip-{ipv4}" '{"hostname":"app","ipv4":"192.168.1.10/24",...}'
#   → "pve-compose;app;ip-192.168.1.10"
tags_expand() {
    _te_tags="$1"
    _te_json="$2"

    # No braces? Nothing to expand
    case "$_te_tags" in
        *"{"*"}"*) ;;
        *) printf '%s' "$_te_tags"; return 0 ;;
    esac

    # Extract fields from JSON
    _te_hostname=$(printf '%s' "$_te_json" | jq -r '.hostname // empty' 2>/dev/null)
    _te_ctid=$(printf '%s' "$_te_json" | jq -r '.ctid // empty' 2>/dev/null)
    _te_cores=$(printf '%s' "$_te_json" | jq -r '.cores // empty' 2>/dev/null)
    _te_memory=$(printf '%s' "$_te_json" | jq -r '.memory // empty' 2>/dev/null)
    _te_swap=$(printf '%s' "$_te_json" | jq -r '.swap // empty' 2>/dev/null)
    _te_storage=$(printf '%s' "$_te_json" | jq -r '.storage // empty' 2>/dev/null)
    _te_disk=$(printf '%s' "$_te_json" | jq -r '.disk // empty' 2>/dev/null)
    _te_bridge=$(printf '%s' "$_te_json" | jq -r '.bridge // empty' 2>/dev/null)
    _te_gateway=$(printf '%s' "$_te_json" | jq -r '.gateway // empty' 2>/dev/null)
    _te_dns=$(printf '%s' "$_te_json" | jq -r '.dns // empty' 2>/dev/null)

    # ipv4 - strip CIDR suffix (/24, /16, etc.)
    _te_ipv4=$(printf '%s' "$_te_json" | jq -r '.ipv4 // empty' 2>/dev/null)
    case "$_te_ipv4" in
        */*)  _te_ipv4=$(printf '%s' "$_te_ipv4" | cut -d/ -f1) ;;
    esac

    # Replace each {var}
    _te_result="$_te_tags"
    _te_result=$(printf '%s' "$_te_result" | sed "s/{hostname}/$_te_hostname/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{ctid}/$_te_ctid/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{cores}/$_te_cores/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{memory}/$_te_memory/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{swap}/$_te_swap/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{storage}/$_te_storage/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{disk}/$_te_disk/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{bridge}/$_te_bridge/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{ipv4}/$_te_ipv4/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{gateway}/$_te_gateway/g")
    _te_result=$(printf '%s' "$_te_result" | sed "s/{dns}/$_te_dns/g")

    debug "tags_expand: '$_te_tags' → '$_te_result'"

    # Filter invalid tags: remove "dhcp" (useless) and unresolved {var} (invalid in Proxmox)
    _te_filtered=""
    _te_old_ifs="$IFS"
    IFS=";"
    for _te_tag in $_te_result; do
        [ -n "$_te_tag" ] || continue
        case "$_te_tag" in
            dhcp)   continue ;;  # Skip - no useful info
            *"{"*"}"*) continue ;;  # Skip - unresolved placeholder, invalid in Proxmox tags
        esac
        if [ -n "$_te_filtered" ]; then
            _te_filtered="$_te_filtered;$_te_tag"
        else
            _te_filtered="$_te_tag"
        fi
    done
    IFS="$_te_old_ifs"

    printf '%s' "$_te_filtered"
}
