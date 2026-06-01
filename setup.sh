mkdir -p core shaders templates examples

cat > obj3mc.py << 'EOF'
#!/usr/bin/env python3
"""
obj3mc - Converts .obj models to Minecraft Java resource packs
Supports: items, blocks, entities
Target: Minecraft Java 1.20.1
"""

import sys
import os
import argparse
from core.parser import ObjParser
from core.baker import VertexBaker
from core.exporter import ResourcePackExporter

VERSION = "0.1.0"

def main():
    parser = argparse.ArgumentParser(
        prog="obj3mc",
        description="Convert .obj models to Minecraft Java 1.20.1 resource packs"
    )

    parser.add_argument("input", help="Path to the .obj file")
    parser.add_argument("-o", "--output", default="output_pack",
                        help="Output folder for the resource pack (default: output_pack)")
    parser.add_argument("-t", "--type", choices=["item", "block", "entity"],
                        default="item", help="Target model type (default: item)")
    parser.add_argument("-n", "--name", default=None,
                        help="Model name (default: same as input filename)")
    parser.add_argument("-s", "--scale", type=float, default=1.0,
                        help="Scale factor for the model (default: 1.0)")
    parser.add_argument("-v", "--version", action="version", version=f"obj3mc {VERSION}")

    args = parser.parse_args()

    if not os.path.isfile(args.input):
        print(f"[ERROR] File not found: {args.input}")
        sys.exit(1)

    if not args.input.lower().endswith(".obj"):
        print(f"[ERROR] Input must be a .obj file")
        sys.exit(1)

    model_name = args.name or os.path.splitext(os.path.basename(args.input))[0]
    model_name = model_name.lower().replace(" ", "_")

    print(f"[obj3mc] Input:  {args.input}")
    print(f"[obj3mc] Type:   {args.type}")
    print(f"[obj3mc] Name:   {model_name}")
    print(f"[obj3mc] Scale:  {args.scale}")
    print(f"[obj3mc] Output: {args.output}/")
    print()

    print("[1/3] Parsing OBJ...")
    parser_obj = ObjParser(args.input)
    mesh = parser_obj.parse()
    print(f"      Vertices: {len(mesh.vertices)}")
    print(f"      Faces:    {len(mesh.faces)}")
    print(f"      UVs:      {len(mesh.uvs)}")

    print("[2/3] Baking vertex data into texture...")
    baker = VertexBaker(mesh, scale=args.scale)
    baked = baker.bake()
    print(f"      Texture size: {baked.width}x{baked.height}px")

    print("[3/3] Exporting resource pack...")
    exporter = ResourcePackExporter(
        mesh=mesh,
        baked=baked,
        model_name=model_name,
        model_type=args.type,
        output_dir=args.output
    )
    exporter.export()

    print()
    print(f"[OK] Resource pack created at: {args.output}/")
    print(f"     Drop it in resourcepacks/ and enable in Minecraft 1.20.1")

if __name__ == "__main__":
    main()
EOF

cat > core/__init__.py << 'EOF'
EOF

cat > core/parser.py << 'EOF'
"""
core/parser.py - OBJ file parser
"""

import os


class Mesh:
    def __init__(self):
        self.vertices = []
        self.uvs = []
        self.normals = []
        self.faces = []
        self.groups = []
        self.materials = []
        self.name = ""

    def bounds(self):
        if not self.vertices:
            return None
        xs = [v[0] for v in self.vertices]
        ys = [v[1] for v in self.vertices]
        zs = [v[2] for v in self.vertices]
        return {
            "min": (min(xs), min(ys), min(zs)),
            "max": (max(xs), max(ys), max(zs)),
            "center": (
                (min(xs) + max(xs)) / 2,
                (min(ys) + max(ys)) / 2,
                (min(zs) + max(zs)) / 2,
            ),
            "size": (
                max(xs) - min(xs),
                max(ys) - min(ys),
                max(zs) - min(zs),
            )
        }

    def recenter(self):
        b = self.bounds()
        if not b:
            return
        cx, _, cz = b["center"]
        cy = b["min"][1]
        self.vertices = [
            (x - cx, y - cy, z - cz)
            for x, y, z in self.vertices
        ]

    def scale_to_unit(self, target=1.0):
        b = self.bounds()
        if not b:
            return
        max_dim = max(b["size"])
        if max_dim == 0:
            return
        factor = target / max_dim
        self.vertices = [
            (x * factor, y * factor, z * factor)
            for x, y, z in self.vertices
        ]


