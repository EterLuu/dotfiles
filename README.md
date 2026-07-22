# 跨平台 dotfiles

这是一套不依赖 GNU Stow、Homebrew 或其他包管理器的开发环境配置。一个 Bash
命令负责部署，实际内容由 Git 同步；适用于 macOS、Linux、WSL，以及 Git
Bash/MSYS2 下的原生 Windows。

它解决三类数据，并刻意不把它们混在一起：

- **共享配置**：Zsh、Bash、Vim、Git、tmux、SSH 的安全默认值，提交到本仓库；
- **平台/主机配置**：放在 `profiles/<platform>` 或
  `profiles/hosts/<hostname>`，只保存可以公开同步的差异；
- **设备私有配置**：软件绝对路径、Git 身份、SSH 主机与代理等，保存在
  `~/.config/dotfiles`、`~/.config/git/local.conf` 和
  `~/.ssh/config.local`，不进入仓库。

```text
Git 仓库（可同步）
├── .dotfiles-manifest       文件部署清单
├── bin/dotfiles             管理命令
├── dotfiles/                通用配置
├── profiles/                macOS/Linux/WSL/Windows/主机差异
└── examples/                首次安装时复制的本地配置模板
          │ install
          ▼
用户 HOME
├── ~/.zshrc 等              符号链接，Windows 默认是普通副本
├── ~/.config/dotfiles/      设备路径、生成环境和本地覆盖
├── ~/.config/git/local.conf Git 身份等私有信息
└── ~/.ssh/config.local      私有主机、密钥路径和跳板机
```

## 快速开始

把仓库克隆到任意位置，不要求固定为 `~/.dotfiles`：

```bash
git clone <your-dotfiles-repository> ~/.dotfiles
cd ~/.dotfiles
./bin/dotfiles install --dry-run
./bin/dotfiles install
```

重新启动登录 Shell，或执行：

```bash
exec "${SHELL:-zsh}" -l
```

安装器会先把冲突文件移到
`~/.local/state/dotfiles/backups/<时间>-<进程号>/`，再部署新配置。重复执行
`dotfiles install` 是幂等的。安装后命令位于 `~/.local/bin/dotfiles`，而该目录
也会加入 `PATH`。

建议先编辑以下仅存在于本机的文件：

```text
~/.config/git/local.conf       Git 姓名、邮箱和签名密钥
~/.ssh/config.local            SSH 主机、User、IdentityFile、ProxyJump
~/.config/dotfiles/local.zsh   仅 Zsh 使用的别名或变量
~/.config/dotfiles/local.bash  仅 Bash 使用的别名或变量
~/.config/dotfiles/local.profile  两种 Shell 共用的设备环境
```

## 命令

```bash
dotfiles install                     # 安装或修复配置
dotfiles install --dry-run           # 只显示动作
dotfiles status                      # 检查缺失、错误链接或副本漂移
dotfiles doctor                      # 检查依赖、平台和疑似私钥
dotfiles update                      # 事务式 fast-forward 并重新安装
dotfiles save -m "update vim"        # 收集副本、创建本地 commit 并重新安装
dotfiles sync -m "sync configs"      # fetch、提交、rebase、部署、push
dotfiles recover                     # 恢复中断或远端结果不明的事务
dotfiles uninstall                   # 只删除未被修改的托管文件
dotfiles root                        # 显示当前仓库位置
dotfiles config list                 # 显示设备设置
```

`uninstall` 不删除设备本地配置和备份。复制模式下，如果 HOME 中的副本被修改，
它也会保留该文件并提示，避免误删。

`commit` 是 `save` 的别名，`publish` 是 `sync` 的别名，`save --push` 也等价于
`sync`。提交消息既可以写成 `-m "message"`，也可以直接作为最后一个位置参数；
省略时会生成包含时间的消息。

### 链接与复制模式

