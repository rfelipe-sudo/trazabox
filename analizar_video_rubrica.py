"""
analizar_video_rubrica.py
─────────────────────────
Analiza un video pedagógico contra una rúbrica usando:
  - ffmpeg    → extrae frames + audio
  - Whisper   → transcribe el audio
  - Claude    → evalúa frames y transcripción contra la rúbrica

USO:
  pip install openai anthropic pillow
  python analizar_video_rubrica.py --video mi_clase.mp4

REQUISITOS:
  - ffmpeg instalado (https://ffmpeg.org)
  - OPENAI_API_KEY  (para Whisper)
  - ANTHROPIC_API_KEY (para Claude)
"""

import os
import sys
import json
import base64
import argparse
import subprocess
import tempfile
from pathlib import Path
from typing import Optional


def cargar_env():
    """Carga variables desde .env en el directorio del script o cwd."""
    for env_path in (Path(__file__).resolve().parent / ".env", Path.cwd() / ".env"):
        if not env_path.exists():
            continue
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip().strip('"').strip("'")
            os.environ.setdefault(key, value)


def verificar_api_keys():
    faltan = []
    if not os.environ.get("OPENAI_API_KEY"):
        faltan.append("OPENAI_API_KEY")
    if not os.environ.get("ANTHROPIC_API_KEY"):
        faltan.append("ANTHROPIC_API_KEY")
    if faltan:
        print("❌ Faltan variables de entorno:", ", ".join(faltan))
        print("   Configúralas con export o agrégalas al .env del proyecto.")
        sys.exit(1)

# ── Librerías ──────────────────────────────────────────────────────────────
try:
    import anthropic
    import openai
except ImportError:
    print("Instalando dependencias...")
    subprocess.run([sys.executable, "-m", "pip", "install", "anthropic", "openai", "pillow"], check=True)
    import anthropic
    import openai

# ── RÚBRICA ────────────────────────────────────────────────────────────────
RUBRICA = """
RÚBRICA DE EVALUACIÓN - VIDEO DE DESEMPEÑO EN AULA

CRITERIOS DE PREPARACIÓN:
1. La experiencia es representativa del desempeño del/la estudiante
2. Se observa un ambiente adecuado para niñas y niños
3. Se utilizan materiales y recursos preparados para el aprendizaje
4. La experiencia se ajusta a características, intereses y contextos de los niños/as

CRITERIOS DE REALIZACIÓN:
5. Duración entre 15 y 25 minutos
6. No se observan cortes en el desarrollo de la experiencia
7. Se evidencia coherencia con los objetivos de aprendizaje de la planificación
8. Interacción efectiva con niñas y niños durante la experiencia

CRITERIOS PEDAGÓGICOS:
9. El/la docente utiliza lenguaje claro y apropiado para el nivel
10. Se promueve la participación activa de los niños/as
11. Se observan estrategias didácticas pertinentes al nivel educativo
12. Se evidencia manejo del grupo y del tiempo

ESCALA:
- Logrado (3): Se evidencia claramente el criterio
- Medianamente logrado (2): Se evidencia parcialmente
- No logrado (1): No se evidencia el criterio
- No observable (0): No es posible evaluar con el material disponible
"""

# ── CONFIGURACIÓN ──────────────────────────────────────────────────────────
FRAME_INTERVAL  = 30   # segundos entre frames
MAX_FRAMES      = 20   # máximo frames a analizar
ANTHROPIC_MODEL = "claude-opus-4-6"

# ──────────────────────────────────────────────────────────────────────────
def check_ffmpeg():
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ ffmpeg no encontrado. Instálalo desde https://ffmpeg.org")
        sys.exit(1)

def get_video_duration(video_path: str) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "json", video_path],
        capture_output=True, text=True
    )
    data = json.loads(result.stdout)
    return float(data["format"]["duration"])

def extract_frames(
    video_path: str,
    output_dir: str,
    interval: int,
    max_frames: int,
    inicio: float = 0,
    duracion: Optional[float] = None,
) -> list[str]:
    """Extrae frames cada N segundos, opcionalmente desde un segmento."""
    print(f"📸 Extrayendo frames cada {interval}s...")
    output_pattern = os.path.join(output_dir, "frame_%04d.jpg")
    cmd = ["ffmpeg"]
    if inicio > 0:
        cmd.extend(["-ss", str(inicio)])
    cmd.extend(["-i", video_path])
    if duracion:
        cmd.extend(["-t", str(duracion)])
    cmd.extend([
        "-vf", f"fps=1/{interval},scale=1280:-1",
        "-vframes", str(max_frames),
        "-q:v", "3",
        output_pattern,
        "-y", "-loglevel", "error",
    ])
    subprocess.run(cmd, check=True)
    frames = sorted(Path(output_dir).glob("frame_*.jpg"))
    print(f"   → {len(frames)} frames extraídos")
    return [str(f) for f in frames]

