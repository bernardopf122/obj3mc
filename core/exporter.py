"""
core/exporter.py - Resource pack exporter
Generates the full Minecraft 1.20.1 resource pack structure.
"""

import os
import json


class ResourcePackExporter:
    def __init__(self, mesh, baked, model_name, model_type, output_dir):
        self.mesh = mesh
        self.baked = baked
        self.model_name = model_name
        self.model_type = model_type
        self.output_dir = output_dir

    def export(self):
        self._make_dirs()
        self._write_pack_mcmeta()
        self._write_texture()
        self._write_model()
        self._write_shaders()

    def _make_dirs(self):
        base = self.output_dir
        os.makedirs(f"{base}/assets/minecraft/models/entity", exist_ok=True)
        os.makedirs(f"{base}/assets/minecraft/textures/obj3mc", exist_ok=True)
        os.makedirs(f"{base}/assets/minecraft/shaders/core", exist_ok=True)

    def _write_pack_mcmeta(self):
        meta = {
            "pack": {
                "pack_format": 15,
                "description": f"obj3mc - {self.model_name}"
            }
        }
        path = f"{self.output_dir}/pack.mcmeta"
        with open(path, "w") as f:
            json.dump(meta, f, indent=2)

    def _write_texture(self):
        png_bytes = self.baked.to_png_bytes()
        path = f"{self.output_dir}/assets/minecraft/textures/obj3mc/{self.model_name}.png"
        with open(path, "wb") as f:
            f.write(png_bytes)

    def _write_model(self):
        from core.shader import ShaderBuilder
        sb = ShaderBuilder(self.mesh, self.baked, self.model_name)
        model = sb.build_model_json(self.model_type)
        path = f"{self.output_dir}/assets/minecraft/models/entity/{self.model_name}.json"
        with open(path, "w") as f:
            json.dump(model, f, indent=2)

    def _write_shaders(self):
        from core.shader import ShaderBuilder
        sb = ShaderBuilder(self.mesh, self.baked, self.model_name)
        vert, frag = sb.build_shaders(self.model_type)

        base = f"{self.output_dir}/assets/minecraft/shaders/core"
        shader_name = sb.shader_name(self.model_type)

        with open(f"{base}/{shader_name}.vsh", "w") as f:
            f.write(vert)
        with open(f"{base}/{shader_name}.fsh", "w") as f:
            f.write(frag)
        with open(f"{base}/{shader_name}.json", "w") as f:
            json.dump(sb.build_shader_json(self.model_type), f, indent=2)