macOS、Linux 和 WSL 默认使用绝对符号链接；原生 Windows 的 Git Bash/MSYS2
默认使用复制，避免 Windows 开发者模式、权限和 Git symlink 配置造成的不一致。
可以按设备永久覆盖：

```bash
dotfiles config set install-mode link   # auto、link 或 copy
dotfiles install
```

也可用 `--mode copy` 做单次覆盖，但后续命令也必须显式使用相同模式：

```bash
dotfiles install --mode copy
# 编辑 HOME 中的副本
dotfiles save --mode copy -m "update copied config"
```

长期使用复制模式时，建议通过 `config set install-mode copy` 持久保存。复制模式
既可以在仓库里编辑源文件，也可以直接编辑 HOME 副本后用 `save` 安全回收；工具
保存了上次部署基线，能区分“仓库有更新”“HOME 有更新”和“两边同时修改”的
冲突。`status` 会发现 HOME 副本与仓库的差异。Windows 上若需完整 Unix 行为，
优先选择 WSL。此仓库不自动管理 PowerShell Profile。

## Conda、Miniconda 与设备路径

安装时会依次检查当前 `CONDA_EXE`、`PATH`，以及常见的 Miniconda、Anaconda、
Miniforge 和 Mambaforge 目录。检测结果写入本机的
`~/.config/dotfiles/generated.sh`，不会提交到 Git。Conda 不会永久占据 PATH，
而是在第一次运行 `conda` 时加载对应 Shell hook，减少启动时间和路径污染。

路径不同或自动探测失败时，在每台设备执行一次：

```bash
dotfiles config set conda-root "$HOME/apps/miniconda3"
```

含空格的路径也受支持。Windows Git Bash 应使用它能识别的路径（例如
`/c/Users/me/miniconda3`）。重装或移动 Conda 后重新设置即可；清除覆盖用：

```bash
dotfiles config unset conda-root
```

其他设备专属 SDK 路径应写入 `local.profile`，不要把绝对路径加入共享的
`.zshrc` 或 `.bashrc`。

## 配置放置教程：一般情况与特殊情况

新增配置前先判断两个问题：它是否可以公开提交，以及它适用于全部平台、某个平台、
某台主机，还是仅当前设备。不要在 `.bashrc`、`.zshrc` 中堆叠大量 `uname`、主机名
和绝对路径判断；本仓库已经把这些边界分开。

### 配置位置速查

| 使用范围 | 推荐文件 | 是否同步 | 适合内容 |
| --- | --- | --- | --- |
| 所有平台、所有 Shell 的环境 | `dotfiles/shell/env.sh` | 是 | `PATH`、`EDITOR`、通用环境变量 |
| 所有平台的交互式 Shell | `dotfiles/shell/interactive.sh` | 是 | alias、函数、按键和交互工具 |
| 某个平台的环境 | `profiles/<平台>/env.sh` | 是 | 平台 PATH、环境变量；不能产生输出或启动后台进程 |
| 某个平台的交互行为 | `profiles/<平台>/shell.sh` | 是 | alias、函数、剪贴板、Agent 桥接等 |
| 某台主机的公开交互配置 | `profiles/hosts/<短主机名>/shell.sh` | 是 | 不含机密的主机别名、工作目录函数 |
| 当前设备的登录环境 | `~/.config/dotfiles/local.profile` | 否 | 私有 SDK 路径、需要由子进程继承的变量 |
| 当前设备的 Bash/Zsh 配置 | `local.bash` / `local.zsh` | 否 | 私有 alias、代理和仅该 Shell 使用的命令 |
| Git 身份 | `~/.config/git/local.conf` | 否 | 姓名、邮箱、签名密钥 |
| SSH 主机 | `~/.ssh/config.local` | 否 | Host、用户名、密钥路径、ProxyJump |

`<平台>` 可以是 `macos`、`linux`、`wsl` 或 `windows`。其中 `windows` 指原生
Git Bash/MSYS2，WSL 会单独识别为 `wsl`，不会加载 `profiles/linux`。

