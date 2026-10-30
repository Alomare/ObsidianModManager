---
title: 编写会话模组
group: 制作模组
summary: 如何修改共享游戏，同时让防护措施继续为你工作。
---

会话模组会改变其他玩家能察觉的内容：伤害、敌人、生成、任务。加载器决定这类模组何时可以运行（[联机游戏](wiki:multiplayer)），并随玩家进出开启或关闭它。你要做的是让每项更改都经过加载器，这样它才能被关闭。

## 设置作用范围 {#set-the-scope}

```json
"scope": "session"
```

省略该字段效果相同。只有当模组所做的一切都不会影响其他玩家时，才使用 `client`。

## 通过挂钩修改游戏 {#change-the-game-through-hooks}

大厅未获许可时，会话模组的挂钩会自动调用游戏原本的代码。完全由挂钩构成的模组不需要额外代码就是安全的：

```lua
-- 每次射击的伤害翻倍，仅在获许可的大厅中生效。
obsidian.hook("Damage", "apply", function(original, target, amount, ...)
  return original(target, amount * 2, ...)
end)
```

`on_frame` 函数和按键也一样：在未获许可的大厅中，它们不会运行。

## 撤销残留的更改 {#undo-what-stays-behind}

有些更改在调用结束后依然存在：写入设置表的值、你生成的单位。监听开关状态并把它们复原：

```lua
local original_speed

obsidian.on_require("lua/settings/player_settings", function(settings)
  original_speed = settings.run_speed
end)

obsidian.on_session(function(on)
  local settings = rawget(_G, "PlayerSettings")
  if settings and original_speed then
    settings.run_speed = on and original_speed * 1.5 or original_speed
  end
end)
```

## 应避免的做法 {#things-to-avoid}

- **直接替换全局变量。** `SomeTable.func = mine` 会在任何大厅中持续运行，因为加载器无法关闭它。加载器会在启动时把每个模组的此类更改写入日志。
- **用资源替换游戏脚本来改变玩法。** 被替换的脚本同样无法即时关闭。Obsidian 允许这样做，但在有未同意玩家的大厅中，这项更改仍留在你的游戏里，而你的其他会话模组会关闭。
- **在游戏自身代码之外，向其他玩家发送自定义网络消息。**

> [!NOTE]
> 修改你自己的进度（例如经验或解锁）是允许的。Obsidian 会在每次部署前备份存档，且不会撤销这些更改。

## 会话模组中的选项 {#options-in-session-mods}

比较玩家的组合时，每个选项值都会计入，除非你把它标记为 `"scope": "client"`。请标记那些只改变该玩家自己所见内容的选项（[选项和按键](wiki:options-and-keys#personal-options-in-session-mods)）。
