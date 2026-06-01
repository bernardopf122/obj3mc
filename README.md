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