### 实际加载顺序

登录环境的加载顺序是：

```text
generated.sh
→ dotfiles/shell/env.sh
→ profiles/<平台>/env.sh
→ local.profile
```

交互式 Shell 的加载顺序是：

```text
generated.sh
→ dotfiles/shell/env.sh
→ profiles/<平台>/env.sh
→ dotfiles/shell/interactive.sh
→ profiles/<平台>/shell.sh
→ profiles/hosts/<短主机名>/shell.sh
→ local.bash 或 local.zsh
```

因此应遵守以下规则：

- `env.sh` 必须可重复加载，不输出文字、不等待输入、不启动后台进程；
- alias、交互函数和需要启动进程的配置放在 `shell.sh`；
- 本机覆盖最后加载，可以覆盖共享 alias 或变量；
- `local.profile` 只保证由登录 Shell 读取。非登录 Shell 通常继承登录环境；如果某个
  启动器没有继承它，应把设置放入对应的 `local.bash`/`local.zsh`，或从二者共同
  source 一个设备本地脚本。

可以检查当前选择的平台和主机：

```bash
printf 'platform=%s host=%s\n' "$DOTFILES_OS" "$DOTFILES_HOST"
```

如果变量为空或平台不正确，先重新执行 `dotfiles install` 生成当前设备环境。

### 一般情况一：增加平台专属环境变量

例如某个缓存目录只适用于 macOS，应修改 `profiles/macos/env.sh`：

```sh
export TOOL_CACHE_HOME="$HOME/Library/Caches/tool"
```

如果只适用于 Linux，则写入 `profiles/linux/env.sh`；不要在共享 `env.sh` 中再写
`if [ "$(uname)" = ... ]`。平台环境会同时提供给 Bash 和 Zsh，所以语法应兼容两者，
并尽量使用 POSIX Shell 写法。

### 一般情况二：增加平台 alias 或函数

例如某个命令只在 Linux 上存在，应修改 `profiles/linux/shell.sh`：

```sh
if command -v systemctl >/dev/null 2>&1; then
    alias user-services='systemctl --user --type=service'
fi
```

这种配置只在交互式 Shell 中加载，不会污染脚本或 `scp` 等非交互命令。

### 一般情况三：增加主机或设备配置

可以公开、且需要跟随某个主机名同步的交互配置放在：

```text
profiles/hosts/<hostname>/shell.sh
```

这里使用 `hostname` 的第一个点号之前的短名称。不要提交公司内网地址、用户名、
token 或私钥路径；这类设置放入 `local.bash`、`local.zsh`、`local.profile`、
`git/local.conf` 或 `ssh/config.local`。

例如只有当前 Bash 设备需要的工作目录别名：

```sh
# ~/.config/dotfiles/local.bash
alias work='cd /private/device/path/to/workspace'
```

### 一般情况四：增加新的托管文件

要同步一个新的普通配置文件，先在仓库中创建源文件，再加入 manifest：

```text
# .dotfiles-manifest
all|dotfiles/tool/config|.config/tool/config
wsl|dotfiles/tool/wsl.conf|.config/tool/platform.conf
```

然后检查并同步：

```bash
dotfiles install --dry-run
dotfiles install
dotfiles status
dotfiles sync -m "tool: add shared configuration"
```

manifest 只放可公开的普通文件。凭据、设备绝对路径以及运行时生成内容不能作为源文件
加入仓库。

### 特殊情况：WSL 使用 Windows OpenSSH Agent

适用场景是：私钥由 Windows `ssh-agent` 持有，WSL 中的 `ssh`、Git 和开发工具通过
Unix socket 访问 Windows named pipe。所有 WSL 设备都使用这种方式时，共享环境变量
写入 `profiles/wsl/env.sh`：

```sh
# Windows OpenSSH agent bridge socket inside WSL.
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
```

