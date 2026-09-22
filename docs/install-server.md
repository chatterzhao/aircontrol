# 安装执行端

执行端是一个常驻后台的程序，装在你**要指挥的那台电脑**上
（本地机器、家里/公司的机器，或者租的云服务器都行）。

---

## 前置要求

| 要求 | 说明 |
|---|---|
| **Java 17 或更高** | 终端里跑 `java -version` 能出版本号就行 |
| **tmux**（可选，强烈建议） | 有它才能在断线后保住会话。**没有的话执行端会当场问你要不要帮你装**（答 y 就行） |

```bash
# 检查
java -version      # 要 17+
tmux -V            # 可选

# 想自己装（执行端也会问，答 y 它替你装）
brew install tmux          # macOS
sudo apt install tmux      # Debian/Ubuntu
sudo dnf install tmux      # Fedora/RHEL
```

> **装 tmux 这件事不用你操心**：执行端启动时如果发现没有 tmux，会检测出你机器上的
> 包管理器并问一句"要我现在帮你装吗"。答 `y` 它就跑（macOS 走 Homebrew，
> 不需要管理员密码；Linux 上要 `sudo`，会问密码）。答 `n` 或者干脆没人应答
> （比如后台/开机自启跑的），它就把命令打出来让你自己决定，**绝不自作主张**。
>
> 没有 tmux 也能用：终端照常开，只是**断线后不保留现场**，而且**新建/切换/重开
> 会话用不了**。另外手机上看"实时画面"那个功能依赖 tmux 的屏幕缓冲，
> **在 Windows 上不可用** —— 看终端请用终端模式（那条走原始字节投屏，不依赖 tmux）。

---

## 下载

到 [Releases](../../releases/latest) 页面，按你的系统下载对应文件：

| 系统 | 下载 |
|---|---|
| macOS（Apple 芯片） | `aircontrol-daemon-macos-min11-arm64-<版本>.zip` |
| macOS（Intel） | `aircontrol-daemon-macos-min11-x64-<版本>.zip` |
| Windows 10 及以上 | `aircontrol-daemon-windows-x64-<版本>.zip` |
| Linux (x64) | `aircontrol-daemon-linux-x64-<版本>.zip` |

> 名字里的 **`min11` 是能运行的最低 macOS 版本**（11 = Big Sur）。写进文件名
> 是因为以前不写，用户在旧系统上装完跑不起来、只以为"包坏了"——
> 对着文件名就应该能判断自己能不能装。

每个 Release 都带一个 `SHA-256SUMS` 文件。**建议校验一下**你下到的东西没被掉包：

```bash
# macOS / Linux
shasum -a 256 -c SHA-256SUMS

# Windows (PowerShell)
Get-FileHash .\aircontrol-daemon-windows-x64-<版本>.zip -Algorithm SHA256
# 把结果跟 SHA-256SUMS 里那一行对一下
```

---

## 解压并启动

**macOS / Linux**

```bash
unzip aircontrol-daemon-<你的系统>-<版本>.zip -d aircontrol
cd aircontrol/daemon        # ⚠️ 包里有层 daemon/ 目录，别少这一层
./bin/daemon --ws-port 8080 --pin 1234 --session aircontrol
```

**Windows（PowerShell）**

```powershell
Expand-Archive aircontrol-daemon-windows-x64-<版本>.zip -DestinationPath aircontrol
cd aircontrol\daemon        # ⚠️ 包里有层 daemon\ 目录
.\bin\daemon.bat --ws-port 8080 --pin 1234 --session aircontrol
```

> **Windows 上要放行防火墙**，否则手机连不进来（而且现象是"连不上"，不会提示原因）。
> 用管理员 PowerShell 跑一次即可（只需一次）：
>
> ```powershell
> netsh advfirewall firewall add rule name="AirControl 8080" dir=in action=allow protocol=TCP localport=8080
> ```
>
> 不想用了就删掉：把 `add` 换成 `delete`，其余参数一样。
>
> 另外 Windows 上没有 tmux，执行端会自动降级（终端照常开，只是断线不保现场）。

> - `--pin` 换成你自己的，**别用示例里的 1234**
> - `--ws-port` 默认 8080，被占用就换一个
> - `--session` 是会话名，用来跟机器上已有的 tmux 会话区分开（Windows 上没有 tmux，这一项不起作用）

启动成功后会打印一个二维码和一条连接串：

```
[daemon] 手机扫码即连：
<二维码>
[daemon] aircontrol://connect?host=100.x.x.x&port=8080#pin=1234
```

**这条串就是全部配置**——照着 [安装 App](install-app.md) 把它填进手机就行。

---

## 网络：二选一

### 方式 A：Tailscale（推荐）

两端都装 [Tailscale](https://tailscale.com/)，登同一个账号。

- ✅ 手机**用流量也能连**，不要求同一个 Wi-Fi
- ✅ 换网络后**地址不变**
- ✅ 链路有 **WireGuard 加密**

装好 Tailscale 后，执行端打印的连接串里**已经是 Tailscale 地址**，直接用。

> Android 上记得把 Tailscale 的电池优化关掉：设置 → 应用 → Tailscale → 电池 → **不限制**。
> 否则系统会在后台把它杀掉。

### 方式 B：局域网

手机和电脑在**同一个 Wi-Fi 或热点**下。

查电脑的内网地址：

```bash
ipconfig getifaddr en0        # macOS
ipconfig                      # Windows（看 IPv4 地址）
hostname -I                   # Linux
```

然后在手机 App 里把连接串里的地址换成这个内网地址。

> ⚠️ 换网络后内网地址会变，要重新填。

---

## 更新

**执行端不做自动更新**（它有系统权限，自动替换二进制风险太高）。手动更新：

```bash
# 1. 停掉正在跑的执行端（Ctrl-C）
# 2. 下载新版本，解压覆盖
# 3. 用同样的参数重新启动
```

会话不会丢——它们跑在 tmux 里，重新 attach 就回来了。
（**Windows 上没有 tmux**，所以那边更新会丢掉正在跑的东西，先把手头的活儿存好。）

App 里会提示执行端是否有新版本。

---

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `Unable to locate a Java Runtime` | 没装 Java 17+，或没配好 `JAVA_HOME` |
| 手机上连不上 | 先确认两端网络互通：Tailscale 里对方是不是在线；或局域网里能不能 ping 通 |
| 手机连上了但屏幕是黑的 | macOS 需要开**屏幕录制权限**：系统设置 → 隐私与安全性 → 屏幕录制 |
| 断线后会话丢了 | 大概率是没装 tmux，走了降级模式 |
| 端口被占用 | 换一个 `--ws-port`，手机端端口跟着改 |
