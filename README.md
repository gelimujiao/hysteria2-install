# hysteria2-install

本仓库包含两个一键部署脚本：

- `hy2-install.sh`：`Hysteria2 + Nginx` 伪装站
- `vmess_reallity.sh`：`VMess + VLESS-Reality + Nginx`（443 同端口分流）

支持系统：`Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora`  
运行权限：`root`

---

## 1. 快速开始

```bash
git clone https://github.com/gelimujiao/hysteria2-install.git
cd hysteria2-install
chmod +x hy2-install.sh vmess_reallity.sh
```

---

## 2. 脚本一：hy2-install.sh

### 功能

- 自动安装 Hysteria2 与 Nginx
- 支持网页模板、在线 HTML、自定义 URL、本地网页导入
- 域名优先 ACME 证书，失败回退自签
- 自动配置防火墙与 systemd
- 输出 `hy2://` 连接 URI 与 Clash 配置

### 安装

```bash
sudo ./hy2-install.sh
```

### 卸载

```bash
sudo ./hy2-install.sh --uninstall
```

---

## 3. 脚本二：vmess_reallity.sh

### 功能

- 自动安装 Xray 与 Nginx
- 支持网页模板、在线 HTML、自定义 URL、本地网页导入
- `443` 同端口分流（核心）：
  - `VLESS + Reality` 监听公网 `443`（或你自定义端口）
  - 普通浏览器 HTTPS 请求通过 fallback 回落到 Nginx 网页
  - `VMess + WS` 通过 fallback 的路径（默认 `/vmess`）转发到本地 `127.0.0.1:10000`

### 证书逻辑（已与 hy2 脚本对齐）

- 输入域名时：先申请 ACME
- ACME 失败时：自动探测公网 IP，切换为 IP 并生成自签证书
- 输入 IP 时：直接使用自签证书

### 安装

```bash
sudo ./vmess_reallity.sh
```

### 卸载

```bash
sudo ./vmess_reallity.sh --uninstall
```

### 本地自检（不改系统）

```bash
./vmess_reallity.sh --self-test
```

说明：`--self-test` 不需要 root，会在临时目录生成并校验 Nginx/Xray 配置。

---

## 4. 端口说明

- `hy2-install.sh`
  - `UDP 443`：Hysteria2
  - `TCP 80`：Nginx

- `vmess_reallity.sh`
  - `TCP 80`：HTTP 跳转到 HTTPS
  - `TCP 443`：Xray Reality 入站（并对普通 HTTPS/WS 做 fallback 分流）

请在安全组和防火墙同时放行端口。

---

## 5. 常见问题

- 报错 `Run as root`：请用 `sudo` 或 root 运行安装/卸载。
- 域名 ACME 失败：先检查 DNS 解析，再重试。
- 客户端连接失败：检查端口放行、域名/IP 是否正确、参数是否完整复制。

---

## 6. 免责声明

本项目仅用于网络技术学习与研究，请在遵守当地法律法规的前提下使用。  
使用本项目造成的后果由使用者自行承担。

