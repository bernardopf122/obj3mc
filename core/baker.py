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
