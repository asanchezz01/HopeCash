"""Generate App Store Connect screenshots and preview videos from real app captures.

The raw inputs are produced by running the Flutter web build at the same logical
sizes as the target Apple devices. This script only scales those truthful app
captures to Apple's accepted pixel dimensions and assembles three silent H.264
previews per device class.
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "store-assets" / "raw"
OUT_ROOT = ROOT / "store-assets" / "app-store-connect"
TOOLS_ROOT = ROOT / "store-assets" / ".tools"

SCREENSHOT_SPECS = {
    "iphone-6.5": {
        "source": RAW_ROOT / "iphone",
        "size": (1242, 2688),
        "preview_size": (886, 1920),
    },
    "ipad-13": {
        "source": RAW_ROOT / "ipad",
        "size": (2064, 2752),
        "preview_size": (1200, 1600),
    },
}

PREVIEWS = {
    "01-visao-geral": [
        ("01-dashboard.png", 6.2),
        ("02-lancamentos.png", 4.65),
        ("03-contas.png", 4.65),
    ],
    "02-planejamento": [
        ("05-orcamento.png", 6.2),
        ("06-metas.png", 3.1),
        ("07-dividas.png", 3.1),
        ("08-investimentos.png", 3.1),
    ],
    "03-hope-e-recursos": [
        ("09-hope.png", 6.2),
        ("04-cartoes.png", 4.65),
        ("10-mais.png", 4.65),
    ],
}


def ffmpeg_executable() -> str:
    sys.path.insert(0, str(TOOLS_ROOT))
    try:
        import imageio_ffmpeg  # type: ignore
    except ImportError as exc:
        raise SystemExit(
            "imageio-ffmpeg ausente. Instale com: "
            "python -m pip install --target store-assets/.tools imageio-ffmpeg==0.6.0"
        ) from exc
    return imageio_ffmpeg.get_ffmpeg_exe()


def resize_screenshots(source_dir: Path, output_dir: Path, size: tuple[int, int]) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    inputs = sorted(source_dir.glob("[0-9][0-9]-*.png"))
    if len(inputs) != 10:
        raise SystemExit(f"Esperadas 10 capturas em {source_dir}; encontradas {len(inputs)}")

    for source in inputs:
        with Image.open(source) as image:
            if image.width * size[1] != image.height * size[0]:
                raise SystemExit(f"Proporcao inesperada em {source}: {image.size}")
            rendered = image.convert("RGB").resize(size, Image.Resampling.LANCZOS)
            rendered.save(output_dir / source.name, "PNG", optimize=True)


def build_preview(
    ffmpeg: str,
    screenshots_dir: Path,
    output_path: Path,
    preview_size: tuple[int, int],
    segments: list[tuple[str, float]],
) -> None:
    command = [ffmpeg, "-y", "-hide_banner", "-loglevel", "error"]
    filter_parts: list[str] = []
    concat_inputs: list[str] = []

    for index, (filename, duration) in enumerate(segments):
        command.extend(
            [
                "-loop",
                "1",
                "-framerate",
                "30",
                "-t",
                f"{duration:g}",
                "-i",
                str(screenshots_dir / filename),
            ]
        )
        width, height = preview_size
        filter_parts.append(
            f"[{index}:v]scale={width}:{height}:flags=lanczos," 
            "setsar=1,fps=30,format=yuv420p,setpts=PTS-STARTPTS" 
            f"[v{index}]"
        )
        concat_inputs.append(f"[v{index}]")

    filter_parts.append(
        f"{''.join(concat_inputs)}concat=n={len(segments)}:v=1:a=0[outv]"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    command.extend(
        [
            "-filter_complex",
            ";".join(filter_parts),
            "-map",
            "[outv]",
            "-an",
            "-c:v",
            "libx264",
            "-profile:v",
            "high",
            "-level:v",
            "4.0",
            "-preset",
            "medium",
            "-b:v",
            "11M",
            "-minrate",
            "10M",
            "-maxrate",
            "12M",
            "-bufsize",
            "12M",
            "-x264-params",
            "nal-hrd=cbr:force-cfr=1:filler=1",
            "-r",
            "30",
            "-t",
            "15.5",
            "-movflags",
            "+faststart",
            str(output_path),
        ]
    )
    subprocess.run(command, check=True)


def verify_pngs(directory: Path, expected_size: tuple[int, int]) -> None:
    files = sorted(directory.glob("*.png"))
    if len(files) != 10:
        raise SystemExit(f"Verificacao falhou: {directory} tem {len(files)} PNGs")
    for path in files:
        with Image.open(path) as image:
            if image.size != expected_size:
                raise SystemExit(f"Dimensao invalida: {path} = {image.size}")


def main() -> None:
    ffmpeg = ffmpeg_executable()
    for device, spec in SCREENSHOT_SPECS.items():
        device_dir = OUT_ROOT / device
        screenshots_dir = device_dir / "screenshots"
        previews_dir = device_dir / "previews"
        resize_screenshots(spec["source"], screenshots_dir, spec["size"])
        verify_pngs(screenshots_dir, spec["size"])

        for preview_name, segments in PREVIEWS.items():
            build_preview(
                ffmpeg,
                screenshots_dir,
                previews_dir / f"{preview_name}.mp4",
                spec["preview_size"],
                segments,
            )

    print(f"Ativos gerados em {OUT_ROOT}")


if __name__ == "__main__":
    os.chdir(ROOT)
    main()
