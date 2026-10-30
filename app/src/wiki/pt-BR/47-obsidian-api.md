---
title: API Obsidian (Obsidian API)
group: Criar mods
summary: "O runtime para mods: os dados do jogo por nome, mudanças verificadas e ações prontas."
---

O Obsidian API é um mod sobre o qual outros mods são construídos. Ele sabe onde as coisas ficam no jogo, faz mudanças do jeito que o jogo aceita e as desfaz quando precisa. É assim que o Obsidian Trainer funciona, e o trainer não usa nada que você não possa usar.

## Como usar {#using-it}

Coloque-o em `requires`. O Obsidian liga o API junto com o seu mod e o inicia primeiro:

```json
"scope": "session",
"entry": "main.lua",
"requires": ["obsidian.api"]
```

Depois peça por ele:

```lua
local api = obsidian.import("obsidian.api")

obsidian.keybind("panic", function()
  api.player.heal()
  api.enemies.kill_near(20)
end)
```

As ações respondem `true`, ou `false` e um motivo curto, como `"host_only"`, `"no_avatar"` ou `"not_in_mission"`.

## Mudar dados do jogo {#edits}

`api.edits` muda tabelas de configuração e registra o que mudou, quem mudou e como era antes.

```lua
-- Dobra o dano do fuzil de assalto, com melhorias.
local ok, why = api.edits.set_unit("equipment/wep_assaultrifle_01", "weapon_info.power", 150)

-- Um valor em qualquer tabela que o jogo lê.
local s = api.catalog.stratagem("stratagem_resupply")
api.edits.set_table("Resupply", s, "cooldown_time", 30)
```

- Tipos e limites são verificados, e `opts` aceita `min` e `max`.
- As tabelas continuam as mesmas, porque unidades vivas guardam referências a elas.
- Uma arma tem uma cópia das configurações para cada melhoria, e a edição alcança todas.
- `api.edits.list()`, `revert(id)` e `revert_all()` mostram e desfazem mudanças.
- Quando o lobby deixa de estar liberado, cada edição é desfeita. Quando libera de novo, elas voltam.

Os campos editáveis, com limites e quando cada um vale, estão em `api.catalog.fields(family)`. Alguns números valem na hora e outros no próximo surgimento. `api.gear.refresh()` leva os guardados para as armas em jogo.

## Efeitos {#effects}

Um efeito continua ligado entre reaparições e missões. O jogo reconstrói boa parte do estado nesses momentos, então o runtime aplica de novo os efeitos ativos.

```lua
api.effects.set("god", true)
api.effects.set("speed", 2)     -- um valor, false para desligar
api.effects.is_on("god")
```

Os seus:

```lua
api.effects.define({
  id = "mymod.low_gravity",
  apply = function(ctx, value) end,            -- ao ligar, e de novo após reaparecer ou nova missão
  frame = function(ctx, value, dt) end,        -- a cada quadro enquanto ligado
  remove = function(ctx, value) end,           -- ao desligar
})
```

`ctx` tem `state`, `name`, `record` e `unit`. Todos podem ser nil.

## O que há na API {#contents}

| Tabela | Para |
|---|---|
| `api.game` | O estado atual, o jogador local, `is_host()` e escritas seguras |
| `api.catalog` | Armas, estratagemas, vantagens, inimigos e grupos por nome, sem itens pagos que o jogador não tem |
| `api.player` | `heal`, `respawn`, `teleport`, `set_cosmetic` e mais |
| `api.gear` | `refill`, `give_weapon`, `give_perk`, `refresh` |
| `api.stratagems` | `reset_cooldowns`, `refill_uses`, `give`, `drop` |
| `api.enemies` | `spawn`, `spawn_group`, `kill_all`, `list` |
| `api.mission` | `finish_objectives`, `win`, `abort`, `practice` |
| `api.world` | `cursor`, `ahead`, `explode` |
| `api.progress` | `set_samples`, `unlock_items`, `upgrade_all` |
| `api.console` | `run(line)`, `commands()` |

## Regras importantes {#rules}

> [!WARNING]
> O jogo guarda cópias com hash de valores protegidos, como `hitpoints_real`, `rounds`, `cooldown_timer`, `uses_left`, `num_grenades` e `extra_lives`. Escrever um deles diretamente dispara a verificação anti-adulteração, que corta a conexão do jogador até reiniciar. Use `api.game.protected` ou um comando na fila. `api.edits` recusa essas chaves.

- `api.game.command(unit, component, command, data)` põe na fila um comando de uma lista conhecida, numa unidade deste jogador. Um comando desconhecido direto no jogo o para com um erro que nenhum script captura.
- Um temporizador que o jogo só roda acima de zero, como o `drop_time` de um hellpod, nunca termina em 0. Use 0.01.
- Criar uma unidade cujo pacote não está carregado para o jogo. `api.enemies.available(enemy)` verifica.
- `api.console.run` recusa comandos que alcançam o backend compartilhado, apagam saves ou liberam conteúdo pago.
- Só mude XP depois de ler por que o trainer não muda: o total vai junto com os próximos resultados normais, depois de qualquer limpeza.
