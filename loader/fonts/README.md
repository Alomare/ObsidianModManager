# Fonts

The in-game menu's fonts, baked for the game by `tools/bake_font.py`.

| File | Made from | License |
|---|---|---|
| `heading.*` | Saira Semi Condensed SemiBold, by Omnibus-Type | [OFL-Saira.txt](OFL-Saira.txt) |
| `body.*` | Barlow Medium, by Jeremy Tribby | [OFL-Barlow.txt](OFL-Barlow.txt) |

Both come from [Google Fonts](https://github.com/google/fonts), under the SIL Open Font License 1.1. "Saira" is a Reserved Font Name and a bake counts as a modified version, so the files here go by their role instead.

To bake them again, from the repository root:

```
pip install pillow uharfbuzz
python tools/bake_font.py --out loader/fonts --base obsidian/fonts heading=SairaSemiCondensed-SemiBold.ttf body=Barlow-Medium.ttf
```
