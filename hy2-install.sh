#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="3.4.0-FullService"
HY_BIN="/usr/local/bin/hysteria"
HY_DIR="/etc/hysteria"
HY_CFG="${HY_DIR}/config.yaml"
CLASH_CFG="${HY_DIR}/clash-config.yaml"  # <--- 新增：Clash配置文件路径
SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
WEB_ROOT="/var/www/html"

PKG_MGR=""
ACTION=""
SERVER_HOST=""
PORT=""
AUTH_PASSWORD=""
OBFS_PASSWORD=""
CERT_KEY="${HY_DIR}/server.key"
CERT_CRT="${HY_DIR}/server.crt"

red() { echo -e "\033[31m$*\033[0m"; }
green() { echo -e "\033[32m$*\033[0m"; }
yellow() { echo -e "\033[33m$*\033[0m"; }
blue() { echo -e "\033[36m$*\033[0m"; }

on_error() {
  local line="$1"
  red "[ERROR] Script failed at line ${line}"
}
trap 'on_error $LINENO' ERR

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    red "Run as root: sudo bash $0"
    exit 1
  fi
}

clear_ports() {
  blue "[0/14] Scanning for port conflicts (80, 443)..."
  local ports=(80 443)
  if ! command_exists ss; then
    case "${PKG_MGR}" in
      apt) apt update -y && apt install -y iproute2 ;;
      dnf) dnf install -y iproute2 ;;
      yum) yum install -y iproute2 ;;
    esac
  fi
  for port in "${ports[@]}"; do
    local pid
    pid=$(ss -tunlp | grep -E ":${port}\s" | grep -oP 'pid=\K[0-9]+' | head -n 1 || true)
    if [[ -n "$pid" ]]; then
      yellow "Port ${port} is occupied by PID ${pid}. Terminating..."
      kill -9 "$pid" 2>/dev/null || true
      green "Port ${port} cleared."
    else
      green "Port ${port} is available."
    fi
  done
}

get_public_ip() {
  local ip
  ip=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com)
  echo "${ip}"
}

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    red "Unsupported system"; exit 1
  fi
  source /etc/os-release
  case "${ID}" in
    ubuntu|debian) PKG_MGR="apt" ;;
    centos|rhel|rocky|almalinux|ol|fedora)
      if command_exists dnf; then PKG_MGR="dnf"; else PKG_MGR="yum"; fi
      ;;
    *) red "Unsupported OS"; exit 1 ;;
  esac
}

install_dependencies() {
  blue "[1/14] Installing dependencies & Nginx..."
  case "${PKG_MGR}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt update -y && apt install -y curl wget ca-certificates openssl tar jq socat nginx ;;
    dnf)
      dnf install -y curl wget ca-certificates openssl tar jq socat nginx ;;
    yum)
      yum install -y epel-release 2>/dev/null || true
      yum install -y curl wget ca-certificates openssl tar jq socat nginx ;;
  esac
  systemctl enable nginx >/dev/null 2>&1 || true
}

