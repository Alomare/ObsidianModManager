---
title: O arquivo obsidian.json
group: Criar mods
summary: Cada campo do arquivo que descreve um mod.
---

O `obsidian.json` fica no topo da pasta do mod, ou no topo do `.zip`. O Obsidian confere o arquivo ao importar e diz qual campo está errado quando algo não encaixa.

## Um exemplo completo {#a-full-example}

```json
{
  "obsidian": 1,
  "id": "seunome.camera-melhor",
  "version": "1.2.0",
  "name": { "en": "Better Camera", "pt-BR": "Câmera Melhor" },
  "description": { "en": "A closer camera with a toggle key.", "pt-BR": "Uma câmera mais próxima, com tecla para ligar e desligar." },
  "authors": ["Seu nome"],
  "image": "image.png",
  "scope": "client",
  "entry": "main.lua",
  "loader_api": 1,
  "options": [
    { "id": "distance", "type": "number", "default": 5, "min": 1, "max": 12, "step": 0.5,
      "label": { "en": "Camera distance", "pt-BR": "Distância da câmera" } }
  ],
  "keybinds": [
    { "id": "toggle", "default": "f8", "label": { "en": "Toggle the camera", "pt-BR": "Ligar ou desligar a câmera" } }
  ],
  "resources": []
}
```

## Campos {#fields}

| Campo | Obrigatório | O que é |
|---|---|---|
| `obsidian` | sim | A versão do formato. Por enquanto, sempre `1`. |
| `id` | sim | Id permanente: de 1 a 64 caracteres entre `a-z`, `0-9`, `.`, `_` e `-`, começando por letra ou dígito. Use `seunome.nome-do-mod`. |
| `version` | sim | Um número de versão como `1.2.0` (versionamento semântico). Uma versão maior substitui uma menor ao importar. |
| `name` | sim | O nome do mod por idioma. Inglês (`en`) é obrigatório. |
| `description` | não | Uma ou duas frases por idioma, mostradas abaixo do nome. |
| `authors` | não | Uma lista de nomes. |
| `image` | não | Uma imagem quadrada PNG, JPG ou WebP dentro da pasta do mod, até 4 MB. |
| `source` | não | O endereço do mod, mostrado nos detalhes dele. Um repositório do GitHub como `https://github.com/voce/mod` também permite que os jogadores atualizem o mod pelo app ([Compartilhar um mod](wiki:sharing#updates)). |
| `scope` | não | `client` ou `session` ([Escopos](wiki:scopes)). Sem o campo, ou com valor desconhecido, conta como `session`. |
| `entry` | não | O script Lua que o loader inicia. Mods que só substituem arquivos do jogo não usam. |
| `loader_api` | não | A versão da [API do loader](wiki:loader-api) de que o mod precisa. `1` se ficar de fora. |
| `options` | não | Configurações que os jogadores mudam no app ([Opções e teclas](wiki:options-and-keys)). |
| `keybinds` | não | Teclas que os jogadores podem trocar no app. |
| `resources` | não | Arquivos do jogo que o mod substitui ou adiciona ([Substituir arquivos do jogo](wiki:resources)). |

## Texto em vários idiomas {#text-in-several-languages}

Todo campo que os jogadores leem é um objeto com uma entrada por idioma: `en`, `pt-BR` e `zh-CN` para o app, e `en`, `fr`, `es` e `pt-BR` para o texto que o jogo mostra. Inglês é sempre obrigatório e aparece no lugar de qualquer idioma que você deixar de fora.

O texto que o mod mostra no jogo vai numa pasta `locales` ao lado do `obsidian.json`, um arquivo por idioma (`locales/en.json`, `locales/pt-BR.json` e assim por diante), cada um um objeto simples de chaves e textos. O mod lê com `obsidian.text`.

## Campos que o Obsidian não conhece {#fields-obsidian-doesn-t-know}

Campos desconhecidos são guardados e ignorados, então um mod escrito para uma versão futura do Obsidian ainda importa.
