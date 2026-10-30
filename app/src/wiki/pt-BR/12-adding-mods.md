---
title: Adicionar e atualizar mods
group: Primeiros passos
summary: Importar um mod de um .zip ou de uma pasta, atualizar e remover.
---

## Importar {#importing}

Arraste uma pasta de mod ou um arquivo `.zip` para a lista de mods na aba [Mods](app:mods), ou clique no **+** verde ao lado da busca e escolha um. Dá para importar vários de uma vez, e uma notificação diz o que aconteceu com cada um.

O Obsidian copia o mod para a biblioteca, então você pode apagar o download depois. Importar não muda nada no jogo até você aplicar.

### Mods feitos para o Obsidian {#mods-made-for-obsidian}

Um mod feito para o Obsidian tem um arquivo `obsidian.json` no topo da pasta ou do arquivo compactado. O Obsidian lê dele o nome, a versão, as opções e as teclas, e mostra tudo no painel da direita.

### Mods mais antigos {#older-mods}

A maioria dos mods de HD1 que circulam hoje substitui bundles inteiros do jogo, com arquivos de nomes como `9e13b2414b41b842`. O Obsidian importa esses também. Ele compara cada bundle do mod com o do seu jogo e guarda só os recursos que o mod de fato altera, então dois mods antigos que mexem em coisas diferentes agora rodam juntos.

Mods antigos entram com o escopo **sessão**, porque o Obsidian não tem como saber o que eles mudam num jogo compartilhado ([Escopos](wiki:scopes)). Eles também não podem ser desligados no meio de uma missão.

> [!NOTE]
> Para comparar os bundles, o jogo precisa estar na versão original que o Obsidian conhece. Use Limpar antes se outra ferramenta mexeu nos arquivos do jogo.

## Atualizar {#updating}

Importe a versão nova do mesmo jeito. Um mod com o mesmo id substitui o que está na biblioteca, e a notificação mostra a versão antiga e a nova. Os valores das opções e as teclas continuam, exceto em opções cujo tipo o autor mudou.

## Remover {#removing}

Clique com o botão direito num mod e escolha **Remover**, ou marque vários mods e use **Remover** na barra acima da lista. Os mods que vêm com o Obsidian não podem ser removidos; eles ficam na pasta Obsidian, que é travada, e continuam desligados até você ligar.

## Imagens {#pictures}

Um mod pode trazer uma imagem quadrada. Para usar uma sua, abra o mod no painel da direita e clique na imagem. Perfis aceitam imagem do mesmo jeito.