def extract_audio(
    video_path: str,
    output_dir: str,
    inicio: float = 0,
    duracion: Optional[float] = None,
) -> str:
    """Extrae audio como mp3, opcionalmente desde un segmento."""
    print("🎵 Extrayendo audio...")
    audio_path = os.path.join(output_dir, "audio.mp3")
    cmd = ["ffmpeg"]
    if inicio > 0:
        cmd.extend(["-ss", str(inicio)])
    cmd.extend(["-i", video_path])
    if duracion:
        cmd.extend(["-t", str(duracion)])
    cmd.extend([
        "-vn", "-acodec", "libmp3lame",
        "-ar", "16000", "-ac", "1", "-b:a", "64k",
        audio_path, "-y", "-loglevel", "error",
    ])
    subprocess.run(cmd, check=True)
    print(f"   → Audio extraído: {os.path.getsize(audio_path) / 1024 / 1024:.1f} MB")
    return audio_path

def transcribe_audio(audio_path: str) -> str:
    """Transcribe audio con Whisper"""
    print("🎤 Transcribiendo audio con Whisper...")
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        print("   ⚠️  OPENAI_API_KEY no encontrada. Saltando transcripción.")
        return "(Transcripción no disponible — configura OPENAI_API_KEY)"

    client = openai.OpenAI(api_key=api_key)
    file_size_mb = os.path.getsize(audio_path) / 1024 / 1024

    if file_size_mb > 25:
        print(f"   ⚠️  Audio muy grande ({file_size_mb:.1f}MB). Cortando a 25 min...")
        trimmed = audio_path.replace(".mp3", "_trimmed.mp3")
        subprocess.run([
            "ffmpeg", "-i", audio_path, "-t", "1500",
            trimmed, "-y", "-loglevel", "error"
        ], check=True)
        audio_path = trimmed

    with open(audio_path, "rb") as f:
        transcript = client.audio.transcriptions.create(
            model="whisper-1",
            file=f,
            language="es"
        )
    print(f"   → Transcripción: {len(transcript.text)} caracteres")
    return transcript.text

def image_to_base64(image_path: str) -> str:
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def analizar_con_claude(
    frames: list[str],
    transcripcion: str,
    duracion: float,
    intervalo: int = FRAME_INTERVAL,
    offset_seg: float = 0,
) -> dict:
    """Envía frames + transcripción a Claude para evaluación"""
    print("🤖 Analizando con Claude...")
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("❌ ANTHROPIC_API_KEY no encontrada.")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    # Construir contenido con imágenes
    content = []

    # Texto intro
    content.append({
        "type": "text",
        "text": f"""Eres un evaluador experto en educación parvularia. 
Analiza este video pedagógico y evalúalo según la rúbrica proporcionada.

DURACIÓN DEL VIDEO: {duracion/60:.1f} minutos

RÚBRICA:
{RUBRICA}

A continuación te entrego {len(frames)} frames del video tomados cada {intervalo} segundos,
y la transcripción completa del audio.

TRANSCRIPCIÓN DEL AUDIO:
{transcripcion[:8000]}

FRAMES DEL VIDEO (en orden cronológico):"""
    })

    # Agregar frames
    for i, frame_path in enumerate(frames):
        tiempo = int(offset_seg + i * intervalo)
        minutos = tiempo // 60
        segundos = tiempo % 60
        content.append({
            "type": "text",
            "text": f"\n[Frame {i+1} — {minutos}:{segundos:02d}]"
        })
        content.append({
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": "image/jpeg",
                "data": image_to_base64(frame_path)
            }
        })

    # Instrucción final
    content.append({
        "type": "text",
        "text": """
Ahora evalúa cada criterio de la rúbrica y responde en formato JSON con esta estructura:
{
  "resumen_general": "texto de 2-3 oraciones",
  "duracion_minutos": número,
  "cumple_duracion": true/false,
  "criterios": [
    {
      "numero": 1,
      "descripcion": "...",
      "puntaje": 0-3,
      "nivel": "Logrado|Medianamente logrado|No logrado|No observable",
      "evidencia": "qué se observó específicamente"
    }
  ],
  "puntaje_total": número,
  "puntaje_maximo": número,
  "porcentaje": número,
  "fortalezas": ["...", "..."],
  "aspectos_a_mejorar": ["...", "..."],
  "recomendaciones": ["...", "..."]
}
Responde SOLO con el JSON, sin texto adicional."""
    })

    response = client.messages.create(
        model=ANTHROPIC_MODEL,
        max_tokens=4000,
        messages=[{"role": "user", "content": content}]
    )

    raw = response.content[0].text.strip()
    # Limpiar posibles backticks
    if raw.startswith("```"):
        raw = raw.split("```")[1]
        if raw.startswith("json"):
            raw = raw[4:]
    raw = raw.strip()

    return json.loads(raw)

