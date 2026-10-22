# dshpack

把一台手机 Termux 上跑着的 **DSH（DeepSeek Harness）+ dshpj 补丁栈**整套环境打成单文件包，
在另一台手机的 Termux 上一条命令还原成和原机一模一样的状态。

```
原机:  dshpack pack --mode std
新机:  dshpack restore dshpack-LE2120-arm64-std-20261022-1900.tar.zst
新机:  dshpj
```

## 为什么能“一模一样”

Termux 的前缀在所有 Android 设备上是固定的：

| 位置 | 路径 |
|---|---|
| 前缀 | `/data/data/com.termux/files/usr` |
| 家目录 | `/data/data/com.termux/files/home` |
| 全局包 | `$PREFIX/lib/node_modules` |

也就是说 `shebang`、`$PREFIX/bin/dsh` 包装脚本、`.dshpj/assets/patch.yml` 里的
绝对路径、cordis profile 的 `pnpm-lock.yaml` —— 搬过去不用改一个字。dshpack 因此
**直接搬二进制文件树**，而不是“在新机器上重新装一遍”。

## 打包了什么

```
dshpack-<机型>-arm64-<mode>-<时间>/
├── MANIFEST.json        # 环境指纹：node/npm/dsh 版本、全局包、Termux 包清单、路径
├── MANIFEST.txt         # 人读摘要
├── CHECKSUMS.sha256     # 逐文件校验和
├── RESTORE.sh           # 目标机上的还原脚本（自带 root 逃逸、备份、自检）
├── dshpack              # 打包器自己的副本
├── payload/
│   ├── home/
│   │   ├── .dsh/        # profiles / storages / llm-deepseek（+ std 以上含 sessions）
│   │   ├── .dshpj/      # 补丁栈：assets/patch.yml、pj-*.mjs、bin/dshpj、doctor
│   │   ├── .dshpj-lab/  # 实验副本（不含 logs）
│   │   ├── .termux/     # termux.properties、boot/
│   │   └── .bashrc .npmrc .gitconfig ...
│   └── prefix/
│       ├── bin/         # dsh、dshpj、dsh-lan、dshpj-doctor、dshui
│       └── lib/node_modules/@deepseek-ai/   # dsh 0.2.0-rc.2 及其全部依赖
└── secrets/             # 仅 --secrets 时出现，且不会被 RESTORE.sh 自动落盘
```

## 三种模式

| 模式 | 体积 | 内容 | 用途 |
|---|---|---|---|
| `slim` | ~4 MB | 配置层 + 补丁栈 + 包装器，不带 node_modules | 目标机已装 dsh，只要配置；还原时 `npm i -g @deepseek-ai/dsh@<版本>` |
| `std`（默认） | ~150–250 MB | slim + `@deepseek-ai/*` 全局包 + 会话历史 | **换机推荐**，还原后开箱即用 |
| `full` | ~400–600 MB | std + `~/.dsh/runtime/node-glibc` + `speech-to-text` 模型 + `attachments` | 连语音识别模型、附件缓存都要一致 |

排除项永远是：`pj-logs/`、`*.pid`、`.dsh/cache`、`.dsh/logs`。

## 用法

```bash
# 安装打包器
install -m755 dshpack $PREFIX/bin/dshpack

dshpack info                              # 先看本机状态
dshpack pack --mode std                   # 默认输出到 ~/dshpack-out/
dshpack pack --mode full --level 19       # 全量，压缩率优先
dshpack pack --secrets                    # 连凭证一起打进 secrets/（自己决定怎么传输）

dshpack list   dshpack-out/xxx.tar.zst    # 看包内容与环境指纹
dshpack verify dshpack-out/xxx.tar.zst    # 逐文件 sha256 校验
dshpack restore xxx.tar.zst               # 就地还原（自动备份旧目录为 .bak-<时间戳>）
dshpack restore xxx.tar.zst --fresh       # 先删旧目录再还原（干净换机）
dshpack restore xxx.tar.zst --pkgs        # 顺手 pkg install 缺失的 Termux 包
dshpack restore xxx.tar.zst --dry-run     # 只打印会做什么
```

在目标机上没有 `dshpack` 也能装：解包后直接跑包内脚本。

```bash
zstd -dc dshpack-*.tar.zst | tar -xf - && cd dshpack-*/
sha256sum -c CHECKSUMS.sha256 && bash RESTORE.sh --pkgs
```

## 让 AI 代理（opencode）去装

新机上只有 opencode、连 node 都没有也没关系：`agents/` 里有给代理看的部署手册。

```bash
# 旧机：开局域网分发，打印网址 + 终端二维码
dshpack serve                 # → http://<旧机IP>:8899/

# 新机
mkdir -p ~/dsh-deploy && cd ~/dsh-deploy
curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/AGENTS.md -o AGENTS.md
curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/bootstrap.sh -o bootstrap.sh
opencode
```

然后对 opencode 说：

> 读 AGENTS.md，按它把 dsh + dshpj 装到本机，并从
> `http://<旧机IP>:8899/dshpack-xxx.run` 还原。每一步都真跑，把真实输出贴给我。

不想让代理读文件，直接给它一句：

> 执行 `bash <(curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/bootstrap.sh)`
> 装上 dsh + dshpj，然后贴出 `node -v`、`dsh --version`、`dshpack info` 的真实输出。

`agents/bootstrap.sh` 自己做：`pkg install` 前置包 → `npm i -g @deepseek-ai/dsh@0.2.0-rc.2`
→ dshpj 补丁栈 → dshpack → 可选 `--bundle` 还原 → 打印自检。幂等，重复跑只补缺的部分。
话术模板与回退策略见 [agents/PROMPT.md](agents/PROMPT.md)，代理规则见
[agents/AGENTS.md](agents/AGENTS.md)。

## 新机前置（一次性）

```bash
pkg update && pkg install -y nodejs-lts git tar zstd openssl termux-exec
termux-setup-storage      # 可选，用于从共享存储把包拷进来
```

`RESTORE.sh` 会：校验 sha256 → 备份旧 `~/.dsh` 等目录 → 还原 home 树 → 还原
`@deepseek-ai/*` → 安装 `$PREFIX/bin` 包装器 → 打印版本自检。非 root 时自动经
Magisk `su` 重新执行（与 `dsh` 启动器的逃逸路径一致）。

## 注意

- `--secrets` 会把 `~/.dsh/.credentials.yaml`、`~/.ssh`、`.gh_token`、`.git-credentials`
  复制进 `secrets/`。`RESTORE.sh` 刻意不自动落盘，需要自己放回原位。
- `full` 模式包含 `~/.dsh/runtime/node-glibc`（glibc Node，~229 MB），只在用到
  glibc 生态（如 speech-to-text）时才需要。
- 打包结束时输出 `xxx.tar.zst.sha256`，传输后先校验再还原。

## 许可

MIT
