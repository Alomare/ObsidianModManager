"""Adds app.* keys to the app catalogs (en, pt-BR, zh-CN). New keys get the English text in the
other catalogs until translated; existing translations are kept. Usage: python tools/add-app-keys.py keys.json"""
import json, sys
from pathlib import Path

LOCALES = Path(__file__).resolve().parent.parent / "locales"
APP_LANGUAGES = ["en", "pt-BR", "zh-CN"]

new = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for lang in APP_LANGUAGES:
    path = LOCALES / f"{lang}.json"
    cat = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    for k, v in new.items():
        assert k.startswith("app."), k
        if lang == "en" or k not in cat:
            cat[k] = v
    path.write_text(json.dumps(dict(sorted(cat.items())), ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
print(f"{len(new)} keys")
