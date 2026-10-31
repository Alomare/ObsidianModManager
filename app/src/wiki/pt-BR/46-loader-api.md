---
title: API do loader
group: Criar mods
summary: Cada função da tabela obsidian, versão 1.
---

O Obsidian Loader inicia o script `entry` de cada mod ligado, na ordem de carregamento, uma vez, quando o jogo abre. Todo script enxerga uma tabela global chamada `obsidian`. Tudo o que um mod registra por ela roda protegido: um erro vai para o log e nunca impede o jogo de abrir.

## Hooks {#hooks}

### obsidian.hook(target, method, fn) {#obsidian-hook-target-method-fn}

Envolve uma função do jogo. `target` é uma tabela, ou o nome de uma tabela global como texto. `fn` recebe primeiro a função original, depois os argumentos da chamada:

```lua
obsidian.hook("PlayerUnitMovement", "update", function(original, self, dt)
  -- antes do código do jogo
  local result = original(self, dt)
  -- depois do código do jogo
  return result
end)
```

Quando a global ainda não existe, o hook espera e entra assim que o jogo a define. Se `fn` falhar, a original roda no lugar.

Num mod de sessão, o hook só chama a original enquanto o lobby não estiver liberado ([Escrever mods de sessão](wiki:session-mods)).

### obsidian.on_require(name, fn) {#obsidian-on-require-name-fn}

Chama `fn(module)` quando o jogo carrega o script `name`, como `"lua/settings/perk_settings"`. Use para mudar uma tabela de configuração logo depois que o jogo a monta.

### obsidian.on_frame(fn) {#obsidian-on-frame-fn}

Chama `fn` uma vez por quadro. Devolva `true` para parar as chamadas. As funções por quadro de um mod de sessão só rodam num lobby liberado.

### obsidian.after_startup(fn) {#obsidian-after-startup-fn}

Chama `fn` uma vez, depois que todos os mods iniciaram, para que mods possam trabalhar juntos sem depender da ordem de carregamento.

## Configurações e teclas {#settings-and-keys}

### obsidian.settings.get(id) {#obsidian-settings-get-id}

O valor da opção `id` deste mod: o que o jogador escolheu no app, ou o padrão ([Opções e teclas](wiki:options-and-keys)).

### obsidian.keybind(id, fn) {#obsidian-keybind-id-fn}

Chama `fn` toda vez que a tecla ligada a `id` desce. A tecla vem do app, ou do padrão no `obsidian.json`.

## Multijogador {#multiplayer}

### obsidian.session.cleared() {#obsidian-session-cleared}

`true` enquanto os mods de sessão deste jogador podem rodar. Mods de cliente quase nunca precisam.

### obsidian.session.members() {#obsidian-session-members}

Uma lista dos outros jogadores no lobby. Cada entrada tem `peer`, `obsidian` (se o jogador usa o Obsidian), `modset` e `consent`.

### obsidian.session.forfeit_xp() {#obsidian-session-forfeit-xp}

A missão em andamento não paga XP, e o jogador é avisado. Serve para um mod que termina uma missão pelo jogador, e vale até a próxima missão começar.

### obsidian.on_session(fn) {#obsidian-on-session-fn}

Chama `fn(on)` sempre que o loader liga ou desliga este mod, para que o mod possa desfazer o que outros jogadores veriam.

## Texto e logs {#text-and-logs}

### obsidian.text(key, ...) {#obsidian-text-key}

O texto `key` da pasta `locales` do mod, no idioma do jogo, com inglês como reserva. Os argumentos extras preenchem os marcadores `%s` e `%d`.

### obsidian.log(...) {#obsidian-log}

Escreve uma linha no log deste mod, em `%APPDATA%\Arrowhead\Helldivers\ObsidianModManager\logs`.

## Outros mods e mais arquivos {#other-mods}

### obsidian.module(name) {#obsidian-module-name}

Carrega outro arquivo Lua deste mod e devolve o que ele devolve. O arquivo precisa estar em `modules` no `obsidian.json`, e `name` é o caminho sem `.lua`, como `"lib/parts"`.

