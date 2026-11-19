# dsh-config-rescue

一个小工具箱，用来在 **DeepSeek Harness Desktop** 的 profile 配置被写坏、桌面打不开的时候，把配置验一遍、恢复回去。

起因是一次真实事故：一份 `cordis.patch.yml` 被 PowerShell 按 GBK 读、又带 BOM 写回，中文末字节把换行吃掉，`displayName:` 和下一行的 `api: openai-completions` 挤成了一行 —— DSH 启动即 fatal，界面上只剩一个崩溃窗口，改配置的入口本身也打不开了。

## 里面有什么

| 文件 | 作用 |
| --- | --- |
| `verify-yaml.mjs` | 只读检查：BOM、U+FFFD、乱码片段、能否解析成 YAML 列表、条目数够不够 |
| `restore-overlay.ps1` | 用一份「已知可用」的覆盖层替换现场，写前校验、写后复验、失败自动回滚 |
| `LICENSE` | MIT |

两者都只依赖 Node（DSH 自带的那份就够），不需要 `npm install`、不需要联网。

## 用法

```powershell
# 1) 只检查，不改任何东西
node verify-yaml.mjs "C:\Users\<you>\AppData\Roaming\dsh-desktop\harness\profiles\desktop\cordis.patch.yml"

# 2) 检查 + 恢复（-Good 指向你留好的那份好文件）
.\restore-overlay.ps1 -Good .\good\cordis.patch.yml `
    -ProfileDir "$env:APPDATA\dsh-desktop\harness\profiles\desktop" -MinEntries 30

# 3) 顺带恢复 preset patch 与 package.json
.\restore-overlay.ps1 -Good .\good\cordis.patch.yml -Presets .\good\presets `
    -PresetDir "$env:APPDATA\dsh-desktop\harness\plugins\qq-agent-presets\presets" `
    -PackageJson .\good\package.json
```

`verify-yaml.mjs` 的退出码：`0` 正常、`1` 有问题、`2` 用法错、`3` 找不到 js-yaml（解析检查被跳过）。设置 `DSH_JS_YAML` 指向一个 `js-yaml.mjs` 就能让它生效。

## 三条硬规则（都是踩出来的）

**1. 别用 PowerShell 往返搬运 YAML。**
`Get-Content -Raw` 按 GBK 读、`Set-Content -Encoding utf8` 带 BOM 写，一个来回就够把中文配置变成乱码 + 断行。要么用真正懂 UTF-8 的编辑器改，要么改完立刻跑 `verify-yaml.mjs`。

**2. 改 `package.json` 必须在 DSH 完全退出之后。**
运行中的实例退出时会按内存里的旧列表回写整个 `dsh.profile.bundles`。你在外面加的行不会生效，还会被无声抹掉 —— 表现是「重启后插件数少了两个」。

**3. preset 的 `suffix` 里不要写 `{{cwd}}`。**
dsh 0.2.x 的 agent loop 不再注册这个变量，任何无法解析的引用都会在模型请求之前让提示词装配失败，QQ / IM 那侧看到的就是「agent 处理出错：unknown prompt variable」。

## 许可证

MIT。随便用，出问题别找我。