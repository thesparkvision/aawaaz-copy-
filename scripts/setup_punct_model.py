#!/usr/bin/env python3
"""Download and prepare the punctuation model for Aawaaz.

Downloads the xlm-roberta punctuation model from HuggingFace,
converts bool outputs to int32 (required by ONNX Runtime Swift),
and copies the files into the app's sandbox container at:
  ~/Library/Containers/dev.shantanugoel.Aawaaz/Data/Library/Application Support/Aawaaz/PunctuationModel/

Usage:
    python scripts/setup_punct_model.py
"""

import os
import shutil
import sys
from pathlib import Path

BUNDLE_ID = "dev.shantanugoel.Aawaaz"


def _resolve_install_dir() -> Path:
    """Return the sandbox container Application Support path for Aawaaz.

    When the app runs sandboxed, FileManager.applicationSupportDirectory
    resolves inside ~/Library/Containers/<bundle-id>/Data/Library/Application Support/.
    We install there so the sandboxed app can read the files.
    Falls back to the plain ~/Library/Application Support/ if the container
    directory does not exist (e.g. app has never been launched).
    """
    container = Path.home() / "Library" / "Containers" / BUNDLE_ID / "Data" / "Library" / "Application Support" / "Aawaaz" / "PunctuationModel"
    plain = Path.home() / "Library" / "Application Support" / "Aawaaz" / "PunctuationModel"

    # Prefer container path if the container exists (app has been launched at least once)
    container_root = Path.home() / "Library" / "Containers" / BUNDLE_ID
    if container_root.exists():
        return container
    return plain


def main():
    app_support_dir = _resolve_install_dir()

    # Check if already set up
    if (app_support_dir / "model_int8.onnx").exists() and (app_support_dir / "sp.model").exists():
        print(f"✅ Model already installed at {app_support_dir}")
        return

    # Step 1: Download model via punctuators
    print("📥 Downloading punctuation model from HuggingFace...")
    try:
        from punctuators.models import PunctCapSegModelONNX
    except ImportError:
        print("❌ 'punctuators' package not installed. Run: pip install punctuators")
        sys.exit(1)

    PunctCapSegModelONNX.from_pretrained("1-800-BAD-CODE/xlm-roberta_punctuation_fullstop_truecase")
    print("✅ Model downloaded")

    # Step 2: Find model files in HF cache
    hf_cache = Path.home() / ".cache" / "huggingface" / "hub" / "models--1-800-BAD-CODE--xlm-roberta_punctuation_fullstop_truecase" / "snapshots"
    if not hf_cache.exists():
        print(f"❌ HF cache not found at {hf_cache}")
        sys.exit(1)

    snapshots = [d for d in hf_cache.iterdir() if not d.name.startswith(".")]
    if not snapshots:
        print("❌ No snapshots found in HF cache")
        sys.exit(1)

    snapshot_dir = snapshots[0]
    original_onnx = snapshot_dir / "model.onnx"
    sp_model = snapshot_dir / "sp.model"
    converted_onnx = snapshot_dir / "model_int8.onnx"

    if not original_onnx.exists():
        print(f"❌ model.onnx not found at {original_onnx}")
        sys.exit(1)

    # Step 3: Convert bool outputs to int32
    if not converted_onnx.exists():
        print("🔄 Converting model (bool → int32 outputs)...")
        try:
            import onnx
            from onnx import helper, TensorProto
        except ImportError:
            print("❌ 'onnx' package not installed. Run: pip install onnx")
            sys.exit(1)

        model = onnx.load(str(original_onnx))

        bool_outputs = [o for o in model.graph.output if o.type.tensor_type.elem_type == TensorProto.BOOL]
        for out in bool_outputs:
            cast_name = f"cast_{out.name}_to_int32"
            cast_node = helper.make_node("Cast", inputs=[out.name], outputs=[cast_name], to=TensorProto.INT32)
            model.graph.node.append(cast_node)

            # Update output to point to cast node
            out.name = cast_name
            out.type.tensor_type.elem_type = TensorProto.INT32

        onnx.save(model, str(converted_onnx))
        print("✅ Model converted")
    else:
        print("✅ Converted model already exists in HF cache")

    # Step 4: Copy to Application Support
    print(f"📁 Installing to {app_support_dir}")
    app_support_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(converted_onnx, app_support_dir / "model_int8.onnx")
    shutil.copy2(sp_model, app_support_dir / "sp.model")

    print(f"✅ Done! Model installed at {app_support_dir}")
    print("   Restart Aawaaz to enable punctuation & capitalization.")


if __name__ == "__main__":
    main()
