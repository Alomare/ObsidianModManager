---
title: 出现问题时
group: 帮助
summary: 日志、启动时崩溃、模组不加载，以及如何恢复原版。
---

## 先恢复原版 {#back-to-vanilla-first}

游戏表现异常时，**清除** 会从游戏中移除 Obsidian 的所有文件。如果清除后问题依旧，原因就不在 Obsidian；请在 Steam 中验证游戏文件完整性。

## 游戏启动时崩溃 {#the-game-crashed-at-startup}

加载器在启动每个模组之前都会写一行日志。如果游戏在那一刻停止，下次打开 Obsidian 时它会指出当时正在启动的模组。停用该模组、重新部署，并告知作者。

## 模组没有效果 {#a-mod-does-nothing}

- 确认模组已启用，并且启用后进行了部署。绿色的 **部署** 按钮表示有等待中的更改。
- 对于会话模组，检查大厅：有未同意的玩家时，会话模组会关闭（[联机游戏](wiki:multiplayer)）。
- 阅读日志（见下文）。启动失败的模组会在那里留下错误信息。

## "未知版本" {#build-unknown}

游戏文件与 Obsidian 认识的版本不符，因此不会部署任何内容，加载器也不会启动任何模组。先清除，再在 Steam 中验证游戏文件完整性。如果你用过直接修改资源包的其他模组工具，验证会恢复原始文件。

## 日志 {#logs}

日志位于 `%APPDATA%\Arrowhead\Helldivers\ObsidianModManager\logs`：

| 文件 | 内容 |
|---|---|
| `loader.log` | 每个模组的启动、挂钩的安装、多人游戏状态，以及每个模组在加载器之外所做的更改 |
| `<模组 id>.log` | 该模组用 `obsidian.log` 写下的内容，仅此而已 |

游戏自身的崩溃报告位于 `%APPDATA%\Arrowhead\Helldivers\crash`。

## 寻求帮助 {#asking-for-help}

请带上 `loader.log`、当时启用的模组列表和发生的情况，前往 [Discord](https://dsc.gg/hd1modding) 或提交 [GitHub issue](https://github.com/Alomare/ObsidianModManager/issues)。