deploy_nova_template() {
  cat > "${WEB_ROOT}/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"><title>NovaStream Cloud</title>
    <style>
        :root { --p: #2563eb; --d: #0f172a; --l: #f8fafc; }
        body { font-family: sans-serif; margin: 0; background: var(--l); color: var(--d); text-align: center; }
        nav { background: white; padding: 1rem; display: flex; justify-content: space-between; align-items: center; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
        .hero { background: linear-gradient(135deg, var(--d) 0%, #1e293b 100%); color: white; padding: 100px 20px; }
        .btn { background: var(--p); color: white; padding: 12px 30px; border-radius: 5px; text-decoration: none; font-weight: bold; }
        .feat { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; padding: 50px 10%; }
        .card { background: white; padding: 30px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <nav><div style="font-weight:bold; color:var(--p); font-size:1.5rem">NovaStream</div><a href="#" class="btn">Login</a></nav>
    <div class="hero"><h1>Scale Your Vision</h1><p>The most reliable cloud infrastructure for global enterprises.</p><br><a href="#" class="btn">Get Started</a></div>
    <div class="feat">
        <div class="card"><h3>Fast</h3><p>Low latency edge nodes.</p></div>
        <div class="card"><h3>Secure</h3><p>Enterprise grade encryption.</p></div>
        <div class="card"><h3>Global</h3><p>Deploy anywhere in seconds.</p></div>
    </div>
</body>
</html>
EOF
}

setup_website() {
  blue "[2/14] Website Template Selection..."
  echo "--------------------------------------------------------------------------"
  echo "1) [Built-in] NovaStream Tech (Modern/Corporate)"
  echo "2) [Online] Minimalist Portfolio (Clean/White)"
  echo "3) [Online] Dark Mode Landing Page (Sleek/Black)"
  echo "4) [Custom URL] Enter a remote .html link"
  echo "5) [Local Path] Use your own local files (dir or file)"
  echo "--------------------------------------------------------------------------"
  read -rp "Choose template [1-5]: " web_choice
  mkdir -p "${WEB_ROOT}"
  case "${web_choice}" in
    1) deploy_nova_template; green "NovaStream deployed." ;;
    2) curl -fsSL "https://raw.githubusercontent.com/gist-templates/minimal-html/main/index.html" -o "${WEB_ROOT}/index.html" || deploy_nova_template ;;
    3) curl -fsSL "https://raw.githubusercontent.com/gist-templates/dark-landing/main/index.html" -o "${WEB_ROOT}/index.html" || deploy_nova_template ;;
    4) read -rp "Enter HTML URL: " custom_url; curl -fsSL "${custom_url}" -o "${WEB_ROOT}/index.html" || deploy_nova_template ;;
    5) 
       read -rp "Enter local path: " local_path
       if [[ -d "${local_path}" ]]; then cp -r "${local_path}"/* "${WEB_ROOT}/"; elif [[ -f "${local_path}" ]]; then cp "${local_path}" "${WEB_ROOT}/index.html"; else deploy_nova_template; fi
       ;;
    *) deploy_nova_template ;;
  esac
}

install_hysteria_binary() {
  blue "[3/14] Installing Hysteria2 binary..."
  curl -fsSL https://get.hy2.sh | bash
  if [[ -x "/usr/local/bin/hysteria" ]]; then HY_BIN="/usr/local/bin/hysteria"
  elif [[ -x "/usr/bin/hysteria" ]]; then HY_BIN="/usr/bin/hysteria"
  else red "Binary not found"; exit 1; fi
}

read_install_inputs() {
  blue "[4/14] Collecting config..."
  read -rp "Server host (domain or IP): " SERVER_HOST
  [[ -z "${SERVER_HOST}" ]] && { red "Host cannot be empty"; exit 1; }
  read -rp "Listen port (default 443): " PORT
  PORT="${PORT:-443}"
  read -rp "Auth password (empty = random): " AUTH_PASSWORD
  AUTH_PASSWORD="${AUTH_PASSWORD:-$(openssl rand -hex 16)}"
  read -rp "OBFS password (empty = random): " OBFS_PASSWORD
  OBFS_PASSWORD="${OBFS_PASSWORD:-$(openssl rand -hex 16)}"
}

generate_self_signed_cert() {
  local host="${1:-${SERVER_HOST}}"
  blue "Generating self-signed certificate for ${host}..."
  mkdir -p "${HY_DIR}"
  local san_type="IP"
  [[ ! "${host}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && san_type="DNS"
  local openssl_cfg
  openssl_cfg="$(mktemp)"
  cat > "${openssl_cfg}" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = v3_req
[dn]
CN = ${host}
[v3_req]
subjectAltName = @alt_names
[alt_names]
${san_type}.1 = ${host}
EOF
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "${CERT_KEY}" -out "${CERT_CRT}" -config "${openssl_cfg}" >/dev/null 2>&1
  rm -f "${openssl_cfg}"
}

issue_acme_cert() {
  blue "Requesting ACME certificate for ${SERVER_HOST}..."
  mkdir -p "${HY_DIR}"
  curl https://get.acme.sh | sh
  local acme_bin="$HOME/.acme.sh/acme.sh"
  "${acme_bin}" --register-account -m "admin@${SERVER_HOST}" >/dev/null 2>&1
  systemctl stop nginx >/dev/null 2>&1 || true
  if "${acme_bin}" --issue -d "${SERVER_HOST}" --standalone >/dev/null 2>&1; then
    "${acme_bin}" --install-cert -d "${SERVER_HOST}" \
      --key-file "${CERT_KEY}" --fullchain-file "${CERT_CRT}" >/dev/null 2>&1
    green "ACME certificate issued!"
    CERT_MODE="acme"
  else
    red "ACME failed!"
    local public_ip
    public_ip=$(get_public_ip)
    if [[ -n "${public_ip}" ]]; then
      yellow "Switching to IP-based self-signed cert..."
      SERVER_HOST="${public_ip}"
      generate_self_signed_cert "${public_ip}"
      CERT_MODE="self-signed"
    else
      generate_self_signed_cert "${SERVER_HOST}"
      CERT_MODE="self-signed"
    fi
  fi
  systemctl start nginx >/dev/null 2>&1 || true
}

handle_certs() {
  blue "[5/14] Handling certificates..."
  if [[ "${SERVER_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    generate_self_signed_cert
    CERT_MODE="self-signed"
  else
    issue_acme_cert
  fi
}

write_server_config() {
  blue "[6/14] Writing Hysteria2 config..."
  cat > "${HY_CFG}" <<EOF
listen: :${PORT}
tls:
  cert: ${CERT_CRT}
  key: ${CERT_KEY}
auth:
  type: password
  password: ${AUTH_PASSWORD}
obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASSWORD}
masquerade:
  type: proxy
  proxy:
    url: http://127.0.0.1:80
    rewriteHost: true
bandwidth:
  up: 100 mbps
  down: 1000 mbps
ignoreClientBandwidth: false
EOF
  chmod 600 "${HY_CFG}"
}

# --- 新增：生成 Clash 配置文件模块 ---
write_clash_config() {
  blue "[7/14] Generating local Clash Meta config..."
  local skip_verify="true"
  [[ "${CERT_MODE}" == "acme" ]] && skip_verify="false"

  cat > "${CLASH_CFG}" <<EOF
port: 7890
socks-port: 7891
allow-lan: true
mode: rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:9090

proxies:
  - name: "🚀 HY2-Server"
    type: hysteria2
    server: ${SERVER_HOST}
    port: ${PORT}
    password: ${AUTH_PASSWORD}
    obfs: salamander
    obfs-password: ${OBFS_PASSWORD}
    skip-cert-verify: ${skip_verify}
    sni: ${SERVER_HOST}

proxy-groups:
  - name: "🚀 节点选择"
    type: select
    proxies:
      - "🚀 HY2-Server"
      - "DIRECT"

rules:
  - GEOIP,CN,DIRECT
  - DOMAIN-SUFFIX,cn,DIRECT
  - MATCH,🚀 节点选择
EOF
  chmod 644 "${CLASH_CFG}"
}

write_systemd_service() {
  blue "[8/14] Writing systemd service..."
  cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Hysteria2 Server Service
After=network-online.target nss-lookup.target nginx.service
Wants=network-online.target nginx.service

[Service]
Type=simple
ExecStart=${HY_BIN} server -c ${HY_CFG}
Restart=always
RestartSec=5s
LimitNOFILE=1048576
ProtectSystem=full
ReadWritePaths=${HY_DIR}

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable hysteria-server >/dev/null 2>&1 || true
}

open_firewall_port() {
  local p="$1"
  blue "[9/14] Opening firewall ports..."
  if command_exists ufw && ufw status | grep -q "Status: active"; then
    ufw allow "${p}/tcp" && ufw allow "${p}/udp" && ufw allow 80/tcp || true
  elif command_exists firewall-cmd && firewall-cmd --state | grep -q "running"; then
    firewall-cmd --permanent --add-port="${p}/tcp" && firewall-cmd --permanent --add-port="${p}/udp" && firewall-cmd --permanent --add-port=80/tcp && firewall-cmd --reload || true
  elif command_exists iptables; then
    iptables -I INPUT -p tcp --dport "${p}" -j ACCEPT || true
    iptables -I INPUT -p udp --dport "${p}" -j ACCEPT || true
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true
  fi
}

start_and_verify() {
  blue "[10/14] Starting services..."
  systemctl restart nginx
  systemctl restart hysteria-server
  sleep 3
  if ! systemctl is-active --quiet hysteria-server; then
    red "Hysteria2 failed to start"; journalctl -u hysteria-server -n 50 --no-pager; exit 1
  fi
  green "All services are running!"
}

show_summary() {
  local insecure="insecure=1"
  [[ "${CERT_MODE}" == "acme" ]] && insecure="insecure=0"
  CONNECTION_URI="hy2://${AUTH_PASSWORD}@${SERVER_HOST}:${PORT}/?sni=${SERVER_HOST}&${insecure}&obfs=salamander&obfs-password=${OBFS_PASSWORD}#hy2-${SERVER_HOST}"
  
  echo -e "\n\033[32m==========================================\n🚀 Deployment Complete (v3.4)\n==========================================\033[0m"
  echo "Final Host  : ${SERVER_HOST}"
  echo "Cert Mode   : ${CERT_MODE}"
  echo "URI         : ${CONNECTION_URI}"
  echo "------------------------------------------"
  echo "Clash Config: ${CLASH_CFG}"
  echo -e "Copy command: \033[33mcat ${CLASH_CFG}\033[0m"
  echo "------------------------------------------"
  echo -e "\nTest it: Visit http://${SERVER_HOST} in browser."
}

run_install() {
  detect_os
  clear_ports
  install_dependencies
  setup_website
  install_hysteria_binary
  read_install_inputs
  handle_certs
  write_server_config
  write_clash_config    # <--- 关键：生成 Clash 配置
  write_systemd_service
  open_firewall_port "${PORT}"
  start_and_verify
  show_summary
}

main() {
  require_root
  if [[ "$#" -gt 0 ]]; then
    case "$1" in
      --install) ACTION="install" ;;
      --uninstall) ACTION="uninstall" ;;
      *) red "Unknown arg"; exit 1 ;;
    esac
  else
    echo "1) Install (Full Service)  2) Uninstall"
    read -rp "Choose: " choice
    [[ "$choice" == "1" ]] && ACTION="install" || ACTION="uninstall"
  fi
  if [[ "${ACTION}" == "install" ]]; then
    run_install
  else
    systemctl stop hysteria-server nginx 2>/dev/null || true
    rm -rf "${HY_DIR}" "${SERVICE_FILE}" "${HY_BIN}" "${WEB_ROOT}"
    systemctl daemon-reload
    green "Uninstalled everything."
  fi
}

main "$@"