class ObjParser:
    def __init__(self, filepath: str):
        self.filepath = filepath

    def parse(self) -> Mesh:
        mesh = Mesh()
        mesh.name = os.path.splitext(os.path.basename(self.filepath))[0]

        with open(self.filepath, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue

                parts = line.split()
                token = parts[0]

                if token == "v":
                    mesh.vertices.append((
                        float(parts[1]),
                        float(parts[2]),
                        float(parts[3])
                    ))

                elif token == "vt":
                    mesh.uvs.append((
                        float(parts[1]),
                        float(parts[2]) if len(parts) > 2 else 0.0
                    ))

                elif token == "vn":
                    mesh.normals.append((
                        float(parts[1]),
                        float(parts[2]),
                        float(parts[3])
                    ))

                elif token == "f":
                    face = []
                    for i in range(1, len(parts)):
                        indices = parts[i].split("/")
                        vi  = int(indices[0]) - 1
                        uvi = int(indices[1]) - 1 if len(indices) > 1 and indices[1] else -1
                        ni  = int(indices[2]) - 1 if len(indices) > 2 and indices[2] else -1
                        face.append((vi, uvi, ni))

                    if len(face) == 3:
                        mesh.faces.append(face)
                    elif len(face) > 3:
                        for i in range(1, len(face) - 1):
                            mesh.faces.append([face[0], face[i], face[i + 1]])

                elif token == "g":
                    if len(parts) > 1:
                        mesh.groups.append(parts[1])

                elif token == "usemtl":
                    if len(parts) > 1:
                        mesh.materials.append(parts[1])

        return mesh
EOF

cat > core/baker.py << 'EOF'
"""
core/baker.py - Vertex data baker
Encodes vertex positions and UVs into a PNG texture.

Layout per vertex (3 pixels RGBA each):
  Pixel 0: R=X_high, G=X_low, B=Y_high, A=Y_low
  Pixel 1: R=Z_high, G=Z_low, B=U_high, A=U_low
  Pixel 2: R=V_high, G=V_low, B=0,      A=255
"""

import math
import struct
import zlib


class BakedData:
    def __init__(self, width, height, pixels, vertex_count):
        self.width = width
        self.height = height
        self.pixels = pixels
        self.vertex_count = vertex_count

    def to_png_bytes(self) -> bytes:
        def chunk(ctype, data):
            crc = zlib.crc32(ctype + data) & 0xFFFFFFFF
            return struct.pack(">I", len(data)) + ctype + data + struct.pack(">I", crc)

        png = b'\x89PNG\r\n\x1a\n'
        png += chunk(b'IHDR',
            struct.pack(">II", self.width, self.height) + bytes([8, 6, 0, 0, 0]))

        raw = b''
        for y in range(self.height):
            raw += b'\x00'
            for x in range(self.width):
                idx = y * self.width + x
                r, g, b, a = self.pixels[idx] if idx < len(self.pixels) else (0, 0, 0, 0)
                raw += bytes([r, g, b, a])

        png += chunk(b'IDAT', zlib.compress(raw, 9))
        png += chunk(b'IEND', b'')
        return png


class VertexBaker:
    def __init__(self, mesh, scale=1.0):
        self.mesh = mesh
        self.scale = scale

    def _encode_float(self, value, min_val, max_val):
        if max_val == min_val:
            return (0, 0)
        n = max(0.0, min(1.0, (value - min_val) / (max_val - min_val)))
        e = int(n * 65535)
        return ((e >> 8) & 0xFF, e & 0xFF)

    def bake(self) -> BakedData:
        mesh = self.mesh
        mesh.recenter()
        mesh.scale_to_unit(target=self.scale)

        b = mesh.bounds()
        min_x, min_y, min_z = b["min"]
        max_x, max_y, max_z = b["max"]

        if mesh.uvs:
            min_u = min(uv[0] for uv in mesh.uvs)
            max_u = max(uv[0] for uv in mesh.uvs)
            min_v = min(uv[1] for uv in mesh.uvs)
            max_v = max(uv[1] for uv in mesh.uvs)
        else:
            min_u = min_v = 0.0
            max_u = max_v = 1.0

        vertex_count = len(mesh.vertices)
        pixels_per_vertex = 3

        cols = max(1, math.ceil(math.sqrt(vertex_count)))
        width = cols * pixels_per_vertex
        height = math.ceil(vertex_count / cols)

        # Build UV map: vertex index -> (u, v)
        uv_map = {}
        for face in mesh.faces:
            for vi, uvi, _ in face:
                if vi not in uv_map and uvi >= 0 and uvi < len(mesh.uvs):
                    uv_map[vi] = mesh.uvs[uvi]

        pixels = []
        for i, (vx, vy, vz) in enumerate(mesh.vertices):
            u, v = uv_map.get(i, (0.0, 0.0))

            xh, xl = self._encode_float(vx, min_x, max_x)
            yh, yl = self._encode_float(vy, min_y, max_y)
            zh, zl = self._encode_float(vz, min_z, max_z)
            uh, ul = self._encode_float(u,  min_u, max_u)
            vh, vl = self._encode_float(v,  min_v, max_v)

            pixels.append((xh, xl, yh, yl))
            pixels.append((zh, zl, uh, ul))
            pixels.append((vh, vl, 0,  255))

        while len(pixels) < width * height:
            pixels.append((0, 0, 0, 0))

        return BakedData(width, height, pixels, vertex_count)
EOF

cat > core/exporter.py << 'EOF'
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
        os.makedirs(f"{base}/assets/minecraft/models/{self.model_type}s", exist_ok=True)
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
        path = f"{self.output_dir}/assets/minecraft/models/{self.model_type}s/{self.model_name}.json"
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
EOF

cat > core/shader.py << 'EOF'
"""
core/shader.py - GLSL shader builder for Minecraft 1.20.1
Ports the objmc vertex-baking approach to 1.20.1 core shaders.

Strategy:
- Item/Block: hooks rendertype_item_entity_translucent_cull
- Entity:     hooks rendertype_entity_cutout_no_cull
- The vertex shader reads baked texture data to reconstruct geometry.
"""


SHADER_MAP = {
    "item":   "rendertype_item_entity_translucent_cull",
    "block":  "rendertype_item_entity_translucent_cull",
    "entity": "rendertype_entity_cutout_no_cull",
}


class ShaderBuilder:
    def __init__(self, mesh, baked, model_name):
        self.mesh = mesh
        self.baked = baked
        self.model_name = model_name

    def shader_name(self, model_type):
        return SHADER_MAP.get(model_type, SHADER_MAP["item"])

    def build_model_json(self, model_type):
        tex = f"obj3mc/{self.model_name}"
        return {
            "textures": {
                "0": tex,
                "particle": tex
            },
            "elements": self._build_elements(),
            "display": self._default_display(model_type)
        }

    def _build_elements(self):
        """
        Build one flat quad per triangle face.
        The actual geometry is reconstructed by the vertex shader;
        these quads are just placeholders to emit the right number of vertices.
        """
        elements = []
        for i, face in enumerate(self.mesh.faces):
            # Each face = one quad element (flat 1x1 placeholder)
            elements.append({
                "from": [0, 0, 0],
                "to":   [1, 1, 0.001],
                "faces": {
                    "south": {
                        "uv": [0, 0, 16, 16],
                        "texture": "#0"
                    }
                }
            })
            # Minecraft caps at 112 elements per model
            if i >= 111:
                break
        return elements

    def _default_display(self, model_type):
        if model_type == "entity":
            return {}
        return {
            "thirdperson_righthand": {
                "rotation": [75, 45, 0],
                "translation": [0, 2.5, 0],
                "scale": [0.375, 0.375, 0.375]
            },
            "firstperson_righthand": {
                "rotation": [0, 45, 0],
                "scale": [0.4, 0.4, 0.4]
            },
            "gui": {
                "rotation": [30, 225, 0],
                "scale": [0.625, 0.625, 0.625]
            },
            "ground": {
                "translation": [0, 3, 0],
                "scale": [0.25, 0.25, 0.25]
            },
            "fixed": {
                "scale": [0.5, 0.5, 0.5]
            }
        }

    def build_shaders(self, model_type):
        vert = self._vertex_shader(model_type)
        frag = self._fragment_shader(model_type)
        return vert, frag

    def _vertex_shader(self, model_type):
        tex_w = self.baked.width
        tex_h = self.baked.height
        vertex_count = self.baked.vertex_count
        face_count = len(self.mesh.faces)

        # Pack face->vertex index table as GLSL array literals
        face_lines = []
        for face in self.mesh.faces[:112]:
            v0, v1, v2 = face[0][0], face[1][0], face[2][0]
            face_lines.append(f"    ivec3({v0}, {v1}, {v2})")
        faces_array = ",\n".join(face_lines)

        return f"""#version 150

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in vec2 UV1;
in ivec2 UV2;
in vec3 Normal;

uniform sampler2D Sampler0;
uniform sampler2D Sampler2;
uniform mat4 ModelViewMat;
uniform mat4 ProjMat;
uniform int FogShape;

out float vertexDistance;
out vec4 vertexColor;
out vec4 lightMapColor;
out vec4 overlayColor;
out vec2 texCoord0;
out vec4 normal;

// Baked texture dimensions
const int TEX_W = {tex_w};
const int TEX_H = {tex_h};
const int VERTEX_COUNT = {vertex_count};
const int FACE_COUNT = {min(face_count, 112)};
const int PPV = 3; // pixels per vertex

// Face->vertex index table (baked at compile time)
const ivec3 FACES[{min(face_count, 112)}] = ivec3[]({faces_array}
);

// Decode two 8-bit channels back to float in [min_val, max_val]
float decode(int high, int low, float min_val, float max_val) {{
    float n = float((high << 8) | low) / 65535.0;
    return min_val + n * (max_val - min_val);
}}

// Read one RGBA pixel from baked texture by linear index
vec4 readPixel(int idx) {{
    int px = (idx % (TEX_W / PPV)) * PPV;
    int py = idx / (TEX_W / PPV);
    // offset within the 3-pixel group handled by caller
    return texelFetch(Sampler0, ivec2(px, py), 0);
}}

vec3 getVertex(int vi) {{
    int col = vi % (TEX_W / PPV);
    int row = vi / (TEX_W / PPV);

    vec4 p0 = texelFetch(Sampler0, ivec2(col * PPV + 0, row), 0);
    vec4 p1 = texelFetch(Sampler0, ivec2(col * PPV + 1, row), 0);
    vec4 p2 = texelFetch(Sampler0, ivec2(col * PPV + 2, row), 0);

    // Bounds are normalized 0..1 in the texture; we restore to -0.5..0.5 range
    float x = decode(int(p0.r * 255.0), int(p0.g * 255.0), -0.5, 0.5);
    float y = decode(int(p0.b * 255.0), int(p0.a * 255.0),  0.0, 1.0);
    float z = decode(int(p1.r * 255.0), int(p1.g * 255.0), -0.5, 0.5);
    return vec3(x, y, z);
}}

vec2 getUV(int vi) {{
    int col = vi % (TEX_W / PPV);
    int row = vi / (TEX_W / PPV);

    vec4 p1 = texelFetch(Sampler0, ivec2(col * PPV + 1, row), 0);
    vec4 p2 = texelFetch(Sampler0, ivec2(col * PPV + 2, row), 0);

    float u = decode(int(p1.b * 255.0), int(p1.a * 255.0), 0.0, 1.0);
    float v = decode(int(p2.r * 255.0), int(p2.g * 255.0), 0.0, 1.0);
    return vec2(u, v);
}}

void main() {{
    // gl_VertexID: 4 verts per quad element, 3 quads cover 1 triangle
    // face index = gl_VertexID / 4
    // corner within face = gl_VertexID % 4 (0,1,2,2 for tri->quad)
    int faceIdx = gl_VertexID / 4;
    int corner  = gl_VertexID % 4;

    vec3 pos = Position;
    vec2 uv  = UV0;

    if (faceIdx < FACE_COUNT) {{
        ivec3 f = FACES[faceIdx];
        // corners: 0->v0, 1->v1, 2->v2, 3->v2 (duplicate for quad)
        int vi = (corner == 0) ? f.x : (corner == 1) ? f.y : f.z;
        pos = getVertex(vi);
        uv  = getUV(vi);
    }}

    gl_Position = ProjMat * ModelViewMat * vec4(pos, 1.0);
    vertexDistance = length((ModelViewMat * vec4(pos, 1.0)).xyz);
    vertexColor    = Color;
    lightMapColor  = texelFetch(Sampler2, UV2 / 16, 0);
    overlayColor   = texelFetch(Sampler1, UV1, 0);
    texCoord0      = uv;
    normal         = ProjMat * ModelViewMat * vec4(Normal, 0.0);
}}
"""

    def _fragment_shader(self, model_type):
        return """#version 150

uniform sampler2D Sampler0;
uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;

in float vertexDistance;
in vec4 vertexColor;
in vec4 lightMapColor;
in vec4 overlayColor;
in vec2 texCoord0;
in vec4 normal;

out vec4 fragColor;

void main() {
    vec4 color = texture(Sampler0, texCoord0);
    if (color.a < 0.1) discard;

    color *= vertexColor * ColorModulator;
    color.rgb = mix(color.rgb, overlayColor.rgb, overlayColor.a);
    color *= lightMapColor;

    float fogFactor = smoothstep(FogStart, FogEnd, vertexDistance);
    fragColor = vec4(mix(color.rgb, FogColor.rgb, fogFactor), color.a);
}
"""

    def build_shader_json(self, model_type):
        name = self.shader_name(model_type)
        return {
            "blend": {
                "func": "add",
                "srcrgb": "srcalpha",
                "dstrgb": "1-srcalpha"
            },
            "vertex": name,
            "fragment": name,
            "attributes": [
                "Position", "Color", "UV0", "UV1", "UV2", "Normal"
            ],
            "samplers": [
                {"name": "Sampler0"},
                {"name": "Sampler1"},
                {"name": "Sampler2"}
            ],
            "uniforms": [
                {"name": "ModelViewMat",  "type": "matrix4x4", "count": 16, "values": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
                {"name": "ProjMat",       "type": "matrix4x4", "count": 16, "values": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
                {"name": "ColorModulator","type": "float",      "count": 4,  "values": [1,1,1,1]},
                {"name": "FogStart",      "type": "float",      "count": 1,  "values": [0]},
                {"name": "FogEnd",        "type": "float",      "count": 1,  "values": [1]},
                {"name": "FogColor",      "type": "float",      "count": 4,  "values": [0,0,0,1]},
                {"name": "FogShape",      "type": "int",        "count": 1,  "values": [0]}
            ]
        }
EOF

cat > templates/pack.mcmeta << 'EOF'
{
  "pack": {
    "pack_format": 15,
    "description": "obj3mc generated resource pack"
  }
}
EOF

cat > README.md << 'EOF'
# obj3mc

Convert `.obj` 3D models to Minecraft Java 1.20.1 resource packs.

Inspired by [obj2mc](https://github.com/MrCheeze/obj2mc) and [objmc](https://github.com/Godlander/objmc).

## Usage

```bash
python obj3mc.py model.obj -t item -o output_pack
python obj3mc.py model.obj -t block -o output_pack
python obj3mc.py model.obj -t entity -o output_pack
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-t` | Target type: `item`, `block`, `entity` | `item` |
| `-o` | Output folder | `output_pack` |
| `-n` | Model name | filename |
| `-s` | Scale factor | `1.0` |

## How it works

1. Parses the `.obj` file (vertices, UVs, faces)
2. Bakes vertex data into a PNG texture (16-bit precision per channel)
3. Generates a GLSL vertex shader that reads the texture to reconstruct geometry
4. Outputs a complete resource pack ready for Minecraft 1.20.1

## Requirements

- Python 3.8+
- No external dependencies

## License

MIT
EOF

echo "✅ Estrutura criada com sucesso!"
echo ""
echo "Arquivos criados:"
find . -not -path './.git/*' -type f | sort
