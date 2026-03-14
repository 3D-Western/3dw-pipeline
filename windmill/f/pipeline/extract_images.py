import os
import subprocess
from typing import Any


def _resolve_model_path(context: dict[str, Any]) -> str:
    model_path = context.get("model_path") or context.get("modelPath")
    if not model_path:
        raise ValueError("missing model path in context (model_path or modelPath)")
    return str(model_path)


def main(context: dict[str, Any]) -> dict[str, Any]:
    """Extract preview images from model file."""
    model_path = _resolve_model_path(context)
    render_script = os.getenv(
        "MODEL_RENDER_SCRIPT",
        "/opt/windpipe/core/slicing/model_render/render_stl.sh",
    )
    backend = os.getenv("MODEL_RENDER_BACKEND", "openscad")

    command = [render_script, model_path, "--backend", backend]
    subprocess.run(command, check=True)

    context["render_backend"] = backend
    context["render_output_dir"] = str(
        os.path.join(os.path.dirname(model_path), "renders")
    )
    return context