后台桥接只应在交互式 Shell 中启动，因此把以下内容加入
`profiles/wsl/shell.sh`：

```sh
# Bridge WSL SSH clients to the Windows OpenSSH agent.
dotfiles_ssh_agent_status=2
if command -v ssh-add >/dev/null 2>&1; then
    ssh-add -l >/dev/null 2>&1
    dotfiles_ssh_agent_status=$?
fi

# ssh-add: 0=Agent 中有密钥，1=Agent 可用但没有密钥，2=无法连接 Agent。
case "$dotfiles_ssh_agent_status" in
    0|1) ;;
    *)
        if [ -e "$SSH_AUTH_SOCK" ] && [ ! -S "$SSH_AUTH_SOCK" ]; then
            printf 'warning: refusing to replace non-socket path: %s\n' \
                "$SSH_AUTH_SOCK" >&2
        elif command -v socat >/dev/null 2>&1 &&
           command -v setsid >/dev/null 2>&1 &&
           command -v npiperelay.exe >/dev/null 2>&1; then
            mkdir -p "$HOME/.ssh"
            chmod 700 "$HOME/.ssh"
            rm -f "$SSH_AUTH_SOCK"

            setsid socat \
                "UNIX-LISTEN:$SSH_AUTH_SOCK,fork,mode=600" \
                "EXEC:npiperelay.exe -ei -s //./pipe/openssh-ssh-agent,nofork" \
                >/dev/null 2>&1 &

            sleep 0.2
        else
            printf '%s\n' \
                'warning: WSL SSH agent bridge requires socat, setsid and npiperelay.exe' >&2
        fi
        ;;
esac
unset dotfiles_ssh_agent_status
```

不能简单使用 `if ! ssh-add -l`：当 Agent 正常但尚无密钥时，`ssh-add -l` 也可能
返回 `1`；这种情况不应删除 socket 并重复启动 `socat`。

准备条件：

1. Windows 的 **OpenSSH Authentication Agent** 服务已经启动，并设置为按需或
   自动启动；私钥应在 Windows 侧加入 Agent，不要复制进仓库；
2. WSL 已安装 `socat` 和提供 `setsid` 的 util-linux；
3. `npiperelay.exe` 可以从 WSL 的 `PATH` 找到。

可以在管理员 PowerShell 中启用 Windows Agent：

```powershell
Set-Service -Name ssh-agent -StartupType Automatic
Start-Service -Name ssh-agent
Get-Service -Name ssh-agent
```

然后在普通 PowerShell 中把私钥加入 Windows Agent，例如：

```powershell
ssh-add "$env:USERPROFILE\.ssh\id_ed25519"
ssh-add -l
```

私钥文件仍只保存在本机；不要把它复制到 WSL dotfiles 仓库。

如果每台设备上的 `npiperelay.exe` 路径不同，不要把 `/mnt/c/Users/...` 绝对路径写入
共享 profile。可以在该设备的 `~/.local/bin` 创建同名包装脚本，因为此目录已经由
共享环境加入 `PATH`：

```sh
#!/usr/bin/env sh
exec "/mnt/c/Users/<当前用户>/path/to/npiperelay.exe" "$@"
```

保存为 `~/.local/bin/npiperelay.exe` 并执行：

```bash
chmod 700 ~/.local/bin/npiperelay.exe
```

这个包装脚本是设备本地文件，不加入 manifest。如果 Agent 桥接只属于一台 WSL，
则不要修改 `profiles/wsl`；把 `SSH_AUTH_SOCK` 和完整启动逻辑放入该设备的
`~/.config/dotfiles/local.bash`。Zsh 用户对应使用 `local.zsh`；同时使用两种 Shell
时，可以让两者 source 同一个未纳入仓库的设备本地脚本。

提交共享配置并重载 Shell：

