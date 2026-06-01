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
