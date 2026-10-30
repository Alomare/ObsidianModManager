---
title: Aplicar e limpar
group: Primeiros passos
summary: O que acontece quando você aplica, o que Limpar remove e por que o Obsidian às vezes recusa.
---

## Aplicar {#deploy}

Aplicar coloca no jogo os mods ligados do perfil ativo. O botão fica verde quando há mudanças que ainda não estão no jogo. O jogo precisa estar fechado.

Cada aplicação segue estes passos:

1. Confere se o jogo é a versão que o Obsidian conhece (veja abaixo).
2. Faz backup da pasta de saves. Os últimos 10 backups ficam guardados.
3. Decide qual mod vence cada recurso, seguindo a ordem de carregamento.
4. Compila o Lua de cada mod, e do loader, em código que o jogo consegue rodar.
5. Grava um patch por bundle do jogo e a lista de mods aplicados para o loader.

**Jogar** aplica antes quando há mudanças esperando e depois abre o jogo.

## Limpar {#purge}

Limpar apaga todos os arquivos que o Obsidian gravou e confere que nenhum ficou para trás. O jogo volta a ser o original. A biblioteca e os perfis continuam; aplique de novo para trazer os mods de volta.

> [!NOTE]
> Patches que outra ferramenta ou uma pessoa colocou na pasta do jogo aparecem na lista, mas nunca são apagados sem perguntar. Os patches do Obsidian ficam acima deles.

## A verificação de versão {#the-build-check}

O Obsidian só aplica na versão Steam do HELLDIVERS em que foi testado. Se os arquivos do jogo forem diferentes, a aplicação para e a barra de cima avisa que a versão é desconhecida. O loader confere de novo toda vez que o jogo abre e mantém todos os mods desligados numa versão que não conhece.

O HD1 não recebe atualização desde 2020, então isso normalmente pega arquivos alterados à mão ou por outra ferramenta de mods. Verifique a integridade dos arquivos na Steam para resolver.

## Saves {#saves}

O Obsidian nunca edita o seu save. Mods de sessão podem mudar o seu próprio progresso (XP, desbloqueios), e o Obsidian não desfaz isso; por isso cada aplicação faz um backup antes. Os backups ficam na pasta `backups`, dentro da pasta de dados do app.
