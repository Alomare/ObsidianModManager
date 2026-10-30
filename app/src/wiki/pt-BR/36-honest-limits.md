---
title: O que as proteções não fazem
group: Jogar online
summary: Contra o que o Obsidian protege, e o que nenhum gerenciador de mods consegue impedir.
---

As proteções impedem que mods bem-comportados prejudiquem outros jogadores por acidente, e fazem da configuração segura o padrão. Elas não são um anti-cheat.

## O que elas cobrem {#what-they-cover}

- Um jogador sem mods não encontra lobbies com mods no matchmaking.
- Mods de sessão que usam o loader se desligam sozinhos num lobby que não concordou com eles.
- Missões jogadas com conteúdo de sessão não são enviadas para a Guerra Galáctica.
- Um mod que falha sem parar é desligado, e um travamento na abertura do jogo aponta o mod que estava iniciando.

## O que elas não cobrem {#what-they-can-t-cover}

Tudo roda no seu próprio PC, então quem quiser trapacear pode escrever um script que ignora o loader por completo. Nenhum gerenciador de mods consegue impedir isso.

Um mod também pode quebrar as regras por engano ou de propósito:

- dizendo que é de cliente enquanto muda o jogo compartilhado;
- mudando o código do jogo diretamente, sem os hooks do loader, e aí o loader não consegue desligar a mudança.

Quando um mod inicia, o loader compara o jogo antes e depois e grava no `loader.log` uma linha por mod com o que ele adicionou ou substituiu fora do loader. É ali que você olha quando um mod se comporta mal.

> [!TIP]
> Instale mods de autores e lugares em que você confia, e leia o que o mod diz que faz. Se um mod de cliente muda coisas que outros jogadores veem, avise o autor ou o pessoal no Discord.
