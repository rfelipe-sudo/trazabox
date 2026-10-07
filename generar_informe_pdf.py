#!/usr/bin/env python3
"""Genera informe PDF de evaluación pedagógica desde resultado.json."""

import json
import sys
from datetime import datetime
from pathlib import Path

try:
    from fpdf import FPDF
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "fpdf2", "-q"], check=True)
    from fpdf import FPDF


class InformePDF(FPDF):
    AZUL = (27, 42, 107)
    ROJO = (232, 57, 29)
    VERDE = (45, 198, 83)
    AMARILLO = (255, 215, 64)
    GRIS = (120, 120, 120)

    def header(self):
        self.set_font("Helvetica", "B", 11)
        self.set_text_color(*self.AZUL)
        self.cell(0, 8, "Informe de Evaluacion - Video de Desempeno en Aula", align="C", new_x="LMARGIN", new_y="NEXT")
        self.set_draw_color(*self.ROJO)
        self.line(10, self.get_y(), 200, self.get_y())
        self.ln(4)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(*self.GRIS)
        self.cell(0, 10, f"Pagina {self.page_no()}", align="C")

    def titulo(self, texto):
        self.set_font(self._body, "B", 16)
        self.set_text_color(*self.AZUL)
        self.cell(0, 10, texto, new_x="LMARGIN", new_y="NEXT")
        self.ln(2)

    def subtitulo(self, texto):
        self.set_font("Helvetica", "B", 12)
        self.set_text_color(*self.AZUL)
        self.cell(0, 8, texto, new_x="LMARGIN", new_y="NEXT")
        self.ln(1)

    def parrafo(self, texto, size=10):
        self.set_font("Helvetica", "", size)
        self.set_text_color(40, 40, 40)
        self.multi_cell(0, 5, texto)
        self.ln(2)

    def meta_box(self, items):
        self.set_fill_color(245, 245, 245)
        y0 = self.get_y()
        self.set_font("Helvetica", "B", 9)
        self.set_text_color(*self.GRIS)
        cols = len(items)
        w = 190 / cols
        for label, value in items:
            x = self.get_x()
            self.cell(w, 5, label.upper(), fill=True)
        self.ln(5)
        self.set_font("Helvetica", "B", 14)
        self.set_text_color(*self.AZUL)
        for label, value in items:
            self.cell(w, 8, str(value), fill=True)
        self.ln(10)

    def badge_color(self, nivel):
        return {
            "Logrado": self.VERDE,
            "Medianamente logrado": self.AMARILLO,
            "No logrado": self.ROJO,
            "No observable": self.GRIS,
        }.get(nivel, self.GRIS)

    def criterio_fila(self, c):
        nivel = c.get("nivel", "")
        color = self.badge_color(nivel)
        y = self.get_y()
        if y > 250:
            self.add_page()
            y = self.get_y()

        self.set_font("Helvetica", "B", 10)
        self.set_text_color(*self.AZUL)
        self.cell(8, 6, str(c["numero"]), border=0)
        self.set_font("Helvetica", "", 9)
        self.set_text_color(40, 40, 40)
        self.cell(62, 6, c["descripcion"][:55] + ("..." if len(c["descripcion"]) > 55 else ""))
        self.set_font("Helvetica", "B", 8)
        self.set_fill_color(*color)
        txt_color = (0, 0, 0) if nivel == "Medianamente logrado" else (255, 255, 255)
        self.set_text_color(*txt_color)
        self.cell(38, 6, nivel, fill=True, align="C")
        self.set_text_color(*self.AZUL)
        self.set_font("Helvetica", "B", 11)
        self.cell(10, 6, str(c["puntaje"]), align="C")
        self.ln(6)

        self.set_font("Helvetica", "I", 8)
        self.set_text_color(80, 80, 80)
        self.multi_cell(0, 4, f"Evidencia: {c.get('evidencia', '')}")
        self.ln(3)

    def lista_seccion(self, titulo, items, color):
        self.subtitulo(titulo)
        self.set_font("Helvetica", "", 9)
        self.set_text_color(*color)
        for item in items:
            self.multi_cell(0, 5, f"  -  {item}")
        self.ln(3)