### obsidian.import(id) {#obsidian-import-id}

O que o script `entry` de outro mod devolveu, ou `nil` quando esse mod não está rodando. Coloque o mod em `requires`, para ele iniciar primeiro ([API Obsidian](wiki:obsidian-api)).

### obsidian.caller() {#obsidian-caller}

O id do mod cujo código está rodando, para um mod compartilhado registrar quem pediu algo.

## Menu dentro do jogo {#menu}

### obsidian.menu.add(title, build) {#obsidian-menu-add-title-build}

Adiciona uma página ao topo do menu dentro do jogo. `title` é um texto, ou uma função que o devolve. `build(page)` roda cada vez que a página abre:

```lua
obsidian.menu.add("Meu mod", function(page)
  page:header("Ajustes")
  page:toggle("Ligado", { get = function() return on end, set = function(v) on = v end })
  page:number("Força", { min = 1, max = 10, step = 1, get = get_power, set = set_power })
  page:choice("Modo", { choices = { { id = "a", label = "Primeiro" } }, get = get_mode, set = set_mode })
  page:action("Fazer", function() return "Feito" end)
  page:input("Nome", function(text) end)
  page:page("Mais", function(sub) sub:label("Mais fundo") end)
end)
```

Qualquer linha aceita `help`, um texto mostrado enquanto está selecionada, e `enabled`, uma função que devolve `false` e um motivo. Um texto devolvido por uma ação aparece como aviso. Uma ação pode chamar `page:refresh()` para montar a página de novo. Uma linha que falha mostra o erro e não conta contra o seu mod.

As páginas de um mod de sessão não aparecem, e fecham, enquanto o lobby não estiver liberado.

### obsidian.menu.open(), close(), toggle(), is_open() {#obsidian-menu-open}

Nada abre o menu sozinho, então associe uma tecla:

```lua
obsidian.keybind("open", function() obsidian.menu.toggle() end)
```

### obsidian.menu.overlay(fn) {#obsidian-menu-overlay-fn}

Chama `fn(draw, width, height)` a cada quadro, para mostrar algo na tela fora do menu. `draw.text(text, x, y, color)` e `draw.rect(x, y, w, h, color, alpha)` usam pixels a partir do canto inferior esquerdo. Cores são `{ r, g, b }`.

### obsidian.toast(text, seconds) {#obsidian-toast-text-seconds}

Mostra uma mensagem curta no canto inferior esquerdo da tela.

## Valores salvos {#storage}

### obsidian.storage.get(key, default), set(key, value), all() {#obsidian-storage}

Textos, números e booleanos que este mod guarda entre aberturas do jogo. `set` com `nil` remove a chave. O arquivo é gravado na hora, então não chame a cada quadro.

## Versão e recursos {#version-and-features}

`obsidian.version` é a versão da API, hoje `1`. Um mod que precisa de uma API mais nova define `loader_api` no `obsidian.json`, e loaders mais antigos se recusam a iniciá-lo.

`obsidian.capabilities` é uma tabela, só de leitura, do que o loader em execução oferece, uma entrada por recurso: `hook`, `on_require`, `on_frame`, `on_session`, `after_startup`, `settings`, `keybind`, `session`, `text`, `log`, `module`, `import`, `caller`, `menu`, `toast`, `storage`. Teste um recurso pelo nome antes de usar um que chegou depois:

```lua
if obsidian.capabilities.on_frame then
  obsidian.on_frame(update)
end
```

## Quando um mod falha {#when-a-mod-fails}

- Um erro na inicialização desliga o mod nesta sessão e grava o erro no `loader.log`.
- Erros em hooks e callbacks vão para o log no máximo três vezes por lugar, então uma função por quadro quebrada não inunda o log.
- Um mod que falha sem parar é desligado pelo resto da sessão.
- Se o jogo travar enquanto um mod inicia, o app aponta esse mod na próxima abertura.