def generar_informe_html(resultado: dict, video_nombre: str, output_path: str):
    """Genera informe HTML con los resultados"""
    criterios_html = ""
    for c in resultado.get("criterios", []):
        color = {"Logrado": "#2dc653", "Medianamente logrado": "#ffd740",
                 "No logrado": "#E8391D", "No observable": "#9E9E9E"}.get(c["nivel"], "#9E9E9E")
        criterios_html += f"""
        <tr>
          <td style="padding:10px;border-bottom:1px solid #eee;font-weight:600">{c['numero']}</td>
          <td style="padding:10px;border-bottom:1px solid #eee">{c['descripcion']}</td>
          <td style="padding:10px;border-bottom:1px solid #eee;text-align:center">
            <span style="background:{color};color:{'#000' if c['nivel']=='Medianamente logrado' else '#fff'};
            padding:3px 10px;border-radius:20px;font-size:12px;font-weight:700">{c['nivel']}</span>
          </td>
          <td style="padding:10px;border-bottom:1px solid #eee;text-align:center;font-weight:800;font-size:18px">{c['puntaje']}</td>
          <td style="padding:10px;border-bottom:1px solid #eee;font-size:13px;color:#555">{c['evidencia']}</td>
        </tr>"""

    fortalezas = "".join(f"<li>{f}</li>" for f in resultado.get("fortalezas", []))
    mejoras    = "".join(f"<li>{m}</li>" for m in resultado.get("aspectos_a_mejorar", []))
    recomend   = "".join(f"<li>{r}</li>" for r in resultado.get("recomendaciones", []))
    porcentaje = resultado.get("porcentaje", 0)
    color_pct  = "#2dc653" if porcentaje >= 70 else "#ffd740" if porcentaje >= 50 else "#E8391D"

    html = f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>Informe de Evaluación — {video_nombre}</title>
