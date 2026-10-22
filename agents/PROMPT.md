# 复制这几句给 opencode

## A. 有旧机快照包（推荐 —— 装完和旧机一模一样）

先在**旧机**上开分发（一条命令，会打印网址和二维码）：

```bash
dshpack serve            # → http://192.168.x.x:8899/
```

然后在新机的 Termux 里：

```bash
mkdir -p ~/dsh-deploy && cd ~/dsh-deploy
curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/AGENTS.md -o AGENTS.md
curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/bootstrap.sh -o bootstrap.sh
opencode
```

在 opencode 里发这一句：

> 读 AGENTS.md，按它把 dsh + dshpj 装到本机，并从
> `http://192.168.x.x:8899/dshpack-<机型>-arm64-std-<时间>.run` 还原。
> 每一步都真跑，把命令的真实输出贴给我。

## B. 没有快照包（只装干净环境）

```bash
opencode
```

> 读 AGENTS.md，只做第 1、2 步（不带 --bundle），装完跑第 3 步验收，
> 把 node -v、dsh --version、dshpack info 的真实输出贴给我。

## C. 连 AGENTS.md 都不想下载（最短的一句话）

> 在本机 Termux 里执行
> `bash <(curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/agents/bootstrap.sh)`
> 把 dsh 和 dshpj 装上；前置包用 pkg install nodejs-lts tar zstd curl git。
> 装完跑 `node -v`、`dsh --version`、`dshpack info` 并贴真实输出。

## D. 想让 opencode 自己从零推导（不给脚本）

> 目标：在 Termux 里装 @deepseek-ai/dsh@0.2.0-rc.2（全局，node 用 pkg 的 nodejs-lts），
> 再装 dshpj 补丁栈（`curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpj-installer/main/bootstrap.sh | bash`），
> 再装 dshpack（`curl -fsSL https://raw.githubusercontent.com/zoujiapeng/dshpack/main/dshpack -o $PREFIX/bin/dshpack && chmod +x $PREFIX/bin/dshpack`）。
> 注意：dsh 必须通过 `$PREFIX/bin/dsh` 启动（它带 `--expose-internals`），
> 不要直接 `node .../lib/bin.js`。装完真跑 `dsh --version`，把输出贴给我。

---

## 为什么这套话术有效

| 要素 | 作用 |
|---|---|
| `AGENTS.md` 放在工作目录 | opencode 启动时自动读，等于把"部署手册"塞进它的上下文 |
| 硬性规则第 4 条（不许伪造输出） | 让它每条命令真跑真贴，避免"已安装 ✅"式的空话 |
| 网络失败的三级回退 | 手机上 GitHub 经常抽风，写死回退路径它就不会卡住 |
| 只给三处需要用户决策的点 | 其余自己判断，不会来回问 |
| 验收命令写死 | 结果可验证：`node -v` / `dsh --version` / HTTP 200 |
