---
title: Obsidian 模组 API
group: 制作模组
summary: "模组库：按名称访问游戏数据、受检查的修改和现成操作。"
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
- `set_table` 的 `opts.also` 可以列出更多路径，它们取同一个值，算作一次更改。
- 当大厅不再处于许可状态时，所有修改都会撤销；重新许可后会恢复。

战略配备的升级等级可以自己设置某个字段，所以只改基础值在这些等级上不起作用。`api.stratagems.edit` 会一次修改所有等级，并使用该字段的范围：

```lua
api.stratagems.edit("stratagem_railcannon_strike", "cooldown_time", 30)
```

可编辑的字段、范围和生效时机见 `api.catalog.fields(family)`。`api.catalog.families_of(settings)` 说明设置表包含哪些类别。有些数值立即生效，有些在下次生成时生效。`api.gear.refresh()` 会把缓存的数值应用到正在使用的武器上。

## 效果 {#effects}

效果在重生和任务之间保持开启。游戏这时会重建大部分状态，所以它会重新应用已启用的效果。

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

`ctx` 包含 `state`、`name`、`record` 和 `unit`，它们都可能为 nil。请为每个效果提供 `remove`，这样大厅不再处于许可状态时它才能撤销。

## 事件 {#events}

`api.events.on(name, fn)` 会在游戏通知某事发生时调用你的函数，无需每帧检查。

```lua
local kills = 0

api.events.on("on_enemy_killed", function(unit, attacker, owner)
  kills = kills + 1
  if kills == 50 then api.ui.hint("已消灭五十个") end
end)
```

| 事件 | 函数收到的参数 | 时机 |
|---|---|---|
| `on_enemy_killed` | `unit`、`attacker`、`owner`、`damage_type` | 本玩家击杀了敌人。只有本机计算这次命中时才有 `damage_type` |
| `on_enemy_spawned` | `unit`、`enemy_name` | 敌人出现，每位玩家的游戏都会收到 |
| `on_player_death` | `unit` | 玩家死亡，每位玩家的游戏都会收到 |
| `on_objective_completed` | 无 | 目标完成 |
| `on_stratagem_activated` | `peer`、`stratagem`、`position`、`unit` | 战略配备倒计时结束，每位玩家的游戏都会收到 |
| `on_avatar_extract` | `unit`、`shuttle` | 本玩家登上撤离飞船 |

- 函数出错时会计入你的模组，其他函数继续运行。
- 大厅未处于许可状态时不会收到任何事件。
- `position` 只在当前帧有效。要保留请复制 `x`、`y` 和 `z`。
- `api.events.off(name, fn)` 用于取消。

## API 内容 {#contents}

| 表 | 用途 |
|---|---|
| `api.game` | 当前状态、本地玩家、`is_host()` 和安全写入 |
| `api.catalog` | 按名称列出武器、战略配备、技能、敌人和敌群，不含玩家未拥有的付费物品。还有 `backpacks`、`crates`、`pickups`、`vehicles`、`by_subtype(name)` 和 `max_upgrade(path)` |
| `api.player` | `heal`、`respawn`、`teleport`、`set_cosmetic` 等 |
| `api.gear` | `refill`、`give_weapon(slot, path, upgrade)`、`give_backpack(path, upgrade)`、`give_perk`、`remove_perk`、`refresh` |
| `api.stratagems` | `reset_cooldowns`、`refill_uses`、`give`、`drop`、`call(name, pos, delay)`、`edit(name, field, value)` |
| `api.enemies` | `spawn`、`spawn_group`、`spawn_entity(path, pos)`、`kill_all`、`kill(unit)`、`list`、`info(unit)`、`nearest(pos)`、`apply_status(unit, template)`、`stun_near(radius)`、`set_pressure(t)`、`waves()`、`force_wave(name, pos)` |
| `api.mission` | `finish_objectives`、`objectives()`、`mutator(name)`、`win`、`abort`、`practice` |
| `api.vehicles` | `current()`、`driving()`、`repair()`、`refill()` |
| `api.combat` | `scale{ players, enemies }` |
| `api.events` | `on(name, fn)`、`off(name, fn)` |
| `api.ui` | `hint(text, seconds)`、`ping(pos)` |
| `api.lobby` | `players()` |
| `api.world` | `cursor`、`ahead`、`explode` |
| `api.progress` | `set_samples`、`unlock_items`、`upgrade_all` |
| `api.console` | `run(line)`、`commands()` |

## 装备 {#gear}

`give_weapon` 和 `give_backpack` 的 `upgrade` 取值 0 到 15。省略时使用玩家为该物品拥有的升级。`api.catalog.max_upgrade(path)` 给出最高值。

`give_backpack` 只接受 `api.catalog.backpacks()` 中的路径，因为游戏会读取其他路径没有的设置，而且那里的错误无法捕获。旧背包会掉到地上，旧武器也一样。

`give_perk` 以游戏控制台的方式更换技能。大厅里有其他玩家时，激光瞄准器会返回 `"alone_only"`，因为他们的游戏会在没有初始化的情况下运行它。

## 战略配备 {#stratagems}