<style>
  body {{ font-family: 'Segoe UI', sans-serif; max-width: 960px; margin: 40px auto; padding: 0 24px; color: #222; }}
  h1 {{ color: #1B2A6B; border-bottom: 3px solid #E8391D; padding-bottom: 12px; }}
  h2 {{ color: #1B2A6B; margin-top: 32px; }}
  .meta {{ display: flex; gap: 24px; flex-wrap: wrap; margin: 20px 0; }}
  .meta-item {{ background: #f5f5f5; padding: 12px 20px; border-radius: 10px; }}
  .meta-item strong {{ display: block; font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: .08em; }}
  .meta-item span {{ font-size: 22px; font-weight: 800; color: #1B2A6B; }}
  .pct {{ font-size: 28px !important; color: {color_pct} !important; }}
  .resumen {{ background: #f0f4ff; border-left: 4px solid #1B2A6B; padding: 16px 20px; border-radius: 0 10px 10px 0; margin: 20px 0; }}
  table {{ width: 100%; border-collapse: collapse; margin-top: 12px; }}
  th {{ background: #1B2A6B; color: #fff; padding: 12px 10px; text-align: left; font-size: 12px; letter-spacing: .06em; }}
  .col3 {{ display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 20px; margin-top: 20px; }}
  .col3 > div {{ background: #f9f9f9; border-radius: 10px; padding: 16px; }}
  .col3 h3 {{ font-size: 13px; text-transform: uppercase; letter-spacing: .08em; margin-bottom: 10px; }}
  .col3 ul {{ padding-left: 18px; }}
  .col3 li {{ margin-bottom: 6px; font-size: 14px; }}
  .verde h3 {{ color: #2dc653; }}
  .amb h3 {{ color: #e6a817; }}
  .azul h3 {{ color: #1B2A6B; }}
  footer {{ margin-top: 40px; text-align: center; font-size: 12px; color: #aaa; }}
</style>
</head>
<body>
<h1>📋 Informe de Evaluación de Video Pedagógico</h1>
<p style="color:#888;font-size:14px">Video: <strong>{video_nombre}</strong></p>

<div class="meta">
  <div class="meta-item"><strong>Duración</strong><span>{resultado.get('duracion_minutos','—')} min</span></div>
  <div class="meta-item"><strong>Cumple duración</strong><span>{'✅ Sí' if resultado.get('cumple_duracion') else '❌ No'}</span></div>
  <div class="meta-item"><strong>Puntaje</strong><span>{resultado.get('puntaje_total','—')} / {resultado.get('puntaje_maximo','—')}</span></div>
  <div class="meta-item"><strong>Porcentaje</strong><span class="pct">{porcentaje}%</span></div>
</div>

<div class="resumen"><strong>Resumen:</strong> {resultado.get('resumen_general','')}</div>

<h2>Evaluación por Criterio</h2>
<table>
  <tr>
    <th style="width:40px">#</th>
    <th>Criterio</th>
    <th style="width:180px">Nivel</th>
    <th style="width:60px">Pts</th>
    <th>Evidencia observada</th>
  </tr>
  {criterios_html}
</table>

<div class="col3">
  <div class="verde"><h3>✅ Fortalezas</h3><ul>{fortalezas}</ul></div>
  <div class="amb"><h3>⚠️ Aspectos a mejorar</h3><ul>{mejoras}</ul></div>
  <div class="azul"><h3>💡 Recomendaciones</h3><ul>{recomend}</ul></div>
</div>

<footer>Generado automáticamente con Claude {ANTHROPIC_MODEL} + Whisper · {__import__('datetime').datetime.now().strftime('%d/%m/%Y %H:%M')}</footer>
</body>
</html>"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"✅ Informe guardado en: {output_path}")

# ── MAIN ───────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="Analiza video pedagógico contra rúbrica")
    parser.add_argument("--video", required=True, help="Ruta al archivo de video")
    parser.add_argument("--output", default=None, help="Ruta del informe HTML (opcional)")
    parser.add_argument("--intervalo", type=int, default=FRAME_INTERVAL, help="Segundos entre frames (default: 30)")
    parser.add_argument("--max-frames", type=int, default=MAX_FRAMES, help="Máximo de frames (default: 20)")
    parser.add_argument("--inicio", type=float, default=0, help="Segundo de inicio del segmento a analizar (default: 0)")
    parser.add_argument("--duracion", type=float, default=None,
                        help="Duración del segmento en segundos (ej. 1200 = 20 min). Recomendado para videos largos.")
    args = parser.parse_args()

    cargar_env()

    video_path = args.video
    if not os.path.exists(video_path):
        print(f"❌ Video no encontrado: {video_path}")
        sys.exit(1)

    video_nombre = Path(video_path).name
    output_path  = args.output or str(Path(video_path).with_suffix("")) + "_informe.html"

    print(f"\n{'='*55}")
    print(f"  ANÁLISIS DE VIDEO PEDAGÓGICO")
    print(f"  {video_nombre}")
    print(f"{'='*55}\n")

    check_ffmpeg()
    verificar_api_keys()

    duracion_total = get_video_duration(video_path)
    duracion_analisis = args.duracion or duracion_total
    print(f"⏱  Duración total: {duracion_total/60:.1f} minutos")
    if args.inicio > 0 or args.duracion:
        print(f"   Segmento analizado: {args.inicio/60:.1f}–{(args.inicio + duracion_analisis)/60:.1f} min "
              f"({duracion_analisis/60:.1f} min)\n")
    elif duracion_total > 25 * 60:
        print("   ⚠️  El video supera 25 min. Considera --duracion 1200 para evaluar un segmento de ~20 min.\n")
    else:
        print()

    with tempfile.TemporaryDirectory() as tmpdir:
        frames = extract_frames(
            video_path, tmpdir, args.intervalo, args.max_frames,
            inicio=args.inicio, duracion=args.duracion,
        )
        audio_path = extract_audio(
            video_path, tmpdir, inicio=args.inicio, duracion=args.duracion,
        )
        transcripcion = transcribe_audio(audio_path)
        resultado = analizar_con_claude(
            frames, transcripcion, duracion_analisis,
            intervalo=args.intervalo, offset_seg=args.inicio,
        )

    json_path = str(Path(output_path).with_suffix("")) + "_resultado.json"
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(resultado, f, ensure_ascii=False, indent=2)

    generar_informe_html(resultado, video_nombre, output_path)

    print(f"\n{'='*55}")
    print(f"  RESULTADO: {resultado.get('porcentaje','?')}%")
    print(f"  Puntaje: {resultado.get('puntaje_total','?')} / {resultado.get('puntaje_maximo','?')}")
    print(f"{'='*55}")
    print(f"\n  Informe HTML: {output_path}")
    print(f"  JSON:         {json_path}\n")

if __name__ == "__main__":
    main()
