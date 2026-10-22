# AGENTS.md — 在只有 opencode 的全新 Termux 上部署 dsh + dshpj

你是这台 Android 手机 Termux 里的执行代理。任务：把 **DeepSeek Harness（dsh）** 和
**dshpj 补丁栈** 装到本机，并且（如果给了一个快照包 URL/路径）把它还原成与旧机
一模一样的状态。

目标机器事实（不要质疑、不要改写）：

- Termux 前缀固定 `/data/data/com.termux/files/usr`，家目录固定
  `/data/data/com.termux/files/home`。
- 架构 `aarch64`；包管理 `pkg`（apt 包装）。
- 本机现在只有 Terminal + opencode，可能连 `node` 都没有。

## 硬性规则

1. **一条命令搞定**：执行 `agents/bootstrap.sh`，不要手工逐条复制粘贴里面的步骤，
   除非它报错需要你定位。
2. **不要 `rm -rf` 任何 `~/.dsh*`**：还原脚本自己会备份成 `.bak-<时间戳>`。
   你只在用户明确说"清掉重装"时加 `--fresh`。
3. **不要改 dsh 的 npm 包内容**（补丁栈是 `--patch` 叠加，不 patch 源码）。
4. **不要伪造输出**：每条命令贴真实 stdout/stderr。装了就是装了，失败就贴失败。
5. **网络失败 = 换路线**，不要放弃：
   - `curl` 失败先试 `curl -4`、再试 `GIT_HTTP_VERSION=HTTP/1.1`；
   - GitHub raw 不通就 `git clone --depth 1 https://github.com/zoujiapeng/dshpack`；
   - 仍然不通 → 让用户用局域网路径（旧机 `dshpack serve`，新机 `curl -fLO http://<ip>:8899/...`）。
6. **需要用户决策的点只有三处**（其余自己判断）：
   `su` 授权弹窗、`termux-setup-storage` 授权、是否要把凭证（`~/.dsh/.credentials.yaml`、
   `~/.ssh`）从旧机搬过来。

## 步骤

### 0. 侦察（30 秒）

```bash
uname -o; uname -m; echo "$PREFIX"; id -u; command -v node npm git curl zstd pkg su
```

预期：`Android` / `aarch64` / `/data/data/com.termux/files/usr`。`node` 通常**不存在**，
这是正常的，下一步会装。

### 1. 拿脚本

```bash
mkdir -p ~/dsh-deploy && cd ~/dsh-deploy
curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/bootstrap.sh -o bootstrap.sh
chmod +x bootstrap.sh
```

不通就用 git：

```bash
git clone --depth 1 https://github.com/zoujiapeng/dshpack ~/dsh-deploy-src
cp ~/dsh-deploy-src/agents/bootstrap.sh ~/dsh-deploy/
```

### 2. 跑

有快照包（推荐，能还原成和旧机一模一样）：

```bash
bash bootstrap.sh --bundle http://<旧机IP>:8899/dshpack-<机型>-arm64-std-<时间>.run
```

没有包（只装干净的 dsh + dshpj）：

```bash
bash bootstrap.sh
```

前置包清单：`nodejs-lts tar zstd curl git openssl termux-exec`，脚本自己 `pkg install`。
dsh 版本默认锁定 `0.2.0-rc.2`（用 `DSH_VER=` 覆盖）。

### 3. 验收（必须真跑，把输出贴给用户）

```bash
node -v
dsh --version
ls -l ~/.dshpj/assets/patch.yml
dshpack info
```

期望：`node v25.x`、`0.2.0-rc.2`、`patch.yml 存在`、`dshpack 1.0.0` + 本机指纹。

`dshpj` **不要**在验收阶段直接前台跑（它会起 web 服务并开浏览器）；要验证就：

```bash
DSHPJ_NO_OPEN=1 timeout 25 dshpj >/tmp/dshpj.out 2>&1 &
sleep 18   # 等它打印 http://<ip>:3081 和二维码
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3081/
tail -5 /tmp/dshpj.out
```

看到 `200` 就是起来了。收尾：

```bash
pkill -f 'dshpj' ; pkill -f '3081'   # 需要时
```

## 还原包里有什么（用于向用户解释）

| 路径 | 内容 |
|---|---|
| `~/.dsh/profiles`、`storages`、`llm-deepseek` | dsh 的 profile 树、存储、模型网关配置 |
| `~/.dsh/sessions` | 会话历史（旧机上的对话都在） |
| `~/.dshpj` | 补丁栈：`assets/patch.yml` + `pj-*.mjs` + `bin/dshpj` |
| `$PREFIX/lib/node_modules/@deepseek-ai` | dsh 及其全部依赖（403 MB，二进制级一致） |
| `$PREFIX/bin/{dsh,dshpj,dsh-lan,dshpj-doctor,dshui}` | 启动器包装脚本 |

包内 `MANIFEST.json` 记录旧机的 node/npm/dsh 版本与 233 个 Termux 包清单；
`CHECKSUMS.sha256` 是逐文件校验（`dshpack restore` 会先校验再落盘）。

## 常见问题

| 症状 | 处理 |
|---|---|
| `dsh` 启动后立刻退出、DNS 失败 | 用 `su` 跑（Magisk），`dsh` 包装器已内置 `exec su -c` |
| `npm i -g` 报 `EACCES` | `su -c 'npm i -g @deepseek-ai/dsh@0.2.0-rc.2'` |
| `@deepseek-ai/dsh-app-boot` internals 报错 | 必须用 `$PREFIX/bin/dsh` 启动（它带 `--expose-internals`），不要直接 `node lib/bin.js` |
| `dshpj` 端口被占 | `DSHPJ_PORT=3085 dshpj` |
| 还原后 `dsh` 版本凭空变新 | 别跑 `npm update -g`，要固定就 `npm i -g @deepseek-ai/dsh@0.2.0-rc.2` |

## 给用户的最终回复格式

```
已部署：dsh <版本> / dshpj <就绪|未装> / dshpack <版本>
还原来源：<URL 或 "无，仅干净安装">
验收：<node -v 输出>，HTTP 200 on 127.0.0.1:3081
下一步：dshpj
```
