# AirControl 执行端安装说明书

> **这份文档是给 AI 助手读的，不是给人读的。**
>
> 用法：把这份文件（或它的链接）交给你的 AI 助手——Claude Code、Codex、Cursor 都行——
> 跟它说「按这个装」。它会自己判断系统、下载、校验、装好、把配对信息拿给你。

---

## 你要做什么（给 AI）

在这台电脑上安装 **AirControl 执行端**（一个后台程序）。

装好之后，用户就能用手机连上这台电脑，指挥电脑上的 AI 干活。
**你只需要把它装好并启动，然后把配对信息告诉用户。不要改用户的任何已有配置。**

---

## 第 0 步：先问清楚三件事

在动手之前，跟用户确认：

1. **确定要在【这台】电脑上装吗？** —— 执行端要长期开着，最好是有 AI 在那跑的那台
2. **这台电脑有没有 Java 17+？** —— 用 `java -version` 看一眼即可，**但不用为它停下来**：
   - **Linux**：不用管。第 1 步的 `install.sh` 会**自己下载一份便携 JRE** 放到安装目录里，
     **完全不动系统**。你不需要装 JDK，也不要 `apt install`。
   - **macOS**：如果没装，`install.sh` 会告诉你 `brew install openjdk@17`。
     注意 macOS 上 `/usr/bin/java` 是个 **stub**——它存在不代表装了 JDK，
     跑起来只会说 "Unable to locate a Java Runtime."
   - **已经装了但版本低于 17** → 让用户处理，别自己升级他的 Java。
3. **用户是想让手机连局域网，还是走 Tailscale？** —— 影响你用哪个地址。**不确定就先按局域网来**

---

## 第 1 步：装 AirControl 执行端（用官方脚本，别自己拼命令）

```bash
curl -fsSL https://gitee.com/zhaoquan/aircontrol/raw/main/install.sh | bash
```

**这个脚本已经处理好了下面这些——自己重写一遍只会把踩过的坑再踩一次**：

- 按平台和架构选对包（Windows 会用 Linux 包，见下）
- **没有 Java 就自动下载便携 JRE**（Linux），完全不动系统
- 下载**先 Gitee 再 GitHub**——实测 GitHub 的 Release 下载会 302 跳到
  `release-assets.githubusercontent.com`，国内**连得上、下不动**
- **SHA-256 校验**（侧载没有签名背书，这是唯一的来源验证）
- 解压到位、打印配对信息和二维码

**它跑完就装好了。** 如果它失败，先把它打印的原始错误贴给用户，
**不要自己另起一套下载流程**——那样出了问题是两套逻辑混在一起，更难查。

> ### 万一必须手动装（脚本彻底跑不通时）
>
> **先 Gitee 再 GitHub**，版本号问 `latest.json`（别猜）：
>
> ```bash
> VERSION=$(curl -fsSL https://gitee.com/zhaoquan/aircontrol/raw/main/latest.json \
>   | sed -n 's/.*"daemon": *"\([^"]*\)".*/\1/p')
> ```
>
> 按平台选文件：
>
> | 系统 | 架构 | 文件 |
> |---|---|---|
> | macOS | arm64 | `aircontrol-daemon-macos-min11-arm64-<版本>.zip` |
> | Linux | x86_64 | `aircontrol-daemon-linux-x64-<版本>.zip` |
> | **Windows** | 任意 | **下 Linux 包**——同一个 zip 里同时有 `bin/daemon` 和 `bin/daemon.bat` |
> | macOS | x86_64（Intel） | ⚠️ **目前没有 Intel 包**，停下来告诉用户 |
>
> 下载后**必须校验**（这一步不能跳）：
>
> ```bash
> curl -fL -o SHA-256SUMS "<release>/SHA-256SUMS"
> shasum -a 256 -c SHA-256SUMS --ignore-missing   # macOS
> sha256sum  -c SHA-256SUMS --ignore-missing      # Linux
> ```
>
> 校验不过就删掉重下，**绝不要继续安装**。
>
> 解压后放到用户级目录（**不要 sudo、不要系统目录**）：
> macOS `~/Applications/aircontrol-daemon/`，
> Linux `~/.local/opt/aircontrol-daemon/`，
> Windows `%LOCALAPPDATA%\aircontrol-daemon\`。
>
> **手动装的话，Java 得你自己确认**——`java -version` 要 17+，没有就让用户装，
> 别乱装 JDK。

## 第 5.5 步：装辅助工具（不装的话，装完也不太好用）

**AirControl 自己只管「连起来」。真正干活的是别的程序。** 所以下面这些要一起处理好：

| 工具 | 干什么 | 必需？ |
|---|---|---|
| **Java 17+** | 执行端靠它运行 | **必需**（第 0 步已确认） |
| **tmux** | 会话管理——多开、断了能接回来 | **强烈建议**（没有会降级） |
| **Tailscale** | 手机和电脑不在同一网络时也能连 | 可选 |
| **AI CLI** | **真正干活的那个** | **必需**（否则连上了也没用） |

### tmux

```bash
# macOS
brew install tmux
# Debian / Ubuntu
apt install tmux
# Fedora / RHEL
dnf install tmux
```

**不要 `sudo`** —— 装不上就告诉用户，让他自己决定。

装完验证：`tmux -V` 能打印版本就行。

### Tailscale（只在用户需要"手机在外面也能连"时装）

- **官方下载页**：<https://tailscale.com/download>
- 装完还要 `tailscale up` 让用户**自己登录**（这一步必须他本人做，别代劳）
- 登录后 `tailscale ip -4` 拿到 `100.x.x.x`，**这就是手机该填的地址**
- 手机端也要装 Tailscale 并登同一个账号

**如果用户只是想在同一 Wi-Fi 下用，跳过这一步。**

### AI CLI（最关键的一步）

**用哪个由用户决定，不要替他选。**

⚠️ **不要照抄任何写死的安装命令**——各平台不同、版本一直在变、包名也可能改。
**去它自己的官方文档确认当前命令**：

| CLI | 去哪看 |
|---|---|
| **Claude Code** | <https://docs.anthropic.com/en/docs/claude-code> |
| **OpenAI Codex CLI** | <https://github.com/openai/codex> |
| **OpenCode** | <https://opencode.ai/install> |
| **DeepSeek / dsh / 其他** | 问用户是从哪拿到的，去它的官方页 |

**通用兜底**：上面这几个大多有 npm 包，所以 `npm i -g <包名>` 通常能装——
**但要先确认包名，别猜**。没有 npm 就用官方给的安装脚本。

**装完必须验证**：跑一下 `<命令> --version`，能打印版本才算装上。

### 如果用户的 CLI 需要 API Key

**Key 必须由用户自己提供，你不能代替他决定用哪个服务、哪个模型。**

拿到之后：

- **写进这个 CLI 自己的配置**（每个 CLI 的配置方式不同，查它自己的文档）
- **不要写进 AirControl 的任何文件**
- **不要写进日志、不要回显到终端上**

---

## 第 6 步：启动

**前台先跑一次**，确认能起来（别急着做成后台服务）：

`install.sh` 跑完会告诉你它装到哪了、怎么起。手动装的话是：

```bash
# macOS / Linux
./daemon/bin/daemon --ws-port 8080 --session aircontrol
# Windows
daemon\bin\daemon.bat --ws-port 8080 --session aircontrol
```

**正常情况下它会打印**（看这个判断成没成）：

- 一个**二维码**
- 一条**连接串**，形如 `aircontrol://connect?host=<地址>&port=8080#pin=<PIN>`
- **连接码（PIN）**——4 位数字
- 本机地址列表（局域网 / Tailscale）

