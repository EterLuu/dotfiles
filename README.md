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
dotfiles update                      # git pull --ff-only 后重新安装
dotfiles save -m "update vim"        # 收集副本、创建本地 commit 并重新安装
dotfiles sync -m "sync configs"      # 提交 + pull --rebase + push，一键同步
dotfiles uninstall                   # 只删除未被修改的托管文件
dotfiles root                        # 显示当前仓库位置
dotfiles config list                 # 显示设备设置
```

`uninstall` 不删除设备本地配置和备份。复制模式下，如果 HOME 中的副本被修改，
它也会保留该文件并提示，避免误删。

### 链接与复制模式

macOS、Linux 和 WSL 默认使用绝对符号链接；原生 Windows 的 Git Bash/MSYS2
默认使用复制，避免 Windows 开发者模式、权限和 Git symlink 配置造成的不一致。
可以按设备永久覆盖：

```bash
dotfiles config set install-mode link   # auto、link 或 copy
dotfiles install
```

也可用 `dotfiles install --mode copy` 做单次覆盖。复制模式既可以在仓库里编辑
源文件，也可以直接编辑 HOME 副本后用 `dotfiles save` 安全回收；工具保存了上次
部署基线，能区分“仓库有更新”“HOME 有更新”和“两边同时修改”的冲突。`status`
会发现 HOME 副本与仓库的差异。Windows 上若需完整 Unix 行为，优先选择 WSL。
此仓库不自动管理 PowerShell Profile。

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
dotfiles sync -m "update shell settings"       # 提交、拉取远端更新并推送
```

`sync`（别名 `publish`）的完整顺序是：收集复制模式下修改过的 HOME 配置、
仅暂存本项目允许的配置目录、检查疑似私钥和常见 token、创建 commit、执行 `git pull --rebase`、
`git push`，最后重新部署。若省略 `-m`，会使用包含时间的自动消息。
如果仓库与 HOME 自上次部署后修改了同一个复制文件，命令会停止并报告冲突，
不会猜测应该覆盖哪一边。

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

其他设备执行 `dotfiles update`。该命令只允许 fast-forward，并在仓库存在未提交
修改时停止，防止覆盖工作。首次迁移已有 HOME 时，先运行 `--dry-run`；安装器
产生备份后，应确认新环境正常，再自行归档或删除旧备份。

## 扩展配置

`.dotfiles-manifest` 每行格式如下，目标必须相对 `$HOME`：

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

测试完全使用临时 HOME，不接触真实用户配置：

```bash
bash -n bin/dotfiles tests/test.sh
./tests/test.sh
```
