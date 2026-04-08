这是一个工业级的 Hysteria 2 一键部署脚本。它不仅安装协议本身，还通过集成 Nginx 构建了一套完整的**流量伪装体系**，旨在提供最高级别的隐蔽性和部署便捷性。

## 🌟 核心特性

### 🛡️ 极致伪装 (Advanced Masquerading)

- **Nginx 深度集成**：自动安装并配置 Nginx，将非法请求转发至真实的 Web 页面。
- **流量分流架构**：
  - `UDP 443` $\rightarrow$ Hysteria 2 (高速加密隧道)
  - `TCP 443/80` $\rightarrow$ Nginx (伪装成正常的 HTTPS/HTTP 网站)
- **多样化模板**：内置企业级响应式 HTML 模板，支持远程 URL 导入或本地目录同步。
  
  ### 🔑 智能证书管理 (Smart Certs)
- **ACME 自动化**：输入域名时自动通过 `acme.sh` 申请受信任的正规证书（无需手动配置 API）。
- **智能回退机制**：若域名申请失败（如 DNS 未生效），脚本将**自动探测服务器公网 IP** $\rightarrow$ 切换为 IP 模式 $\rightarrow$ 生成自签名证书，确保部署不中断。
- **自适应配置**：根据证书模式自动生成 `insecure=0` (正规) 或 `insecure=1` (自签) 的连接 URI。
  
  ### 🛠️ 工业级部署优化 (Industrial Grade)
- **端口强制清理**：执行前自动扫描 80/443 端口，强制终止冲突进程（如 Apache, 旧版 Nginx），确保一次启动成功。
- **全自动防火墙**：智能识别并配置 `ufw` / `firewall-cmd` / `iptables`。
- **系统级管理**：自动创建 Systemd 服务，支持开机自启与自动崩溃重启。

---

## 🚀 快速开始

### 1. 环境要求

- **操作系统**：Ubuntu / Debian / CentOS / Rocky Linux / AlmaLinux / Fedora
- **权限**：必须以 `root` 用户运行
- **端口**：确保服务商开放了 `UDP 443` 和 `TCP 80/443` ### 2. 一键安装 ```bash
  
  # 下载脚本
  
  wget -O hy2-install.sh https://github.com/你的用户名/你的仓库名/raw/main/hy2-install.sh
  
  # 赋予执行权限
  
  chmod +x hy2-install.sh
  
  # 运行脚本
  
  sudo ./hy2-install.sh
- ### 3. 配置步骤
  
  运行脚本后，按照交互提示操作：
  1. **选择模板**：建议选择 1) NovaStream 或上传你自己的 HTML 目录。
  
  2. **输入 Host**：输入你的 **域名** (推荐) 或 **服务器 IP**。
  
  3. **设置密码**：直接回车将生成随机强密码。
  
  4. **等待部署**：脚本将自动完成 清理端口 -> 安装依赖 -> 申请证书 -> 配置服务。

## 📐 技术架构

```
graph TD
    User((用户/客户端)) -->|UDP 443| HY2[Hysteria 2 Server]
    User -->|TCP 443/80| HY2
    HY2 -->|合法协议流量| Tunnel(加密隧道 $\rightarrow$ 目标网站)
    HY2 -->|非法/探测流量| Nginx[Nginx Web Server]
    Nginx -->|响应| FakePage[伪装 HTML 网页]
```

## 客户端配置

安装完成后，脚本将输出一个 hy2:// 开头的 URI。

### 推荐客户端

- **Windows/macOS**: [v2rayN](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2F2dust%2Fv2rayN), [Nekoray](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FMatsuriDayo%2Fnekoray)

- **Android**: [Nekobox](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FMatsuriDayo%2FNekoBoxForAndroid)

- **iOS**: [Shadowrocket](https://www.google.com/url?sa=E&q=https%3A%2F%2Fapps.apple.com%2Fus%2Fapp%2Fshadowrocket%2Fid932747118)

- **通用**: [Clash Meta / Mihomo](https://www.google.com/url?sa=E&q=https%3A%2F%2Fgithub.com%2FMetaCubeX%2Fmihomo) (需转换配置文件)



## 卸载服务

若需完全删除 Hysteria 2 及 Nginx 伪装环境，运行：

codeBash

```
sudo ./hy2-install.sh --uninstall
```

## ⚠️ 免责声明

本工具仅用于学习研究网络协议及提升网络质量。请在遵守当地法律法规的前提下使用。作者不对任何因使用本工具而导致的账户封禁或法律问题负责。



如果你觉得此脚本，不错，请我喝一杯咖啡吧！！！

<img src="file:///C:/Users/Administrator/AppData/Roaming/marktext/images/2026-04-08-12-26-42-35cb34c265e0eef9049fd154068626b5.jpg" title="" alt="" width="337">
