#!/usr/bin/env python3
"""Injects custom.css into VS Code's workbench.html, replacing any prior
injection. Reimplements what be5invis.vscode-custom-css's "Enable Custom CSS
and JS" command does, so install.sh can do it non-interactively on every run.
"""
import re
import sys

START = "<!-- !! VSCODE-CUSTOM-CSS-START !! -->"
END = "<!-- !! VSCODE-CUSTOM-CSS-END !! -->"

html_path, css_path = sys.argv[1], sys.argv[2]

with open(html_path, "r", encoding="utf-8") as f:
    html = f.read()

# Strip any previously injected block (ours or the extension's).
html = re.sub(
    re.escape(START) + r"[\s\S]*?" + re.escape(END) + r"\n*",
    "",
    html,
)
html = re.sub(r"<!-- !! VSCODE-CUSTOM-CSS-SESSION-ID [\w-]+ !! -->\n*", "", html)

# Allow inline <style> to run.
html = re.sub(r'<meta\s+http-equiv="Content-Security-Policy"[\s\S]*?/>', "", html)

with open(css_path, "r", encoding="utf-8") as f:
    css = f.read()

inject = f"{START}\n<style>{css}</style>\n{END}\n"
html = html.replace("</head>", inject + "</head>")

with open(html_path, "w", encoding="utf-8") as f:
    f.write(html)
