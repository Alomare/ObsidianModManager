---
title: Adicionar e atualizar mods
group: Primeiros passos
summary: Importar um mod de um .zip ou de uma pasta, atualizar e remover.
---

## Importar {#importing}

Arraste uma pasta de mod ou um arquivo `.zip` para a lista de mods na aba [Mods](app:mods), ou clique no **+** verde ao lado de Criar pasta e escolha um. Dá para importar vários de uma vez, e uma notificação diz o que aconteceu com cada um.

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

### Pelo GitHub {#from-github}

Um mod pode indicar o repositório dele no GitHub. Quando algum indica, aparece um botão com duas setas ao lado do **+** verde na aba [Mods](app:mods). Ele pergunta ao GitHub se há versões novas, e cada mod que tiver uma mostra um botão **Atualizar para** ao lado da versão. Clique nele e depois aplique ao jogo.

O Obsidian só fala com o GitHub quando você clica, e só instala uma versão mais alta do mesmo mod.

## Remover {#removing}

Clique com o botão direito num mod e escolha **Remover**, ou marque vários mods e use **Remover** na barra acima da lista.

## Pacote inicial {#starter-pack}

Três mods vêm com o Obsidian, na pasta **STARTER PACK**, no topo da lista: Obsidian API, [Obsidian Trainer](wiki:trainer) e Obsidian Qualidade de Vida. O Qualidade de Vida começa ligado, só com as correções para tela larga ativas. Os outros dois ficam desligados até você ligar.

Eles são mods como quaisquer outros. Você pode mover ou remover os mods, renomear ou apagar a pasta, e atualizar os mods pelo GitHub. Para deixar tudo como era, use **Restaurar pacote inicial** em [Configurações](app:settings). Isso traz de volta os mods apagados e a pasta, e volta as configurações deles ao padrão no perfil ativo.

## Dependências {#dependencies}

Alguns mods precisam de outros para funcionar. A aba **Dependências**, no painel à direita, mostra do que um mod precisa e quais mods precisam dele. Ligar um mod liga o que ele precisa, e desligar desliga os mods que precisam dele.

Se um mod precisa de algo que não está na sua biblioteca, a aba avisa, e o mod não liga até você adicionar o que falta.

## Imagens {#pictures}

Um mod pode trazer uma imagem quadrada. Para usar uma sua, abra o mod no painel da direita e clique na imagem. Perfis aceitam imagem do mesmo jeito.
