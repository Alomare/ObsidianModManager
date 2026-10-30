---
title: 替换游戏文件
group: 制作模组
summary: 按名称修改游戏脚本和其他资源，无需分发整个资源包。
---

除了运行脚本，模组还可以通过 `resources` 列表替换游戏资源或添加新资源。Obsidian 在部署时把它们放进补丁，并逐个资源处理与其他模组的冲突。

## 修改过的游戏脚本 {#a-changed-game-script}

把要修改的游戏脚本复制到模组文件夹，编辑后列出：

```json
"resources": [
  { "type": "lua", "name": "lua/settings/perk_settings", "source": "res/perk_settings.lua" }
]
```

- `type` 和 `name` 是资源在游戏中的路径。
- `source` 是模组文件夹中的纯 Lua 代码，Obsidian 在部署时编译。
- 对于已经编译好的 LuaJIT 2.0 字节码文件，可以用 `bytecode` 代替 `source`。Obsidian 会检查文件头，拒绝其他格式。

> [!TIP]
> 挂钩只修改一个函数，脚本其余部分仍由游戏负责，因此两个模组可以修改同一脚本而不冲突。修改代码时优先使用[挂钩](wiki:loader-api#hooks)，只在必要时替换整个脚本。

## 其他资源 {#other-resources}

纹理、单位、材质等其他类型使用 `data`，即游戏存储的原始资源：

```json
{ "type": "texture", "name": "units/foo/bar", "data": "res/bar.texture" }
```

导入时转换的旧式模组使用这种形式。从零制作这类文件需要 HD1 目前还没有的工具。

## 字段 {#fields}

| 字段 | 说明 |
|---|---|
| `type` | 资源类型，例如 `lua` 或 `texture`；名称未知的类型用 `#` 加 16 位十六进制数 |
| `name` | 资源名称，例如 `lua/settings/perk_settings`，或 `#` 加 16 位十六进制数 |
| `source` | 要编译的 Lua 源代码 |
| `bytecode` | 已编译的 LuaJIT 2.0 字节码 |
| `data` | 任何其他类型的原始资源 |
| `bundle` | 资源所属的资源包，16 位十六进制数。只有游戏中尚不存在的资源才需要 |
| `flags` | 资源包为每个资源保存的一个值；除非转换器设置了它，否则省略 |
| `when` | 只有这些选项取得对应值时才使用该资源（[选项和按键](wiki:options-and-keys#options-that-pick-files)） |

## 限制 {#limits}

大型纹理、声音和视频把数据保存在单独的 `.stream` 文件中。Obsidian 目前拒绝这类资源。

被替换的资源是静态的：无法在游戏中途关闭。在会话模组中，资源用于游戏启动时读取的数据，行为则用挂钩实现。
