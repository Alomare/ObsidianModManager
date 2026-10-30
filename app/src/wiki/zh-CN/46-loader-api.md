---
title: 加载器 API
group: 制作模组
summary: obsidian 表中的每个函数，第 1 版。
---

游戏启动时，Obsidian Loader 按加载顺序启动每个已启用模组的 `entry` 脚本，各一次。每个脚本都能看到名为 `obsidian` 的全局表。模组通过它注册的所有内容都受保护运行：出错只会写入日志，绝不会阻止游戏启动。

## 挂钩 {#hooks}

### obsidian.hook(target, method, fn) {#obsidian-hook-target-method-fn}

包裹游戏中的一个函数。`target` 是一个表，或以字符串表示的全局表名。`fn` 首先收到原函数，然后是调用参数：

```lua
obsidian.hook("PlayerUnitMovement", "update", function(original, self, dt)
  -- 游戏代码之前
  local result = original(self, dt)
  -- 游戏代码之后
  return result
end)
```

如果该全局还不存在，挂钩会等待，在游戏定义它后立即生效。如果 `fn` 出错，则改为运行原函数。

在会话模组中，大厅未获许可时挂钩只会调用原函数（[编写会话模组](wiki:session-mods)）。

### obsidian.on_require(name, fn) {#obsidian-on-require-name-fn}

游戏加载脚本 `name`（例如 `"lua/settings/perk_settings"`）时调用 `fn(module)`。可用于在游戏构建设置表之后立即修改它。

### obsidian.on_frame(fn) {#obsidian-on-frame-fn}

每帧调用一次 `fn`。返回 `true` 即停止调用。会话模组的每帧函数只在获许可的大厅中运行。

### obsidian.after_startup(fn) {#obsidian-after-startup-fn}

所有模组启动后调用一次 `fn`，让模组之间无需依赖加载顺序就能协作。

## 设置和按键 {#settings-and-keys}

### obsidian.settings.get(id) {#obsidian-settings-get-id}

本模组选项 `id` 的值：玩家在应用中所选的值，或默认值（[选项和按键](wiki:options-and-keys)）。

### obsidian.keybind(id, fn) {#obsidian-keybind-id-fn}

每次绑定到 `id` 的按键按下时调用 `fn`。按键来自应用，或来自 `obsidian.json` 中的默认值。

## 多人游戏 {#multiplayer}

### obsidian.session.cleared() {#obsidian-session-cleared}

该玩家的会话模组可以运行时为 `true`。客户端模组很少需要它。

### obsidian.session.members() {#obsidian-session-members}

大厅中其他玩家的列表。每项包含 `peer`、`obsidian`（该玩家是否使用 Obsidian）、`modset` 和 `consent`。

### obsidian.on_session(fn) {#obsidian-on-session-fn}

每当加载器开启或关闭本模组时调用 `fn(on)`，让模组可以撤销其他玩家会看到的更改。

## 文本和日志 {#text-and-logs}

### obsidian.text(key, ...) {#obsidian-text-key}

从模组 `locales` 文件夹中按游戏语言取文本 `key`，缺失时使用英文。额外参数用于填充 `%s` 和 `%d` 占位符。

### obsidian.log(...) {#obsidian-log}

向本模组的日志写一行，位于 `%APPDATA%\Arrowhead\Helldivers\ObsidianModManager\logs`。

## 版本和功能 {#version-and-features}

`obsidian.version` 是 API 版本，目前为 `1`。需要更新 API 的模组在 `obsidian.json` 中设置 `loader_api`，较旧的加载器会拒绝启动它。

`obsidian.capabilities` 是一个只读表，列出当前加载器支持的功能，每项一个条目：`hook`、`on_require`、`on_frame`、`on_session`、`after_startup`、`settings`、`keybind`、`session`、`text`、`log`。使用较晚加入的功能前，先按名称检查：

```lua
if obsidian.capabilities.on_frame then
  obsidian.on_frame(update)
end
```

## 模组出错时 {#when-a-mod-fails}

- 启动时出错会在本次会话中关闭该模组，并把错误写入 `loader.log`。
- 挂钩和回调中的错误在每个位置最多记录三次，因此出错的每帧函数不会刷屏日志。
- 持续出错的模组会在本次会话剩余时间内被关闭。
- 如果游戏在某个模组启动时崩溃，应用会在下次启动时指出该模组。
