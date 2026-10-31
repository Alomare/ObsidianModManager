---
title: API Obsidian (Obsidian API)
group: Criar mods
summary: "Uma biblioteca para mods: os dados do jogo por nome, mudanças verificadas e ações prontas."
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
- `opts.also` em `set_table` lista mais caminhos que recebem o mesmo valor, como uma só mudança.
- Quando o lobby deixa de estar liberado, cada edição é desfeita. Quando libera de novo, elas voltam.

Os níveis de melhoria de um estratagema podem definir um campo por conta própria, então mudar a base para nesses níveis. `api.stratagems.edit` muda todos os níveis de uma vez, com os limites do campo:

```lua
api.stratagems.edit("stratagem_railcannon_strike", "cooldown_time", 30)
```

Os campos editáveis, com limites e quando cada um vale, estão em `api.catalog.fields(family)`. `api.catalog.families_of(settings)` diz quais famílias uma tabela de configuração tem. Alguns números valem na hora e outros no próximo surgimento. `api.gear.refresh()` leva os guardados para as armas em jogo.

## Efeitos {#effects}

Um efeito continua ligado entre reaparições e missões. O jogo reconstrói boa parte do estado nesses momentos, então a biblioteca aplica de novo os efeitos ativos.

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

`ctx` tem `state`, `name`, `record` e `unit`. Todos podem ser nil. Dê um `remove` a cada efeito, para ele sair quando o lobby deixar de estar liberado.

## Eventos {#events}

`api.events.on(name, fn)` chama a sua função quando o jogo avisa que algo aconteceu, então você não precisa olhar a cada quadro.

```lua
local kills = 0

api.events.on("on_enemy_killed", function(unit, attacker, owner)
  kills = kills + 1
  if kills == 50 then api.ui.hint("Cinquenta abatidos") end
end)
```

| Evento | Sua função recebe | Quando |
|---|---|---|
| `on_enemy_killed` | `unit`, `attacker`, `owner`, `damage_type` | Este jogador abateu um inimigo. `damage_type` só vem quando este jogo calculou o golpe |
| `on_enemy_spawned` | `unit`, `enemy_name` | Um inimigo surgiu, no jogo de cada jogador |
| `on_player_death` | `unit` | Um jogador morreu, no jogo de cada jogador |
| `on_objective_completed` | nada | Um objetivo foi concluído |
| `on_stratagem_activated` | `peer`, `stratagem`, `position`, `unit` | A contagem de um estratagema terminou, no jogo de cada jogador |
| `on_avatar_extract` | `unit`, `shuttle` | Este jogador embarcou na nave de extração |

- Uma função que falha conta contra o seu mod, e as outras continuam rodando.
- Nada chega enquanto o lobby não estiver liberado.
- `position` dura um quadro. Copie `x`, `y` e `z` para guardar.
- `api.events.off(name, fn)` cancela uma.

## O que há na API {#contents}

| Tabela | Para |
|---|---|
| `api.game` | O estado atual, o jogador local, `is_host()` e escritas seguras |
| `api.catalog` | Armas, estratagemas, vantagens, inimigos e grupos por nome, sem itens pagos que o jogador não tem. Também `backpacks`, `crates`, `pickups`, `vehicles`, `by_subtype(name)` e `max_upgrade(path)` |
| `api.player` | `heal`, `respawn`, `teleport`, `set_cosmetic` e mais |
| `api.gear` | `refill`, `give_weapon(slot, path, upgrade)`, `give_backpack(path, upgrade)`, `give_perk`, `remove_perk`, `refresh` |
| `api.stratagems` | `reset_cooldowns`, `refill_uses`, `give`, `drop`, `call(name, pos, delay)`, `edit(name, field, value)` |
| `api.enemies` | `spawn`, `spawn_group`, `spawn_entity(path, pos)`, `kill_all`, `kill(unit)`, `list`, `info(unit)`, `nearest(pos)`, `apply_status(unit, template)`, `stun_near(radius)`, `set_pressure(t)`, `waves()`, `force_wave(name, pos)` |
| `api.mission` | `finish_objectives`, `objectives()`, `mutator(name)`, `win`, `abort`, `practice` |
| `api.vehicles` | `current()`, `driving()`, `repair()`, `refill()` |
| `api.combat` | `scale{ players, enemies }` |
| `api.events` | `on(name, fn)`, `off(name, fn)` |
| `api.ui` | `hint(text, seconds)`, `ping(pos)` |
| `api.lobby` | `players()` |
| `api.world` | `cursor`, `ahead`, `explode` |
| `api.progress` | `set_samples`, `unlock_items`, `upgrade_all` |
| `api.console` | `run(line)`, `commands()` |

## Equipamento {#gear}

`upgrade` em `give_weapon` e `give_backpack` vai de 0 a 15. Deixe de fora para usar o que o jogador tem para aquele item. `api.catalog.max_upgrade(path)` dá o maior valor.

`give_backpack` só aceita caminhos de `api.catalog.backpacks()`, porque o jogo lê configurações que outros caminhos não têm, num ponto em que nada captura o erro. A mochila antiga cai no chão, como a arma antiga.

`give_perk` troca vantagens do jeito que o console do jogo troca. A mira laser responde `"alone_only"` com outros jogadores no lobby, porque o jogo deles a rodaria sem preparo.

## Estratagemas {#stratagems}