from typing import Optional


def _font_path():
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/Library/Fonts/Arial.ttf",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    ]
    for p in candidates:
        if Path(p).exists():
            return p
    return None


def generar_pdf(resultado: dict, video_nombre: str, output_path: str, metadata: Optional[dict] = None):
    pdf = InformePDF()
    font = _font_path()
    if font:
        pdf.add_font("Body", "", font)
        pdf.add_font("Body", "B", font)
        pdf.add_font("Body", "I", font)
        body = "Body"
    else:
        body = "Helvetica"
    pdf.set_auto_page_break(auto=True, margin=15)
    pdf.add_page()

    pdf.titulo("Evaluacion de Video Pedagogico")
    pdf.set_font("Helvetica", "", 10)
    pdf.set_text_color(*InformePDF.GRIS)
    pdf.cell(0, 6, f"Video: {video_nombre}", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, f"Generado: {datetime.now().strftime('%d/%m/%Y %H:%M')}", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(4)

    pct = resultado.get("porcentaje", 0)
    cumple = "Si" if resultado.get("cumple_duracion") else "No"
    pdf.meta_box([
        ("Duracion analizada", f"{resultado.get('duracion_minutos', '-')} min"),
        ("Cumple 15-25 min", cumple),
        ("Puntaje", f"{resultado.get('puntaje_total', '-')} / {resultado.get('puntaje_maximo', 36)}"),
        ("Porcentaje", f"{pct}%"),
    ])

    if metadata:
        pdf.parrafo(
            f"Duracion total del archivo: {metadata.get('duracion_total_min', '-')} min. "
            f"Frames analizados: {metadata.get('frames', '-')} distribuidos a lo largo del video completo."
        )

    pdf.subtitulo("Resumen general")
    pdf.parrafo(resultado.get("resumen_general", ""))

    if resultado.get("nota_segmento"):
        pdf.parrafo(resultado["nota_segmento"], size=9)

    pdf.subtitulo("Evaluacion por criterio")
    pdf.set_font("Helvetica", "B", 8)
    pdf.set_text_color(*InformePDF.GRIS)
    pdf.cell(8, 5, "#")
    pdf.cell(62, 5, "Criterio")
    pdf.cell(38, 5, "Nivel")
    pdf.cell(10, 5, "Pts", align="C")
    pdf.ln(6)

    for c in resultado.get("criterios", []):
        pdf.criterio_fila(c)

    pdf.add_page()
    pdf.lista_seccion("Fortalezas", resultado.get("fortalezas", []), InformePDF.VERDE)
    pdf.lista_seccion("Aspectos a mejorar", resultado.get("aspectos_a_mejorar", []), (230, 168, 23))
    pdf.lista_seccion("Recomendaciones", resultado.get("recomendaciones", []), InformePDF.AZUL)

    pdf.subtitulo("Escala de evaluacion")
    pdf.parrafo(
        "Logrado (3): Se evidencia claramente el criterio.\n"
        "Medianamente logrado (2): Se evidencia parcialmente.\n"
        "No logrado (1): No se evidencia el criterio.\n"
        "No observable (0): No es posible evaluar con el material disponible.",
        size=9,
    )

    pdf.output(output_path)
    print(f"PDF generado: {output_path}")


if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("--json", required=True)
    p.add_argument("--video", default="video")
    p.add_argument("--meta", default=None)
    p.add_argument("--output", required=True)
    args = p.parse_args()

    with open(args.json, encoding="utf-8") as f:
        data = json.load(f)
    meta = None
    if args.meta:
        with open(args.meta, encoding="utf-8") as f:
            meta = json.load(f)
    generar_pdf(data, args.video, args.output, meta)
