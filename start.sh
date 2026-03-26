#!/usr/bin/env bash
set -euo pipefail

GREEN="$(printf '\033[1;32m')"
YELLOW="$(printf '\033[1;33m')"
RED="$(printf '\033[1;31m')"
CYAN="$(printf '\033[1;36m')"
RESET="$(printf '\033[0m')"

log_info() {
  printf '%s[paperclip-init]%s %s\n' "$YELLOW" "$RESET" "$1"
}

log_ok() {
  printf '%s[paperclip-init]%s %s\n' "$GREEN" "$RESET" "$1"
}

log_error() {
  printf '%s[paperclip-init]%s %s\n' "$RED" "$RESET" "$1"
}

log_url() {
  printf '%s[paperclip-init]%s %s%s%s\n' "$GREEN" "$RESET" "$CYAN" "$1" "$RESET"
}

is_valid_url() {
  node -e "new URL(process.argv[1]); process.exit(0)" "$1" >/dev/null 2>&1
}

extract_hostname() {
  node -p "new URL(process.argv[1]).hostname" "$1" 2>/dev/null
}

sync_config_public_url() {
  local public_url="$1"
  local config_path="/paperclip/instances/default/config.json"

  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  node - "$config_path" "$public_url" <<'EOF'
const fs = require('fs');

const configPath = process.argv[2];
const publicUrl = process.argv[3];
const hostname = new URL(publicUrl).hostname;

const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
config.auth ??= {};
config.auth.publicBaseUrl = publicUrl;

const trustedOrigins = new Set(Array.isArray(config.auth.trustedOrigins) ? config.auth.trustedOrigins : []);
trustedOrigins.add(publicUrl);
trustedOrigins.add(`http://${hostname}`);
trustedOrigins.add(`https://${hostname}`);
config.auth.trustedOrigins = Array.from(trustedOrigins);

fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + '\n');
EOF
}

resolve_public_url() {
  local candidate

  for candidate in "${PAPERCLIP_PUBLIC_URL:-}" "${SERVICE_URL_SERVER:-}"; do
    if [[ -n "$candidate" ]] && is_valid_url "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  if [[ -n "${SERVICE_FQDN_SERVER:-}" ]]; then
    candidate="https://${SERVICE_FQDN_SERVER}"
    if is_valid_url "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  fi

  return 1
}

bootstrap_ceo() {
  local bootstrap_output=""
  local bootstrap_url=""

  if [[ "${PAPERCLIP_AUTO_BOOTSTRAP_CEO:-true}" != "true" ]]; then
    return 0
  fi

  if [[ -f /paperclip/bootstrap-ceo-url.txt ]]; then
    return 0
  fi

  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${PORT:-3100}/" >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  bootstrap_output="$(pnpm paperclipai auth bootstrap-ceo 2>&1 || true)"
  printf '%s\n' "$bootstrap_output" | tee /paperclip/bootstrap-ceo-url.txt >/dev/null
  log_ok "bootstrap CEO output saved to ${CYAN}/paperclip/bootstrap-ceo-url.txt${RESET}"
  bootstrap_url="$(printf '%s\n' "$bootstrap_output" | grep -Eo 'https://[^[:space:]]+' | tail -n 1 || true)"
  if [[ -n "$bootstrap_url" ]]; then
    log_url "$bootstrap_url"
  else
    printf '%s\n' "$bootstrap_output" | sed "s#^#${GREEN}[paperclip-init]${RESET} #"
  fi
}

main() {
  local public_url=""
  local allowed_hostname=""

  if [[ ! -f /paperclip/instances/default/config.json ]]; then
    log_info "running onboard -y"
    pnpm paperclipai onboard -y || true
  fi

  if public_url="$(resolve_public_url)"; then
    export PAPERCLIP_PUBLIC_URL="$public_url"
    log_info "public url: ${CYAN}${public_url}${RESET}"
    sync_config_public_url "$public_url"

    allowed_hostname="$(extract_hostname "$public_url")"
    if [[ -n "$allowed_hostname" ]]; then
      log_info "allowing hostname: ${CYAN}${allowed_hostname}${RESET}"
      pnpm paperclipai allowed-hostname "$allowed_hostname" >/dev/null 2>&1 || true
    fi
  else
    unset PAPERCLIP_PUBLIC_URL || true
    log_error "no valid public URL found. Set ${CYAN}PAPERCLIP_PUBLIC_URL${RESET} or configure the Coolify service URL."
  fi

  node --import ./server/node_modules/tsx/dist/loader.mjs server/dist/index.js &
  local server_pid=$!

  bootstrap_ceo

  wait "$server_pid"
}

main "$@"
