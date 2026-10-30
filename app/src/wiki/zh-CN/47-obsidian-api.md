---
title: Obsidian 运行时 API
group: 制作模组
summary: "模组运行时：按名称访问游戏数据、受检查的修改和现成操作。"
---

Obsidian API 是供其他模组使用的模组。它知道游戏中各项内容的位置，以游戏接受的方式进行修改，并在需要时撤销。Obsidian Trainer 就是这样工作的，它没有使用任何你用不到的功能。

## 使用方法 {#using-it}

把它写进 `requires`，Obsidian 会随你的模组一同启用它，并先启动它：

```json
"scope": "session",
"entry": "main.lua",
"requires": ["obsidian.api"]
```

然后获取它：

```lua
local api = obsidian.import("obsidian.api")

obsidian.keybind("panic", function()
  api.player.heal()
  api.enemies.kill_near(20)
end)
```

操作返回 `true`，或者返回 `false` 和简短的原因，例如 `"host_only"`、`"no_avatar"` 或 `"not_in_mission"`。

## 修改游戏数据 {#edits}

`api.edits` 修改设置表，并记录改了什么、谁改的以及原来的值。

```lua
-- 将突击步枪的伤害翻倍，包括升级版本。
local ok, why = api.edits.set_unit("equipment/wep_assaultrifle_01", "weapon_info.power", 150)

-- 修改游戏读取的任意表中的值。
local s = api.catalog.stratagem("stratagem_resupply")
api.edits.set_table("Resupply", s, "cooldown_time", 30)
```

- 会检查类型和范围，`opts` 可以提供 `min` 和 `max`。
- 表保持为同一张表，因为游戏中的单位持有对它们的引用。
- 武器的每种升级都有一份设置副本，修改会覆盖所有副本。
- `api.edits.list()`、`revert(id)` 和 `revert_all()` 用于查看和撤销更改。
- 当大厅不再处于许可状态时，所有修改都会撤销；重新许可后会恢复。

可编辑的字段、范围和生效时机见 `api.catalog.fields(family)`。有些数值立即生效，有些在下次生成时生效。`api.gear.refresh()` 会把缓存的数值应用到正在使用的武器上。

## 效果 {#effects}

效果在重生和任务之间保持开启。游戏这时会重建大部分状态，所以运行时会重新应用已启用的效果。

```lua
api.effects.set("god", true)
api.effects.set("speed", 2)     -- 一个数值，false 表示关闭
api.effects.is_on("god")
```

自定义效果：

```lua
api.effects.define({
  id = "mymod.low_gravity",
  apply = function(ctx, value) end,            -- 开启时，以及重生或新任务后再次调用
  frame = function(ctx, value, dt) end,        -- 开启期间每帧调用
  remove = function(ctx, value) end,           -- 关闭时
})
```

`ctx` 包含 `state`、`name`、`record` 和 `unit`，它们都可能为 nil。

## API 内容 {#contents}

| 表 | 用途 |
|---|---|
| `api.game` | 当前状态、本地玩家、`is_host()` 和安全写入 |
| `api.catalog` | 按名称列出武器、战略配备、技能、敌人和敌群，不含玩家未拥有的付费物品 |
| `api.player` | `heal`、`respawn`、`teleport`、`set_cosmetic` 等 |
| `api.gear` | `refill`、`give_weapon`、`give_perk`、`refresh` |
| `api.stratagems` | `reset_cooldowns`、`refill_uses`、`give`、`drop` |
| `api.enemies` | `spawn`、`spawn_group`、`kill_all`、`list` |
| `api.mission` | `finish_objectives`、`win`、`abort`、`practice` |
| `api.world` | `cursor`、`ahead`、`explode` |
| `api.progress` | `set_samples`、`unlock_items`、`upgrade_all` |
| `api.console` | `run(line)`、`commands()` |

## 重要规则 {#rules}

> [!WARNING]
> 游戏会为受保护的数值保留哈希副本，例如 `hitpoints_real`、`rounds`、`cooldown_timer`、`uses_left`、`num_grenades` 和 `extra_lives`。直接写入这些值会触发防篡改检查，使玩家断开网络直到重启。请使用 `api.game.protected` 或排队命令。`api.edits` 会拒绝这些键。

- `api.game.command(unit, component, command, data)` 从已知列表中向本玩家拥有的单位排队命令。直接向游戏排队未知命令会使游戏因脚本无法捕获的错误而停止。
- 游戏只在大于零时运行的计时器（例如空投舱的 `drop_time`）设为 0 时永远不会结束。请使用 0.01。
- 生成资源包未加载的单位会使游戏停止。`api.enemies.available(enemy)` 可以检查。
- `api.console.run` 会拒绝访问共享后端、清除存档或解锁付费内容的命令。
- 修改经验值之前，请先了解修改器为什么不做这件事：总经验值会随之后的普通结果一起上传，即使清除后也是如此。
