#!/usr/bin/env python3
"""Gera um PDF a partir de um Markdown usando python-markdown + LibreOffice.

Uso:
    scripts/gerar-pdf.py docs/arquivo.md [docs/arquivo.pdf]

Caminho: Markdown -> HTML -> DOCX -> PDF. A passagem por DOCX existe para marcar
as linhas de tabela com w:cantSplit, senão o LibreOffice corta uma linha ao meio
na virada de página. Blocos de código viram tabelas de uma célula (linhas unidas
por <br>), porque o importador HTML transforma cada linha de <pre> em parágrafo
com espaço entre elas.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    import markdown
except ImportError:  # pragma: no cover
    sys.exit("erro: instale python3-markdown (apt install python3-markdown)")

CSS = """
@page { size: A4; margin: 1.9cm 1.8cm; }
body { font-family: "DejaVu Sans", sans-serif; font-size: 9.5pt;
       color: #1d1d1f; line-height: 1.32; text-align: left; }
h1 { font-size: 19pt; color: #0f3d56; margin: 0 0 10pt 0; }
h2 { font-size: 13pt; color: #12557a; margin: 14pt 0 5pt 0; }
h3 { font-size: 10.8pt; color: #2c3e50; margin: 12pt 0 4pt 0; }
p { margin: 0 0 6pt 0; }
ul, ol { margin: 0 0 6pt 0; }
li { margin: 0 0 2.5pt 0; }
strong { color: #111; }
a { color: #0b5d8a; }
code { font-family: "DejaVu Sans Mono", monospace; font-size: 8.4pt;
       background: #eef2f6; color: #123; }
pre { font-family: "DejaVu Sans Mono", monospace; font-size: 7.9pt;
      background: #f3f5f8; color: #12232e; padding: 5pt 6pt;
      margin: 6pt 0 9pt 0; }
table { font-size: 8.3pt; margin: 6pt 0 10pt 0; }
th { background: #e6edf3; text-align: left; }
blockquote { background: #fff9e6; color: #3a2f16; padding: 6pt 8pt;
             margin: 8pt 0 10pt 0; font-size: 9pt; text-align: left; }
blockquote p { text-align: left; margin: 0 0 3pt 0; }
hr { color: #c8d2da; }
"""

CODE_CHUNK = 12

TEMPLATE = """<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>{title}</title><style>{css}</style></head>
<body>{body}</body></html>
"""

# títulos h2 que devem começar em página nova

def _pre_to_block(match: re.Match) -> str:
    """LibreOffice transforma cada linha de <pre> em um parágrafo com espaço
    entre eles. Aqui o bloco vira uma tabela de uma célula por trecho, com as
    linhas separadas por <br>: o espaçamento fica constante e o fundo cinza se
    mantém. Blocos longos são cortados em trechos de CODE_CHUNK linhas, para
    que a quebra de página caia entre trechos (sem empurrar o bloco inteiro)."""
    code = match.group(1).rstrip("\n")
    lines = [line.replace(" ", "&nbsp;") or "&nbsp;" for line in code.split("\n")]
    chunks = [lines[i:i + CODE_CHUNK] for i in range(0, len(lines), CODE_CHUNK)]
    out = []
    for i, chunk in enumerate(chunks):
        if i == 0:
            chunk = ["&nbsp;"] + chunk
        if i == len(chunks) - 1:
            chunk = chunk + ["&nbsp;"]
        out.append(
            '<table border="0" cellspacing="0" cellpadding="0" width="100%">'
            '<tr><td bgcolor="#f3f5f8">'
            "<p style=\"font-family:'DejaVu Sans Mono',monospace;font-size:7pt;"
            'margin:0;line-height:1.12">' + "<br>".join(chunk) + "</p></td></tr></table>"
        )
    return "".join(out)


def build_html(md_text: str, title: str) -> str:
    body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "sane_lists"],
        output_format="html5",
    )
    # blocos de código: um parágrafo só, com quebras de linha de verdade
    body = re.sub(r"<pre><code[^>]*>(.*?)</code></pre>", _pre_to_block, body, flags=re.S)
    # o LibreOffice só desenha borda com o atributo; CSS é ignorado
    body = body.replace(
        "<table>",
        '<table border="1" cellspacing="0" cellpadding="2" width="100%">',
    )
    return TEMPLATE.format(title=title, css=CSS, body=body)


def _patch_docx_rows(path: Path) -> None:
    """Marca toda linha de tabela com <w:cantSplit/> (\"não quebrar linha entre
    páginas\"). Sem isso o LibreOffice corta uma linha ao meio na virada de
    página e sobra uma célula órfã no topo da página seguinte."""
    import re as _re
    import zipfile

    tmp = path.with_suffix(".patch.docx")

    def fix_row(match: _re.Match) -> str:
        row = match.group(0)
        # blocos de código também são tabelas (uma célula só): podem quebrar
        if row.count("<w:tc") < 2 or "cantSplit" in row:
            return row
        if "<w:trPr>" in row:
            return row.replace("<w:trPr>", "<w:trPr><w:cantSplit/>", 1)
        return row.replace("<w:tr>", "<w:tr><w:trPr><w:cantSplit/></w:trPr>", 1)

    with zipfile.ZipFile(path) as zin, zipfile.ZipFile(
        tmp, "w", zipfile.ZIP_DEFLATED
    ) as zout:
        for item in zin.infolist():
            data = zin.read(item.filename)
            if item.filename == "word/document.xml":
                text = data.decode("utf-8")
                text = _re.sub(r"<w:tr[ >].*?</w:tr>", fix_row, text, flags=_re.S)
                data = text.encode("utf-8")
            zout.writestr(item, data)
    tmp.replace(path)


def _soffice_convert(src: Path, fmt: str, outdir: Path) -> Path:
    ext = fmt.split(":")[0]
    target = outdir / f"{src.stem}.{ext}"
    proc = subprocess.run(
        ["soffice", "--headless", "--convert-to", fmt, "--outdir", str(outdir), str(src)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0 or not target.exists():
        raise RuntimeError(proc.stdout + proc.stderr)
    return target


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    src = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else src.with_suffix(".pdf")
    if not src.exists():
        sys.exit(f"erro: {src} não existe")
    if not shutil.which("soffice"):
        sys.exit("erro: LibreOffice (soffice) não encontrado")

    md_text = src.read_text(encoding="utf-8")
    m = re.search(r"^#\s+(.+)$", md_text, flags=re.M)
    html = build_html(md_text, m.group(1).strip() if m else src.stem)
    with tempfile.TemporaryDirectory(prefix="md2pdf-") as tmp:
        tmp = Path(tmp)
        # o nome do HTML define o nome do PDF gerado
        html_path = tmp / f"{out.stem}.html"
        html_path.write_text(html, encoding="utf-8")

        # HTML -> DOCX (para marcar as linhas de tabela) -> PDF.
        # Se a etapa DOCX falhar, cai direto no HTML -> PDF.
        try:
            docx = _soffice_convert(html_path, "docx:MS Word 2007 XML", tmp)
            _patch_docx_rows(docx)
            pdf = _soffice_convert(docx, "pdf", tmp)
        except RuntimeError as exc:
            print(f"aviso: rota DOCX falhou ({str(exc).strip()[:120]}); usando HTML",
                  file=sys.stderr)
            pdf = _soffice_convert(html_path, "pdf", tmp)

        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(pdf), out)

    size = out.stat().st_size / 1024
    print(f"ok: {out} ({size:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