**如果它说「没装 tmux」**：终端会话管理会降级。问用户要不要装
（macOS `brew install tmux`，Linux `apt install tmux` / `dnf install tmux`），**不要自己 sudo 装**。

---

## 第 7 步：告诉用户什么

跑起来之后，**把这四样东西清楚地给用户**：

1. **连接串**（那一整条 `aircontrol://...`）—— 手机 App 里粘贴它就能连
2. **连接码 PIN** —— 手填时需要；**提醒他别截图外发**
3. **地址** —— 用哪个连：同一 Wi-Fi 用局域网地址；不在同一网络用 Tailscale 的 `100.x.x.x`
4. **怎么停**：在前台按 `Ctrl-C`；想让它常驻，再谈后台服务

**明确提醒两条**（这是安全相关的，必须说）：

- **连接码别外发**（截图、贴群、发聊天都算）
- **链路是明文 `ws://`**：请只在 **Tailscale 或可信局域网**里用，纯公网直连当前版本不建议

---

## 第 8 步：装手机端（可选）

如果用户还要装手机 App：

```bash
# 从同一个 Release 下载
aircontrol-app-android-min7-<版本>.apk
```

把这**一个文件**交给用户，让他自己传到手机上安装（需要允许"安装未知应用"）。

**不要**尝试用 adb 直接装到用户手机上——除非他明确要求，而且设备已经连上。

---

## 硬性约束（这几条不能违反）

| 不能做 | 为什么 |
|---|---|
| ❌ **改用户的 `.zshrc` / `.bashrc` / 任何已有配置** | 改坏了用户的终端就打不开了 |
| ❌ **用 `sudo` 装东西** | 用户没授权；而且这个程序不需要 root |
| ❌ **覆盖 `~/.claude/`、`~/.codex/` 等已有配置目录** | 那是用户自己的配置，不是你的 |
| ❌ **跳过校验和** | 校验和是唯一的来源验证 |
| ❌ **把连接码写进任何文件、日志、聊天** | 它是连接凭证 |
| ❌ **装到系统目录** | 用户级目录就够，卸载也干净 |
| ❌ **替用户选 AI CLI / 模型 / 服务商** | 那是用户的决定，你只负责装 |
| ❌ **把 API Key 回显到终端或写进日志** | 密钥只在它自己的配置文件里 |

---

## 装完之后能干什么

执行端跑起来后，用户在手机上可以：

- 看这台电脑的**终端**（真的终端，`vim`/`htop`/`claude` 都能用）
- 看这台电脑的**屏幕**
- 让电脑上的 AI 干活，**危险操作会推到手机上等他批准**
- 同时开多个会话，互不影响

**底下跑什么 AI、用哪个模型、API Key 配在哪——都由用户决定，不归你管。**

---

## 出问题了怎么办

| 现象 | 先查什么 |
|---|---|
| 下载卡住 / 0 字节 | 换源（Gitee ↔ GitHub）；确认网络 |
| 校验不过 | 删掉重下；两次都不过就停下报告 |
| 起不来，提示 Java | `java -version`，要 17+ |
| 起来了但手机连不上 | 两端是否同一网络；是否用了 Tailscale；防火墙是否放行 8080 |
| Windows 上第一次跑，桌面上弹了防火墙询问 | 点「允许访问」。**不点的话不只是连不上**：那个弹窗占着前台，手机上的点击/打字会落到它身上，看起来像"操作没反应" |
| 连上就断 | 看执行端窗口打印的错误；确认中间没有代理 |
| 屏幕功能不可用 | macOS 要授权「屏幕录制」；Linux 服务器没有图形界面 |

**卡住就把原始报错贴给用户，不要自己猜着改配置。**
