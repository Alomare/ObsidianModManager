---
title: Compartilhar um mod
group: Criar mods
summary: Empacotar uma versão, números de versão, imagens e traduções.
---

## Empacotar {#packing}

Compacte a pasta do mod em `.zip` de forma que o `obsidian.json` fique no topo do arquivo, ou dentro de uma única pasta no topo. Os jogadores soltam o `.zip` na lista de mods, e a instalação é só isso.

Deixe de fora arquivos que o mod não usa. Mantenha os caminhos do `obsidian.json` relativos à pasta do mod, com barras normais.

## Versões {#versions}

Use um número de versão como `1.4.2`:

- aumente o último número para correções;
- aumente o do meio para recursos e opções novas;
- aumente o primeiro quando o mod mudar de um jeito que os jogadores gostariam de saber antes de atualizar.

Quem importa uma versão maior mantém os valores das opções e as teclas, exceto em opções que mudaram de tipo. Mantenha os ids de opções e teclas iguais entre versões.

> [!WARNING]
> Nunca mude o `id` de um mod já lançado. O Obsidian veria um mod diferente, e os jogadores acabariam com os dois.

## Imagens {#pictures}

Adicione um `image.png` quadrado (ou JPG ou WebP, até 4 MB) e indique no `obsidian.json` com `"image": "image.png"`. 512 por 512 pixels é mais que suficiente.

## Traduções {#translations}

- Ponha o nome, a descrição e os rótulos das opções em todos os idiomas que puder, em `name`, `description` e `label`.
- Ponha o texto que o mod mostra no jogo em `locales/<idioma>.json`.
- Inglês é sempre a reserva, então uma tradução que falta aparece em inglês em vez de em branco.

## Antes de lançar {#before-you-release}

1. Importe o próprio `.zip` no Obsidian, não a pasta, para testar o que os jogadores vão receber.
2. Aplique, jogue uma missão e leia o log do seu mod.
3. Num mod de sessão, teste com um amigo que não o usa: o seu mod deve desligar ([Escrever mods de sessão](wiki:session-mods)).
4. Escreva na descrição o que o mod muda e se outros jogadores percebem.
