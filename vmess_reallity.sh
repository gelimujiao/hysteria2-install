#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="1.1.0"
XRAY_BIN="/usr/local/bin/xray"
XRAY_CFG="/usr/local/etc/xray/config.json"
XRAY_DIR="/usr/local/etc/xray"
SERVICE_NAME="xray"
WEB_ROOT="/var/www/html"
NGINX_SITE="/etc/nginx/conf.d/vmess_reality.conf"

# 443 由 Xray 接管；普通 HTTPS 流量 fallback 到 Nginx 的本地 TLS 端口
NGINX_TLS_LOCAL_PORT="8443"

PKG_MGR=""
ACTION=""
SERVER_HOST=""
REALITY_PORT=""
VMESS_WS_PATH=""
SNI_MASK=""
UUID=""
REALITY_PRIVATE_KEY=""
REALITY_PUBLIC_KEY=""
REALITY_SHORT_ID=""
CERT_KEY=""
CERT_CRT=""
CERT_MODE="self-signed"
SELF_TEST_TMP=""

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

get_public_ip() {
  local ip
  ip="$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || curl -s https://icanhazip.com || true)"
  echo "${ip}"
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local msg="$3"
  if grep -qE "${pattern}" "${file}"; then
    green "[PASS] ${msg}"
  else
    red "[FAIL] ${msg}"
    exit 1
  fi
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    red "Run as root: sudo bash $0"
    exit 1
  fi
}

detect_os() {
  if [[ ! -f /etc/os-release ]]; then
    red "Unsupported system"
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID}" in
    ubuntu|debian) PKG_MGR="apt" ;;
    centos|rhel|rocky|almalinux|ol|fedora)
      if command_exists dnf; then PKG_MGR="dnf"; else PKG_MGR="yum"; fi
      ;;
    *)
      red "Unsupported OS"
      exit 1
      ;;
  esac
}

