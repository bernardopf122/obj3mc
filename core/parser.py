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