```bash
dotfiles sync -m "wsl: bridge Windows OpenSSH agent"
exec "${SHELL:-bash}" -l
```

依次排查：

```bash
printf '%s\n' "$DOTFILES_OS"                  # 应为 wsl
command -v ssh-add socat setsid npiperelay.exe
printf '%s\n' "$SSH_AUTH_SOCK"
ls -l "$SSH_AUTH_SOCK"
ssh-add -l
```

`ssh-add -l` 显示“no identities”说明桥接已经可用，但 Windows Agent 中还没有密钥；
显示“Could not open a connection”才表示 socket 或桥接进程有问题。

## SSH 与机密信息

仓库只同步 SSH 的通用安全/连接行为。以下内容绝不能提交：

- 私钥、证书、恢复码和 access token；
- 内网主机名、用户名或不宜公开的跳板拓扑；
- 带密码的代理 URL。

设备私有 Host 写入 `~/.ssh/config.local`。确实需要在所有设备共享、且可以公开
的 Host 别名可加入 `dotfiles/ssh/shared.conf`。私钥仍留在各设备的 `~/.ssh`，
权限建议为目录 `700`、私钥 `600`。`dotfiles doctor` 会检查仓库里常见的私钥
文件名，但它不能替代提交前审查和 secret scanner。

## 在设备之间同步

推荐的一键方式：

```bash
dotfiles save -m "update shell settings"       # 只创建本地 commit
dotfiles sync -m "update shell settings"       # 完整事务并推送到 upstream
```

`save` 和 `sync` 要求仓库至少已有一个 commit、Git identity 已配置、暂存区为空，
并且未提交修改只能位于 `.dotfiles-manifest`、`README.md`、`bin/`、`dotfiles/`、
`examples/`、`profiles/`、`tests/` 等托管范围内。`sync` 还要求当前分支已有
upstream；首次推送可执行：

```bash
git push -u origin main
```

`sync`（别名 `publish`）按以下事务顺序执行：

1. 检查工作区和 upstream，并在修改本地文件前执行 `git fetch`；
2. 快照仓库托管范围、HOME 托管文件、生成状态、复制模式基线，以及安装可能
   创建或修改的目录状态和权限；
3. 收集 HOME 副本、限定暂存范围、扫描常见私钥/token，然后创建 commit；
4. 在已 fetch 的 upstream 上执行 rebase；
5. 先部署并验证本机配置；
6. 最后 push 单一分支引用，远端确认后删除事务快照。

第 2～6 步中，只要远端尚未接受 commit，任何冲突、Git hook、rebase、部署或
push 拒绝都会自动恢复调用前的 Git HEAD、未提交修改、HOME 文件、复制基线和
受影响目录的权限。事务中新建的空目录会被删除；如果目录内出现了事务之外的新
文件，回退会保留该目录和文件、报告回退不完整并保留快照，不会为追求目录状态而
删除未知数据。

如果自动回退自身没有完全成功，快照会保留在
`~/.local/state/dotfiles/transactions/` 并输出其准确路径。事务目录权限设为 `700`；
成功或完整回退后会自动删除。

同一 HOME 同时只允许一个事务，锁位于
`~/.local/state/dotfiles/transaction.lock`。普通错误以及 `INT`、`TERM`、`HUP`
中断会自动触发回退；`ACTIVE` 或 `IN_DOUBT` 快照存在时，即使锁文件被手动删除，
`install`、`uninstall`、配置写入、`save`、`sync` 和 `update` 等修改命令也会拒绝
启动；`status`、`doctor` 和 `config list` 等只读命令仍可使用。若进程被强制终止而
来不及处理，下一次运行会要求执行 `dotfiles recover`。

