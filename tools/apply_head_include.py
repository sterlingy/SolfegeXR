"""Copy web/page_head.html into the Web export preset's html/head_include.

Godot stores the head include as one quoted string in export_presets.cfg;
keeping the HTML in its own file is easier to read and edit.
Run after editing web/page_head.html:  python tools/apply_head_include.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
html = open(os.path.join(ROOT, "web", "page_head.html"), encoding="utf-8").read()
# Drop the explanatory HTML comment; keep the markup on as few lines as possible.
html = re.sub(r"<!--.*?-->\s*", "", html, flags=re.S).strip()
value = html.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\n")
cfg_path = os.path.join(ROOT, "export_presets.cfg")
cfg = open(cfg_path, encoding="utf-8").read()
# The stored value spans lines and escapes its quotes (\"), so match up to the closing quote.
cfg, n = re.subn(r'^html/head_include="(?:[^"\\]|\\.)*"', lambda m: 'html/head_include="%s"' % value, cfg, flags=re.M)
assert n == 1, "html/head_include not found"
open(cfg_path, "w", encoding="utf-8", newline="\n").write(cfg)
print("head_include updated (%d chars)" % len(value))
