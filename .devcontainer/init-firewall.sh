#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Whitelist-only firewall for Claude Code devcontainer
#
# Default policy: DROP all outbound traffic, then selectively ACCEPT traffic
# to known-good destinations (GitHub, npm, Anthropic, PyPI, Cargo, etc.).
###############################################################################

# ---------------------------------------------------------------------------
# Disable IPv6 (defense-in-depth — iptables rules are IPv4-only)
# ---------------------------------------------------------------------------
sysctl -w net.ipv6.conf.all.disable_ipv6=1 >/dev/null 2>&1 || true
sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# Flush existing rules
# ---------------------------------------------------------------------------
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

# Destroy existing ipsets (ignore errors if they don't exist)
ipset destroy allowed-ips 2>/dev/null || true
ipset destroy allowed-cidrs 2>/dev/null || true

# ---------------------------------------------------------------------------
# Create ipsets
# ---------------------------------------------------------------------------
ipset create allowed-ips hash:ip
ipset create allowed-cidrs hash:net

# ---------------------------------------------------------------------------
# Helper: resolve domain and add IPs to allowed-ips set
# ---------------------------------------------------------------------------
allow_domain() {
    local domain="$1"
    local ips
    ips=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.' || true)
    if [ -z "$ips" ]; then
        echo "WARNING: Could not resolve $domain — skipping"
        return 0
    fi
    for ip in $ips; do
        ipset add allowed-ips "$ip" 2>/dev/null || true
    done
    echo "Allowed: $domain → $ips"
}

# ---------------------------------------------------------------------------
# GitHub IP ranges (from GitHub meta API)
# ---------------------------------------------------------------------------
echo "Fetching GitHub IP ranges..."
GITHUB_META=$(curl -sf https://api.github.com/meta 2>/dev/null || echo "{}")
if [ "$GITHUB_META" != "{}" ]; then
    for cidr in $(echo "$GITHUB_META" | jq -r '
        (.hooks + .web + .api + .git + .packages + .pages
         + .importer + .actions + .dependabot + .copilot)
        | .[]' 2>/dev/null | sort -u); do
        # Skip IPv6 CIDRs
        echo "$cidr" | grep -q ':' && continue
        ipset add allowed-cidrs "$cidr" 2>/dev/null || true
    done
    echo "Allowed: GitHub IP ranges"
else
    echo "WARNING: Could not fetch GitHub meta — GitHub CIDRs not added"
fi

# ---------------------------------------------------------------------------
# Anthropic & telemetry
# ---------------------------------------------------------------------------
allow_domain "api.anthropic.com"
allow_domain "sentry.io"
allow_domain "statsig.anthropic.com"
allow_domain "statsig.com"

# ---------------------------------------------------------------------------
# Claude native installer (auto-update)
# ---------------------------------------------------------------------------
allow_domain "claude.ai"
allow_domain "storage.googleapis.com"

# ---------------------------------------------------------------------------
# npm registry
# ---------------------------------------------------------------------------
allow_domain "registry.npmjs.org"

# ---------------------------------------------------------------------------
# PyPI (Python packages)
# ---------------------------------------------------------------------------
allow_domain "pypi.org"
allow_domain "files.pythonhosted.org"

# ---------------------------------------------------------------------------
# Cargo / crates.io (Rust packages)
# ---------------------------------------------------------------------------
allow_domain "crates.io"
allow_domain "static.crates.io"
allow_domain "index.crates.io"
allow_domain "static.rust-lang.org"

# ---------------------------------------------------------------------------
# VS Code / extensions
# ---------------------------------------------------------------------------
allow_domain "update.code.visualstudio.com"
allow_domain "marketplace.visualstudio.com"
allow_domain "vscode.blob.core.windows.net"
allow_domain "az764295.vo.msecnd.net"
allow_domain "gallery.vsassets.io"
allow_domain "open-vsx.org"

# ---------------------------------------------------------------------------
# Default policies
# ---------------------------------------------------------------------------
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# ---------------------------------------------------------------------------
# Allow loopback
# ---------------------------------------------------------------------------
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ---------------------------------------------------------------------------
# Allow established / related connections
# ---------------------------------------------------------------------------
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ---------------------------------------------------------------------------
# Allow DNS (UDP + TCP port 53) — needed for domain resolution
# ---------------------------------------------------------------------------
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

# ---------------------------------------------------------------------------
# Allow SSH (port 22) — needed for git over SSH
# ---------------------------------------------------------------------------
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT

# ---------------------------------------------------------------------------
# Allow traffic to host network (Docker host communication)
# ---------------------------------------------------------------------------
# Common Docker bridge gateway
iptables -A OUTPUT -d 172.17.0.0/16 -j ACCEPT
# Host-mapped gateway
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT

# ---------------------------------------------------------------------------
# Allow whitelisted IPs and CIDRs (HTTPS)
# ---------------------------------------------------------------------------
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-ips dst -j ACCEPT
iptables -A OUTPUT -p tcp --dport 443 -m set --match-set allowed-cidrs dst -j ACCEPT

# Also allow HTTP (port 80) for redirects and some registries
iptables -A OUTPUT -p tcp --dport 80 -m set --match-set allowed-ips dst -j ACCEPT
iptables -A OUTPUT -p tcp --dport 80 -m set --match-set allowed-cidrs dst -j ACCEPT

# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------
echo ""
echo "=== Firewall configured ==="
echo "Allowed IPs:   $(ipset list allowed-ips   | grep -c 'Members' || echo 0) entries"
echo "Allowed CIDRs: $(ipset list allowed-cidrs | grep -c 'Members' || echo 0) entries"
echo ""
echo "Testing blocked domain (example.com)..."
if curl --connect-timeout 3 -sf https://example.com >/dev/null 2>&1; then
    echo "ERROR: example.com is reachable — firewall may not be working!"
    exit 1
else
    echo "OK: example.com is blocked"
fi

echo "Testing allowed domain (api.github.com)..."
if curl --connect-timeout 5 -sf https://api.github.com/zen >/dev/null 2>&1; then
    echo "OK: api.github.com is reachable"
else
    echo "WARNING: api.github.com is not reachable — GitHub IPs may have changed"
fi

echo ""
echo "Firewall initialization complete."