`api.stratagems.call` 会放下一枚真实的信标，和游戏自己的定时投放一样。它有声音和倒计时，巡逻队能听到，增援也可以使用。它不消耗冷却或次数，并按玩家拥有的等级呼叫。

```lua
api.stratagems.call("stratagem_resupply", api.world.cursor(), 15)   -- 在原有呼叫时间上再加 15 秒
```

`api.stratagems.drop` 是快速方式：没有信标，没有等待，不能用于增援。

效果 `ignore_jammers` 让战略配备可以在禁用区域内使用。

## 敌人 {#enemies}

```lua
local bug, metres = api.enemies.nearest()
if bug then api.enemies.apply_status(bug, "flashbang_stun") end

-- 在同一任务中打更大的仗。false 把数值交还给游戏。
api.enemies.set_pressure({ cap = 24, difficulty = 15, patrols = 20, interval = 4 })
api.enemies.set_pressure({ difficulty = false })
```

- `apply_status` 可以从任何玩家的游戏作用于任何敌人。状态名称见 `api.catalog.status_templates()`。
- `info(unit)` 返回 `key`、`name`、`faction`、`boss`、`hitpoints`、`max_hitpoints` 和 `owned`。
- `set_pressure` 只属于主机。`cap` 最大为 32，并同时提高波次受限的两个上限。尸体也计入。
- `difficulty` 是每次遭遇可花费的预算。种子、可选波次和目标都不变。
- `force_wave` 一次生成 `api.enemies.waves()` 中的一个波次，忽略其延迟。
- `spawn_entity` 生成补给箱或拾取物。请使用 `api.catalog.crates()` 和 `pickups()` 中的路径，它们不含付费物品。

## 任务 {#missions}

`api.mission.objectives()` 列出 `name`、`text`、`type`、`state`、`group`、`done`、`total` 和 `position`。`state` 为 `pending`、`complete` 或 `failed`。

效果 `protect_objectives` 让车队和护送对象不会死亡。它只作用于本玩家游戏运行的单位，所以请在主机上使用。

`api.mission.mutator(name)` 在任意任务中开启游戏的一个试炼场修改项，`nil` 表示关闭。同一时间只有一个，真实的试炼场保留自己的修改项。

| 名称 | 作用 |
|---|---|
| `super_boots` | 步行速度提高 40% |
| `what_goes_around` | 对队友造成的伤害返还给射击者 |
| `orbital_support` | 每 20 秒在玩家附近投下支援战略配备 |
| `orbital_bombardments` | 每 15 秒加上呼叫时间，在玩家附近落下打击 |

## 载具 {#vehicles}

这些效果作用于玩家正在驾驶的载具，玩家离开时解除。乘客的游戏无法更改它。

| 效果 | 数值 |
|---|---|
| `vehicle_speed` | 倍率 |
| `vehicle_turn` | 倍率 |
| `vehicle_armor` | 所有角度的护甲 |
| `vehicle_god` | `true`：不受伤害 |
| `vehicle_rockets` | `true`：机甲火箭弹永不耗尽 |

`vehicle` 类别的字段会持久修改载具。最高速度在驾驶员下车再上车后生效。

## 伤害 {#damage}

```lua
api.combat.scale({ players = 0.5, enemies = 2 })
```

倍率范围为 0 到 100，在护甲之后计算，所以能挡住射击的护甲仍然能挡住。1 或 `false` 关闭这一方。游戏的计算不提供攻击者，所以倍率按受击方区分。每位玩家的游戏各自计算命中，所以大厅中的每个人都应使用相同的数值。

## 消息 {#messages}

`api.ui.hint(text, seconds)` 显示游戏自己的提示框，即使提示已关闭。`text` 是你的文字，或提示名称，例如 `"hint_alarm"`。`api.ui.ping(pos)` 在地图上的某个位置放下本玩家的标记，`api.ui.ping(nil)` 将其移除。所有玩家都能看到。

`api.lobby.players()` 列出 `peer`、`name`、以毫秒为单位的 `ping`、`host` 和 `me`。它只读取数据。队友只有在任务中才有名字。

## 重要规则 {#rules}

> [!WARNING]
> 游戏会为受保护的数值保留哈希副本，例如 `hitpoints_real`、`rounds`、`cooldown_timer`、`uses_left`、`num_grenades` 和 `extra_lives`。直接写入这些值会触发防篡改检查，使玩家断开网络直到重启。请使用 `api.game.protected` 或排队命令。`api.edits` 会拒绝这些键。

- `api.game.command(unit, component, command, data)` 从已知列表中向本玩家拥有的单位排队命令。直接向游戏排队未知命令会使游戏因脚本无法捕获的错误而停止。
- 游戏只在大于零时运行的计时器（例如空投舱的 `drop_time`）设为 0 时永远不会结束。请使用 0.01。
- 生成资源包未加载的单位会使游戏停止。`api.enemies.available(enemy)` 可以检查。
- `api.console.run` 会拒绝访问共享后端、清除存档或解锁付费内容的命令。`spawn_enemy` 只在大厅没有其他人时运行，因为它只在本玩家的游戏中加载资源包。
- 修改经验值之前，请先了解修改器为什么不做这件事：总经验值会随之后的普通结果一起上传，即使清除后也是如此。