`api.stratagems.call` coloca um sinalizador real, como o jogo faz nas próprias entregas programadas. Tem som e contagem, as patrulhas ouvem, e funciona para Reforço. Não gasta recarga nem uso, e chama no nível que o jogador tem.

```lua
api.stratagems.call("stratagem_resupply", api.world.cursor(), 15)   -- 15 s além da própria chamada
```

`api.stratagems.drop` é o rápido: sem sinalizador, sem espera e sem Reforço.

O efeito `ignore_jammers` deixa estratagemas funcionarem dentro de zonas sem estratagemas.

## Inimigos {#enemies}

```lua
local bug, metres = api.enemies.nearest()
if bug then api.enemies.apply_status(bug, "flashbang_stun") end

-- Lutas maiores na mesma missão. false devolve um número ao jogo.
api.enemies.set_pressure({ cap = 24, difficulty = 15, patrols = 20, interval = 4 })
api.enemies.set_pressure({ difficulty = false })
```

- `apply_status` funciona em qualquer inimigo, no jogo de qualquer jogador. Os nomes de status estão em `api.catalog.status_templates()`.
- `info(unit)` dá `key`, `name`, `faction`, `boss`, `hitpoints`, `max_hitpoints` e `owned`.
- `set_pressure` é do host. `cap` vai até 32 e levanta os dois limites em que as ondas param. Cadáveres contam.
- `difficulty` é quanto cada encontro pode gastar. A semente, as ondas disponíveis e os objetivos continuam iguais.
- `force_wave` cria uma onda de `api.enemies.waves()` de uma vez, ignorando os atrasos dela.
- `spawn_entity` cria uma caixa ou um item no chão. Use caminhos de `api.catalog.crates()` e `pickups()`, que deixam de fora itens pagos.

## Missões {#missions}

`api.mission.objectives()` lista `name`, `text`, `type`, `state`, `group`, `done`, `total` e `position`. `state` é `pending`, `complete` ou `failed`.

O efeito `protect_objectives` mantém comboios e pessoas escoltadas vivos. Ele alcança o que roda no jogo deste jogador, então use no host.

`api.mission.mutator(name)` liga um dos modificadores do campo de provas do jogo em qualquer missão, e `nil` desliga. É um por vez, e um campo de provas real mantém o dele.

| Nome | O que faz |
|---|---|
| `super_boots` | 40% mais rápido a pé |
| `what_goes_around` | Dano em um colega volta para quem atirou |
| `orbital_support` | Estratagemas de apoio caem perto de um jogador a cada 20 s |
| `orbital_bombardments` | Ataques caem perto de um jogador a cada 15 s, mais a chamada deles |

## Veículos {#vehicles}

Estes efeitos alcançam o veículo que o jogador está dirigindo e o soltam quando ele sai. O jogo de um passageiro não consegue mudá-lo.

| Efeito | Valor |
|---|---|
| `vehicle_speed` | Um multiplicador |
| `vehicle_turn` | Um multiplicador |
| `vehicle_armor` | Armadura em todos os ângulos |
| `vehicle_god` | `true`: sem dano |
| `vehicle_rockets` | `true`: os foguetes do exotraje nunca acabam |

Os campos da família `vehicle` mudam um veículo de vez. A velocidade máxima vale quando o motorista sai e entra de novo.

## Dano {#damage}

```lua
api.combat.scale({ players = 0.5, enemies = 2 })
```

Um multiplicador de 0 a 100, depois da armadura, então a armadura que para um tiro continua parando. 1 ou `false` desliga um lado. O jogo não passa quem atacou para as contas, então a escala vale por quem leva o golpe. O jogo de cada jogador calcula os próprios golpes, então todos no lobby devem usar os mesmos números.

## Mensagens {#messages}

`api.ui.hint(text, seconds)` mostra a caixa de dicas do próprio jogo, mesmo com as dicas desligadas. `text` são as suas palavras ou o nome de uma dica, como `"hint_alarm"`. `api.ui.ping(pos)` coloca a marca deste jogador no mapa em uma posição, e `api.ui.ping(nil)` tira. Todos os jogadores veem.

`api.lobby.players()` lista `peer`, `name`, `ping` em milissegundos, `host` e `me`. Só lê. Um colega tem nome durante uma missão.

## Regras importantes {#rules}

> [!WARNING]
> O jogo guarda cópias com hash de valores protegidos, como `hitpoints_real`, `rounds`, `cooldown_timer`, `uses_left`, `num_grenades` e `extra_lives`. Escrever um deles diretamente dispara a verificação anti-adulteração, que corta a conexão do jogador até reiniciar. Use `api.game.protected` ou um comando na fila. `api.edits` recusa essas chaves.

- `api.game.command(unit, component, command, data)` põe na fila um comando de uma lista conhecida, numa unidade deste jogador. Um comando desconhecido direto no jogo o para com um erro que nenhum script captura.
- Um temporizador que o jogo só roda acima de zero, como o `drop_time` de um hellpod, nunca termina em 0. Use 0.01.
- Criar uma unidade cujo pacote não está carregado para o jogo. `api.enemies.available(enemy)` verifica.
- `api.console.run` recusa comandos que alcançam o backend compartilhado, apagam saves ou liberam conteúdo pago. `spawn_enemy` só roda sem mais ninguém no lobby, porque carrega um pacote apenas no jogo deste jogador.
- Só mude XP depois de ler por que o trainer não muda: o total vai junto com os próximos resultados normais, depois de qualquer limpeza.