install_dependencies() {
  blue "[1/12] Installing dependencies..."
  case "${PKG_MGR}" in
    apt)
      export DEBIAN_FRONTEND=noninteractive
      apt update -y
      apt install -y curl wget ca-certificates openssl jq socat nginx
      ;;
    dnf)
      dnf install -y curl wget ca-certificates openssl jq socat nginx
      ;;
    yum)
      yum install -y epel-release 2>/dev/null || true
      yum install -y curl wget ca-certificates openssl jq socat nginx
      ;;
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
  blue "[2/12] Website Template Selection..."
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
    4)
      read -rp "Enter HTML URL: " custom_url
      curl -fsSL "${custom_url}" -o "${WEB_ROOT}/index.html" || deploy_nova_template
      ;;
    5)
      read -rp "Enter local path: " local_path
      if [[ -d "${local_path}" ]]; then
        cp -r "${local_path}"/* "${WEB_ROOT}/"
      elif [[ -f "${local_path}" ]]; then
        cp "${local_path}" "${WEB_ROOT}/index.html"
      else
        deploy_nova_template
      fi
      ;;
    *)
      deploy_nova_template
      ;;
  esac
}

read_install_inputs() {
  blue "[3/12] Collecting config..."
  read -rp "Server host (domain or IP): " SERVER_HOST
  [[ -z "${SERVER_HOST}" ]] && { red "Host cannot be empty"; exit 1; }

  read -rp "Reality listen port (default 443): " REALITY_PORT
  REALITY_PORT="${REALITY_PORT:-443}"

  read -rp "VMess ws path (default /vmess): " VMESS_WS_PATH
  VMESS_WS_PATH="${VMESS_WS_PATH:-/vmess}"
  [[ "${VMESS_WS_PATH}" != /* ]] && VMESS_WS_PATH="/${VMESS_WS_PATH}"

  read -rp "Reality SNI camouflage domain (default www.microsoft.com): " SNI_MASK
  SNI_MASK="${SNI_MASK:-www.microsoft.com}"
}

install_xray() {
  blue "[4/12] Installing Xray..."
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root
  if [[ ! -x "${XRAY_BIN}" ]]; then
    red "Xray binary not found at ${XRAY_BIN}"
    exit 1
  fi
  mkdir -p "${XRAY_DIR}"
}

generate_runtime_values() {
  blue "[5/12] Generating UUID and Reality keys..."
  UUID="$("${XRAY_BIN}" uuid)"

  local x25519_out
  x25519_out="$("${XRAY_BIN}" x25519)"
  REALITY_PRIVATE_KEY="$(echo "${x25519_out}" | awk '/Private key:/ {print $3}')"
  REALITY_PUBLIC_KEY="$(echo "${x25519_out}" | awk '/Public key:/ {print $3}')"
  if [[ -z "${REALITY_PRIVATE_KEY}" || -z "${REALITY_PUBLIC_KEY}" ]]; then
    red "Failed to generate Reality keypair"
    exit 1
  fi

  REALITY_SHORT_ID="$(openssl rand -hex 8)"
}

generate_self_signed_cert() {
  blue "Generating self-signed cert for ${SERVER_HOST}..."
  mkdir -p "${XRAY_DIR}"
  CERT_KEY="${XRAY_DIR}/nginx.key"
  CERT_CRT="${XRAY_DIR}/nginx.crt"

  local san_type="IP"
  [[ ! "${SERVER_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && san_type="DNS"
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
CN = ${SERVER_HOST}
[v3_req]
subjectAltName = @alt_names
[alt_names]
${san_type}.1 = ${SERVER_HOST}
EOF
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout "${CERT_KEY}" -out "${CERT_CRT}" -config "${openssl_cfg}" >/dev/null 2>&1
  rm -f "${openssl_cfg}"
  CERT_MODE="self-signed"
}

issue_acme_cert() {
  blue "Requesting ACME cert for ${SERVER_HOST}..."
  mkdir -p "${XRAY_DIR}"
  CERT_KEY="${XRAY_DIR}/nginx.key"
  CERT_CRT="${XRAY_DIR}/nginx.crt"

  curl https://get.acme.sh | sh
  local acme_bin="$HOME/.acme.sh/acme.sh"
  "${acme_bin}" --register-account -m "admin@${SERVER_HOST}" >/dev/null 2>&1 || true
  systemctl stop nginx >/dev/null 2>&1 || true
  if "${acme_bin}" --issue -d "${SERVER_HOST}" --standalone >/dev/null 2>&1; then
    "${acme_bin}" --install-cert -d "${SERVER_HOST}" \
      --key-file "${CERT_KEY}" --fullchain-file "${CERT_CRT}" >/dev/null 2>&1
    CERT_MODE="acme"
    green "ACME certificate issued."
  else
    red "ACME failed!"
    local public_ip
    public_ip="$(get_public_ip)"
    if [[ -n "${public_ip}" ]]; then
      yellow "Switching to public IP for self-signed cert: ${public_ip}"
      SERVER_HOST="${public_ip}"
      generate_self_signed_cert
    else
      yellow "Public IP detection failed, fallback to self-signed on current host."
      generate_self_signed_cert
    fi
  fi
}

handle_certs() {
  blue "[6/12] Handling certificates..."
  if [[ "${SERVER_HOST}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    generate_self_signed_cert
  else
    issue_acme_cert
  fi
}

write_nginx_site() {
  blue "[7/12] Writing Nginx website config..."
  cat > "${NGINX_SITE}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${SERVER_HOST};
    return 301 https://\$host\$request_uri;
}

server {
    listen 127.0.0.1:${NGINX_TLS_LOCAL_PORT} ssl http2;
    server_name ${SERVER_HOST};

    ssl_certificate     ${CERT_CRT};
    ssl_certificate_key ${CERT_KEY};
    ssl_protocols TLSv1.2 TLSv1.3;

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
}

write_xray_config() {
  blue "[8/12] Writing Xray config..."
  cat > "${XRAY_CFG}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "listen": "127.0.0.1",
      "port": 10000,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "${VMESS_WS_PATH}"
        }
      }
    },
    {
      "tag": "reality-in",
      "listen": "0.0.0.0",
      "port": ${REALITY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "path": "${VMESS_WS_PATH}",
            "dest": "127.0.0.1:10000",
            "xver": 1
          },
          {
            "dest": "127.0.0.1:${NGINX_TLS_LOCAL_PORT}",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${SNI_MASK}:443",
          "xver": 0,
          "serverNames": [
            "${SNI_MASK}"
          ],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": [
            "${REALITY_SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
}

open_firewall_ports() {
  blue "[9/12] Opening firewall ports..."
  if command_exists ufw && ufw status | grep -q "Status: active"; then
    ufw allow 80/tcp || true
    ufw allow "${REALITY_PORT}/tcp" || true
  elif command_exists firewall-cmd && firewall-cmd --state | grep -q "running"; then
    firewall-cmd --permanent --add-port=80/tcp || true
    firewall-cmd --permanent --add-port="${REALITY_PORT}/tcp" || true
    firewall-cmd --reload || true
  elif command_exists iptables; then
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true
    iptables -I INPUT -p tcp --dport "${REALITY_PORT}" -j ACCEPT || true
  fi
}

start_and_verify() {
  blue "[10/12] Verifying config and starting services..."
  "${XRAY_BIN}" run -test -config "${XRAY_CFG}"
  nginx -t

  systemctl restart nginx
  systemctl enable nginx >/dev/null 2>&1 || true

  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1 || true
  systemctl restart "${SERVICE_NAME}"
  sleep 2

  if ! systemctl is-active --quiet "${SERVICE_NAME}"; then
    red "Xray failed to start"
    journalctl -u "${SERVICE_NAME}" -n 80 --no-pager
    exit 1
  fi
  if ! systemctl is-active --quiet nginx; then
    red "Nginx failed to start"
    journalctl -u nginx -n 80 --no-pager
    exit 1
  fi
  green "Xray + Nginx are running."
}

show_summary() {
  blue "[11/12] Generating connection info..."
  local vmess_json
  vmess_json=$(cat <<EOF
{
  "v": "2",
  "ps": "vmess-${SERVER_HOST}",
  "add": "${SERVER_HOST}",
  "port": "${REALITY_PORT}",
  "id": "${UUID}",
  "aid": "0",
  "net": "ws",
  "type": "none",
  "host": "${SERVER_HOST}",
  "path": "${VMESS_WS_PATH}",
  "tls": "tls"
}
EOF
)

  local vless_uri
  vless_uri="vless://${UUID}@${SERVER_HOST}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI_MASK}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${REALITY_SHORT_ID}&type=tcp#reality-${SERVER_HOST}"

  echo -e "\n\033[32m=========================================="
  echo "VMess + Reality + Nginx Installed"
  echo "Version: ${SCRIPT_VERSION}"
  echo "==========================================\033[0m"
  echo "Server Host       : ${SERVER_HOST}"
  echo "Reality Port      : ${REALITY_PORT}"
  echo "VMess WS Path     : ${VMESS_WS_PATH}"
  echo "Website Root      : ${WEB_ROOT}"
  echo "Cert Mode         : ${CERT_MODE}"
  echo "Reality SNI Mask  : ${SNI_MASK}"
  echo "------------------------------------------"
  echo "UUID              : ${UUID}"
  echo "Reality PublicKey : ${REALITY_PUBLIC_KEY}"
  echo "Reality ShortID   : ${REALITY_SHORT_ID}"
  echo "------------------------------------------"
  echo "VLESS-Reality URI:"
  echo "${vless_uri}"
  echo "------------------------------------------"
  echo "VMess JSON:"
  echo "${vmess_json}"
  echo "------------------------------------------"
  echo "Browser test: https://${SERVER_HOST}:${REALITY_PORT}"
}

run_self_test() {
  blue "[Self-Test] Running local config generation checks..."
  SELF_TEST_TMP="$(mktemp -d)"
  trap 'rm -rf "${SELF_TEST_TMP}"' EXIT

  WEB_ROOT="${SELF_TEST_TMP}/web"
  NGINX_SITE="${SELF_TEST_TMP}/vmess_reality.conf"
  XRAY_CFG="${SELF_TEST_TMP}/config.json"
  XRAY_DIR="${SELF_TEST_TMP}"
  CERT_KEY="${SELF_TEST_TMP}/nginx.key"
  CERT_CRT="${SELF_TEST_TMP}/nginx.crt"

  SERVER_HOST="example.com"
  REALITY_PORT="443"
  VMESS_WS_PATH="/vmess"
  SNI_MASK="www.microsoft.com"
  UUID="11111111-1111-4111-8111-111111111111"
  REALITY_PRIVATE_KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  REALITY_PUBLIC_KEY="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
  REALITY_SHORT_ID="1234abcd5678ef90"

  mkdir -p "${WEB_ROOT}"
  echo "dummy-key" > "${CERT_KEY}"
  echo "dummy-crt" > "${CERT_CRT}"

  deploy_nova_template
  write_nginx_site
  write_xray_config

  [[ -s "${WEB_ROOT}/index.html" ]] && green "[PASS] Website template generated" || { red "[FAIL] Website template missing"; exit 1; }
  [[ -s "${NGINX_SITE}" ]] && green "[PASS] Nginx config generated" || { red "[FAIL] Nginx config missing"; exit 1; }
  [[ -s "${XRAY_CFG}" ]] && green "[PASS] Xray config generated" || { red "[FAIL] Xray config missing"; exit 1; }

  assert_file_contains "${NGINX_SITE}" "listen 127.0.0.1:${NGINX_TLS_LOCAL_PORT} ssl" "Nginx local TLS listener exists"
  assert_file_contains "${NGINX_SITE}" "ssl_certificate" "Nginx cert path set"
  assert_file_contains "${XRAY_CFG}" "\"security\": \"reality\"" "Xray Reality inbound exists"
  assert_file_contains "${XRAY_CFG}" "\"fallbacks\"" "Xray fallback configured"
  assert_file_contains "${XRAY_CFG}" "\"dest\": \"127.0.0.1:${NGINX_TLS_LOCAL_PORT}\"" "Fallback to Nginx TLS is set"
  assert_file_contains "${XRAY_CFG}" "\"path\": \"${VMESS_WS_PATH}\"" "Fallback VMess path is set"

  if command_exists jq; then
    jq empty "${XRAY_CFG}" >/dev/null
    green "[PASS] Xray JSON syntax valid"
  else
    yellow "[WARN] jq not found, skipped JSON syntax check"
  fi

  green "Self-test completed successfully."
}

run_install() {
  detect_os
  install_dependencies
  setup_website
  read_install_inputs
  install_xray
  generate_runtime_values
  handle_certs
  write_nginx_site
  write_xray_config
  open_firewall_ports
  start_and_verify
  show_summary
}

run_uninstall() {
  blue "[Uninstall] Stopping and removing services..."
  systemctl stop "${SERVICE_NAME}" nginx 2>/dev/null || true
  rm -f "${XRAY_CFG}" "${NGINX_SITE}"
  rm -rf "${WEB_ROOT}" 2>/dev/null || true
  green "Uninstall completed."
}

main() {
  if [[ "$#" -gt 0 ]]; then
    case "$1" in
      --install) ACTION="install" ;;
      --uninstall) ACTION="uninstall" ;;
      --self-test) ACTION="self-test" ;;
      *) red "Unknown arg"; exit 1 ;;
    esac
  else
    echo "1) Install (VMess + Reality + Nginx)  2) Uninstall  3) Self-Test"
    read -rp "Choose: " choice
    case "${choice}" in
      1) ACTION="install" ;;
      2) ACTION="uninstall" ;;
      3) ACTION="self-test" ;;
      *) red "Invalid choice"; exit 1 ;;
    esac
  fi

  case "${ACTION}" in
    install)
      require_root
      run_install
      ;;
    uninstall)
      require_root
      run_uninstall
      ;;
    self-test)
      run_self_test
      ;;
  esac
}

main "$@"
