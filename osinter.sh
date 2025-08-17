#!/usr/bin/env bash

# Lightweight website recon runner
# Usage: ./osinter.sh example.com

set -euo pipefail

# ---------- UI ----------
RED="\033[1;31m"
GRN="\033[1;32m"
YEL="\033[1;33m"
BLU="\033[1;34m"
RESET="\033[0m"

# ---------- Args & domain sanitization ----------
if [[ $# -lt 1 ]]; then
  echo -e "${RED}Usage:${RESET} $0 <domain>"
  exit 1
fi

domain_raw="$1"
# strip scheme, trailing slash, whitespace
domain="$(printf "%s" "$domain_raw" | sed -E 's#^https?://##; s#/$##' | tr -d '[:space:]')"

if [[ -z "$domain" ]]; then
  echo -e "${RED}[-] Invalid domain provided.${RESET}"
  exit 1
fi

timestamp="$(date +%Y-%m-%d_%H-%M-%S)"

# Keep runs separate per domain and per timestamp
base_dir="results/$domain/$timestamp"
info_path="$base_dir/info"
subdomain_path="$base_dir/subdomains"
screenshot_path="$base_dir/screenshots"
mkdir -p "$info_path" "$subdomain_path" "$screenshot_path"

# ---------- Dependency checks ----------
missing=0
check_tool() {
  local t="$1"
  if ! command -v "$t" >/dev/null 2>&1; then
    echo -e "${RED}[-] Missing tool: ${t}${RESET}"
    missing=1
  else
    echo -e "${GRN}[+] Found ${t}${RESET}"
  fi
}

echo -e "${BLU}[*] Checking required tools...${RESET}"
for t in whois subfinder assetfinder httprobe gowitness; do
  check_tool "$t"
done

if [[ $missing -eq 1 ]]; then
  if [[ -f "./config.sh" ]]; then
    echo -e "${YEL}One or more tools are missing. Please run:${RESET} ./config.sh"
  else
    echo -e "${YEL}One or more tools are missing. Install them and ensure they are in your \$PATH.${RESET}"
  fi
  exit 1
fi

# ---------- Traps for graceful exits ----------
trap 'echo -e "\n${RED}[!] Aborted by user (Ctrl+C).${RESET}"; exit 1' INT
trap 'echo -e "\n${RED}[!] An error occurred. Partial output (if any) is in:${RESET} ${base_dir}"' ERR

# ---------- WHOIS ----------
echo -e "${BLU}[*] Whois lookup for ${domain}...${RESET}"
whois "$domain" > "$info_path/whois-${timestamp}.txt" || true  # whois can be rate-limited; don't abort

# ---------- Subdomain enumeration (subfinder + assetfinder) ----------
echo -e "${BLU}[*] Enumerating subdomains (subfinder + assetfinder)...${RESET}"
tmp_all="$subdomain_path/_all_raw.txt"

subfinder -d "$domain" 2>/dev/null | sed '/^$/d' >> "$tmp_all" || true
assetfinder "$domain" 2>/dev/null | grep -F "$domain" >> "$tmp_all" || true

found_file="$subdomain_path/found-${timestamp}.txt"
sort -u "$tmp_all" > "$found_file"
found_count="$(wc -l < "$found_file" || echo 0)"
echo -e "${GRN}[+] Unique subdomains: ${found_count}${RESET}"

# ---------- Live host probing (HTTPS preferred) ----------
echo -e "${BLU}[*] Probing for live hosts (HTTPS preferred)...${RESET}"
alive_urls="$subdomain_path/alive-urls-${timestamp}.txt"
# Feed hostnames (no scheme) to httprobe; it prints full URLs
sed 's#^https\?://##' "$found_file" \
  | httprobe -prefer-https 2>/dev/null \
  | sort -u | tee "$alive_urls" >/dev/null
alive_count="$(wc -l < "$alive_urls" || echo 0)"
echo -e "${GRN}[+] Live URLs: ${alive_count}${RESET}"

# ---------- Screenshots ----------
if [[ "$alive_count" -gt 0 ]]; then
  echo -e "${BLU}[*] Taking screenshots with gowitness...${RESET}"
  # gowitness 'scan file' expects URLs; we already have URLs
  gowitness scan file -f "$alive_urls" -s "$screenshot_path" --no-http || true
else
  echo -e "${YEL}[!] No live hosts to screenshot.${RESET}"
fi

# ---------- Convenience: update 'latest' symlink ----------
ln -sfn "$base_dir" "results/$domain/latest"

# ---------- Summary ----------
echo -e "${GRN}\n[✓] Done.${RESET}"
echo -e "Base dir : $base_dir"
echo -e "Whois    : $info_path/whois-${timestamp}.txt"
echo -e "Found    : $found_file (${found_count})"
echo -e "Alive    : $alive_urls (${alive_count})"
echo -e "Screens  : $screenshot_path"
