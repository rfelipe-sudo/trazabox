"""
analizar_video_rubrica_local.py
───────────────────────────────
Alternativa SIN APIs de pago: extrae frames + audio y genera un paquete
listo para evaluar en Cursor (o con Whisper local opcional).

USO:
  pip install faster-whisper   # opcional, para transcripción local
  python analizar_video_rubrica_local.py --video mi_clase.mp4 --duracion 1200

  Luego abre la carpeta generada y pide en Cursor:
  "Evalúa según la rúbrica usando los archivos en [carpeta]"

REQUISITOS:
  - ffmpeg
  - faster-whisper (opcional; si no está, solo genera frames)
"""

import os
import sys
import json
import argparse
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path

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

PROMPT_EVALUACION = """Eres un evaluador experto en educación parvularia.
Analiza este video pedagógico usando la transcripción y los frames adjuntos.
Evalúa cada criterio de la rúbrica y responde SOLO con JSON:

{{
  "resumen_general": "texto de 2-3 oraciones",
  "duracion_minutos": número,
  "cumple_duracion": true/false,
  "criterios": [
    {{
      "numero": 1,
      "descripcion": "...",
      "puntaje": 0-3,
      "nivel": "Logrado|Medianamente logrado|No logrado|No observable",
      "evidencia": "qué se observó específicamente"
    }}
  ],
  "puntaje_total": número,
  "puntaje_maximo": número,
  "porcentaje": número,
  "fortalezas": ["...", "..."],
  "aspectos_a_mejorar": ["...", "..."],
  "recomendaciones": ["...", "..."]
}}

DURACIÓN DEL SEGMENTO: {duracion_min:.1f} minutos
INICIO DEL SEGMENTO: {inicio_min:.1f} minutos

RÚBRICA:
{rubrica}

TRANSCRIPCIÓN:
{transcripcion}
"""


def check_ffmpeg():
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("❌ ffmpeg no encontrado. Instálalo desde https://ffmpeg.org")
        sys.exit(1)


def get_video_duration(video_path: str) -> float:
    result = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", video_path],
        capture_output=True, text=True, check=True,
    )
    return float(json.loads(result.stdout)["format"]["duration"])


def extract_frames(video_path, out_dir, interval, max_frames, inicio=0, duracion=None):
    pattern = os.path.join(out_dir, "frame_%04d.jpg")
    cmd = ["ffmpeg"]
    if inicio > 0:
        cmd.extend(["-ss", str(inicio)])
    cmd.extend(["-i", video_path])
    if duracion:
        cmd.extend(["-t", str(duracion)])
    cmd.extend([
        "-vf", f"fps=1/{interval},scale=1280:-1",
        "-vframes", str(max_frames), "-q:v", "3",
        pattern, "-y", "-loglevel", "error",
    ])
    subprocess.run(cmd, check=True)
    return sorted(Path(out_dir).glob("frame_*.jpg"))


def extract_audio(video_path, out_dir, inicio=0, duracion=None):
    audio_path = os.path.join(out_dir, "audio.wav")
    cmd = ["ffmpeg"]
    if inicio > 0:
        cmd.extend(["-ss", str(inicio)])
    cmd.extend(["-i", video_path])
    if duracion:
        cmd.extend(["-t", str(duracion)])
    cmd.extend(["-vn", "-ar", "16000", "-ac", "1", audio_path, "-y", "-loglevel", "error"])
    subprocess.run(cmd, check=True)
    return audio_path


def transcribe_local(audio_path: str) -> str:
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        return "(Instala faster-whisper: pip install faster-whisper)"

    print("🎤 Transcribiendo localmente (puede tardar unos minutos)...")
    model = WhisperModel("base", device="cpu", compute_type="int8")
    segments, _ = model.transcribe(audio_path, language="es")
    text = " ".join(s.text.strip() for s in segments)
    print(f"   → {len(text)} caracteres transcritos")
    return text or "(Sin habla detectada)"


def main():
    parser = argparse.ArgumentParser(description="Prepara material para evaluación local en Cursor")
    parser.add_argument("--video", required=True)
    parser.add_argument("--output", default=None, help="Carpeta de salida")
    parser.add_argument("--intervalo", type=int, default=30)
    parser.add_argument("--max-frames", type=int, default=20)
    parser.add_argument("--inicio", type=float, default=0)
    parser.add_argument("--duracion", type=float, default=None)
    parser.add_argument("--sin-transcripcion", action="store_true")
    args = parser.parse_args()

    video_path = Path(args.video)
    if not video_path.exists():
        print(f"❌ Video no encontrado: {video_path}")
        sys.exit(1)

    check_ffmpeg()
    duracion_total = get_video_duration(str(video_path))
    duracion_seg = args.duracion or duracion_total

    out_dir = Path(args.output or video_path.with_suffix(""))
    out_dir = out_dir.parent / f"{out_dir.name}_evaluacion"
    frames_dir = out_dir / "frames"
    frames_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n📦 Generando paquete en: {out_dir}\n")
    print(f"⏱  Total: {duracion_total/60:.1f} min | Segmento: {duracion_seg/60:.1f} min\n")

    with tempfile.TemporaryDirectory() as tmp:
        tmp_audio = extract_audio(str(video_path), tmp, args.inicio, args.duracion)
        frames_tmp = extract_frames(
            str(video_path), tmp, args.intervalo, args.max_frames,
            args.inicio, args.duracion,
        )
        for i, src in enumerate(frames_tmp):
            t = int(args.inicio + i * args.intervalo)
            dst = frames_dir / f"frame_{t//60:02d}m{t%60:02d}s.jpg"
            dst.write_bytes(src.read_bytes())

        transcripcion = "(Transcripción omitida)" if args.sin_transcripcion else transcribe_local(tmp_audio)

    (out_dir / "transcripcion.txt").write_text(transcripcion, encoding="utf-8")
    (out_dir / "rubrica.txt").write_text(RUBRICA.strip(), encoding="utf-8")

    meta = {
        "video": video_path.name,
        "duracion_total_min": round(duracion_total / 60, 1),
        "segmento_inicio_min": round(args.inicio / 60, 1),
        "segmento_duracion_min": round(duracion_seg / 60, 1),
        "cumple_duracion_rubrica": 15 <= duracion_seg / 60 <= 25,
        "frames": len(list(frames_dir.glob("*.jpg"))),
        "generado": datetime.now().isoformat(),
    }
    (out_dir / "metadata.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")

    prompt = PROMPT_EVALUACION.format(
        duracion_min=duracion_seg / 60,
        inicio_min=args.inicio / 60,
        rubrica=RUBRICA.strip(),
        transcripcion=transcripcion[:12000],
    )
    (out_dir / "prompt_para_cursor.md").write_text(prompt, encoding="utf-8")

    print("✅ Listo:")
    print(f"   Frames:       {frames_dir}")
    print(f"   Transcripción:{out_dir / 'transcripcion.txt'}")
    print(f"   Prompt:       {out_dir / 'prompt_para_cursor.md'}")
    print("\n💡 En Cursor, arrastra la carpeta 'frames' y pega el contenido de prompt_para_cursor.md")


if __name__ == "__main__":
    main()
