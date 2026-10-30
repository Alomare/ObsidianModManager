---
title: Escrever mods de sessão
group: Criar mods
summary: Como mudar o jogo compartilhado de um jeito que as proteções continuem funcionando para você.
---

Um mod de sessão muda algo que outros jogadores percebem: dano, inimigos, spawns, missões. O loader decide quando um mod assim pode rodar ([Jogar online](wiki:multiplayer)) e liga e desliga o mod conforme os jogadores entram e saem. A sua parte é fazer cada mudança pelo loader, para que ela possa ser desligada.

## Defina o escopo {#set-the-scope}

```json
"scope": "session"
```

Deixar o campo de fora tem o mesmo efeito. Só use `client` quando nada do que o mod faz chega aos outros jogadores.

## Mude o jogo por hooks {#change-the-game-through-hooks}

Os hooks de um mod de sessão chamam o código original do jogo sozinhos enquanto o lobby não está liberado. Um mod feito só de hooks não precisa de nenhum código extra para ser seguro:

```lua
-- Dobra o dano de cada tiro, só em lobbies liberados.
obsidian.hook("Damage", "apply", function(original, target, amount, ...)
  return original(target, amount * 2, ...)
end)
```

O mesmo vale para funções `on_frame` e teclas: num lobby que não está liberado, elas não rodam.

## Desfaça o que fica para trás {#undo-what-stays-behind}

Algumas mudanças duram mais que a chamada que as fez: um valor gravado numa tabela de configuração, uma unidade que você criou. Escute a troca e ponha as coisas de volta:

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

## O que evitar {#things-to-avoid}

- **Substituir globais diretamente.** `SomeTable.func = mine` continua rodando em qualquer lobby, porque o loader não consegue desligar. O loader lista mudanças assim no log, para cada mod, na inicialização.
- **Substituir scripts do jogo por recursos para mudar a jogabilidade.** Um script substituído também não desliga na hora. O Obsidian aceita, mas num lobby com um jogador que não concordou, a mudança continua no seu jogo enquanto o resto dos seus mods de sessão desliga.
- **Mandar mensagens de rede próprias** para outros jogadores fora do código do próprio jogo.

> [!NOTE]
> Mudar o seu próprio progresso, como XP ou desbloqueios, é permitido. O Obsidian faz backup do save antes de cada aplicação e não desfaz essas mudanças.

## Opções em mods de sessão {#options-in-session-mods}

Todo valor de opção conta quando o Obsidian compara os conjuntos dos jogadores, a não ser que você marque a opção com `"scope": "client"`. Marque as opções que só mudam o que este jogador vê ([Opções e teclas](wiki:options-and-keys#personal-options-in-session-mods)).