事务会在每个稳定阶段记录 Git HEAD、工作区和暂存区、仓库托管内容、HOME 托管
文件、设备生成状态、复制基线及相关目录的校验指纹。`ACTIVE` 恢复只有在当前状态
仍与最后一个完整检查点完全一致时才会自动回退；如果强制终止恰好发生在两个检查点
之间，或之后有人修改了这些状态，工具会保留快照并拒绝覆盖。此时应先检查 Git 与
HOME 差异并手动协调，而不是强制删除快照。事务执行期间仍不要用其他进程同时编辑
托管配置。

远端 push 是分布式事务的提交点。若 push 报错且网络中断导致远端结果无法确认，
工具不会冒险回退，也不会假定推送成功：它保留已提交/已部署的本地状态、事务锁和
标记为 `IN_DOUBT` 的快照，并返回状态码 `2`。网络恢复后执行：

```bash
dotfiles recover
```

`recover` 会先查询远端：若远端包含该 commit，就保留当前本地状态并清理快照；
否则只有在整个受管面仍匹配事务指纹时才恢复事务前状态。之后对 Git、HOME、生成
文件、复制基线或相关目录的修改都会让破坏性回退安全停止。Git hook 或远端服务
触发的外部副作用不属于本地事务，无法由此工具撤销。新版工具会阻止产生多个待恢复
事务；处理旧版本遗留的多个快照时，必须明确指定输出过的路径：

```bash
dotfiles recover ~/.local/state/dotfiles/transactions/<事务目录>
```

复制模式下，如果仓库与 HOME 自上次部署后修改了同一个文件，命令会在 commit
之前停止并完整回退，不会猜测应该覆盖哪一边。机密检查仅覆盖暂存文件中的常见
文件名和内容特征，不能替代提交前审查或专用 secret scanner。

需要逐步检查时仍可手动执行：

在修改配置的设备上：

```bash
cd "$(dotfiles root)"
git status
git add .dotfiles-manifest .gitattributes .gitignore README.md bin dotfiles examples profiles tests
git diff --cached
git commit -m "update shell settings"
git push
```

其他设备执行 `dotfiles update`。该命令先 fetch，再把 fast-forward 与本机安装放在
同一个本地事务中；安装失败会同时恢复原 HEAD、HOME 和设备状态。仓库存在未提交
修改时会在事务开始前停止。fetch 更新的远端跟踪引用以及远端本身不属于本地回退
范围。首次迁移已有 HOME 时，先运行 `--dry-run`；安装器产生备份后，应确认新环境
正常，再自行归档或删除旧备份。

## 扩展配置

`.dotfiles-manifest` 每行格式如下，目标必须相对 `$HOME`。目前可靠支持普通文件；
目录在链接模式可能可用，但复制模式不会递归复制，因此不应加入清单：

```text
平台范围|仓库内源文件|HOME 下目标文件
all|dotfiles/tool/config|.config/tool/config
macos,linux|dotfiles/tool/unix.conf|.toolrc
```

支持的范围是 `all`、`unix`、`macos`、`linux`、`wsl`、`windows`。增加文件后
运行 `dotfiles install` 和 `dotfiles status`。平台公共环境写入
`profiles/<platform>/env.sh`，交互函数/别名写入 `shell.sh`。主机级公共设置可建
`profiles/hosts/<短主机名>/shell.sh`；敏感设置仍应放在 HOME 的本地覆盖文件。

本项目有意不自动安装系统软件或 Vim 插件。包名、管理员权限和公司策略高度依赖
设备，把“配置同步”与“软件安装”分开可以让安装过程可预测，也更容易审计。

## 验证

测试完全使用临时 HOME 和临时 bare Git remote，不接触真实用户配置。覆盖内容包括
成功同步、push 拒绝回退、rebase 冲突回退、`SIGKILL` 后的 `ACTIVE` 恢复与修改
保护、远端结果不确定后的 `recover` 与事务阻塞、`update` 部署失败后的 HEAD/HOME/
目录权限回退、悬空链接、双边复制冲突和机密拦截：

```bash
bash -n bin/dotfiles tests/test.sh
./tests/test.sh
```
