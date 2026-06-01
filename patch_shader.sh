cat > core/shader.py << 'EOF'
"""
core/shader.py - GLSL shader builder for Minecraft 1.20.1
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
        """Um elemento placeholder por face — sem limite artificial."""
        elements = []
        for face in self.mesh.faces:
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
        return self._vertex_shader(model_type), self._fragment_shader(model_type)

    def _vertex_shader(self, model_type):
        tex_w = self.baked.width
        tex_h = self.baked.height
        vertex_count = self.baked.vertex_count
        face_count = len(self.mesh.faces)

        face_lines = []
        for face in self.mesh.faces:
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
uniform sampler2D Sampler1;
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

const int TEX_W        = {tex_w};
const int TEX_H        = {tex_h};
const int VERTEX_COUNT = {vertex_count};
const int FACE_COUNT   = {face_count};
const int PPV          = 3;

const ivec3 FACES[{face_count}] = ivec3[](
{faces_array}
);

float decode(int high, int low, float mn, float mx) {{
    return mn + (float((high << 8) | low) / 65535.0) * (mx - mn);
}}

vec3 getVertex(int vi) {{
    int col = vi % (TEX_W / PPV);
    int row = vi / (TEX_W / PPV);
    vec4 p0 = texelFetch(Sampler0, ivec2(col * PPV + 0, row), 0);
    vec4 p1 = texelFetch(Sampler0, ivec2(col * PPV + 1, row), 0);
    float x = decode(int(p0.r*255.0), int(p0.g*255.0), -0.5,  0.5);
    float y = decode(int(p0.b*255.0), int(p0.a*255.0),  0.0,  1.0);
    float z = decode(int(p1.r*255.0), int(p1.g*255.0), -0.5,  0.5);
    return vec3(x, y, z);
}}

vec2 getUV(int vi) {{
    int col = vi % (TEX_W / PPV);
    int row = vi / (TEX_W / PPV);
    vec4 p1 = texelFetch(Sampler0, ivec2(col * PPV + 1, row), 0);
    vec4 p2 = texelFetch(Sampler0, ivec2(col * PPV + 2, row), 0);
    float u = decode(int(p1.b*255.0), int(p1.a*255.0), 0.0, 1.0);
    float v = decode(int(p2.r*255.0), int(p2.g*255.0), 0.0, 1.0);
    return vec2(u, v);
}}

void main() {{
    int faceIdx = gl_VertexID / 4;
    int corner  = gl_VertexID % 4;

    vec3 pos = Position;
    vec2 uv  = UV0;

    if (faceIdx < FACE_COUNT) {{
        ivec3 f = FACES[faceIdx];
        int vi = (corner == 0) ? f.x : (corner == 1) ? f.y : f.z;
        pos = getVertex(vi);
        uv  = getUV(vi);
    }}

    gl_Position    = ProjMat * ModelViewMat * vec4(pos, 1.0);
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
    float fog = smoothstep(FogStart, FogEnd, vertexDistance);
    fragColor = vec4(mix(color.rgb, FogColor.rgb, fog), color.a);
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
            "attributes": ["Position", "Color", "UV0", "UV1", "UV2", "Normal"],
            "samplers": [
                {"name": "Sampler0"},
                {"name": "Sampler1"},
                {"name": "Sampler2"}
            ],
            "uniforms": [
                {"name": "ModelViewMat",   "type": "matrix4x4", "count": 16, "values": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
                {"name": "ProjMat",        "type": "matrix4x4", "count": 16, "values": [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]},
                {"name": "ColorModulator", "type": "float",     "count": 4,  "values": [1,1,1,1]},
                {"name": "FogStart",       "type": "float",     "count": 1,  "values": [0]},
                {"name": "FogEnd",         "type": "float",     "count": 1,  "values": [1]},
                {"name": "FogColor",       "type": "float",     "count": 4,  "values": [0,0,0,1]},
                {"name": "FogShape",       "type": "int",       "count": 1,  "values": [0]}
            ]
        }
EOF

echo "✅ core/shader.py atualizado — limite removido"
python obj3mc.py goku_hair.obj -t item -o output_pack
