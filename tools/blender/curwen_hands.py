"""Builds stylized Curwen (solfege) hand signs and exports them for Godot.

Run headless (no Blender window needed):
  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
      -P tools/blender/curwen_hands.py -- <out.glb> [preview_dir]

One right hand, built from simple rounded parts (palm + jointed fingers +
thumb), posed seven ways. Each pose is a separate object named after its
syllable (do, re, mi, fa, sol, la, ti) so the app can show one at a time.
Units: metres, hand about 18 cm long. +Y is up, -Y... (Godot uses Y-up; the
glTF exporter converts Blender's Z-up automatically.)

Curwen signs (as the singer sees their own right hand, palm toward the floor
unless noted):
  do   closed fist, knuckles forward
  re   flat hand, fingers angled up about 40 degrees
  mi   flat hand, level
  fa   fist with the thumb pointing down
  sol  flat hand on edge, palm facing the singer, thumb up
  la   relaxed hand drooping down from the wrist
  ti   fist with the index finger pointing up and forward
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.abspath("curwen_hands.glb")
PREVIEW_DIR = argv[1] if len(argv) > 1 else ""

# ---------------------------------------------------------------- materials
def make_material(name, rgb, rough=0.55):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    m.diffuse_color = (*rgb, 1.0)  # viewport/workbench colour too
    return m

SKIN = make_material("HandWarm", (0.96, 0.78, 0.45))      # the app's warm gold
NAIL = make_material("HandLight", (1.0, 0.92, 0.75), 0.35)

# ---------------------------------------------------------------- parts
def capsule(name, length, radius, mat):
    """A finger segment: cylinder with round ends, from the origin along +X."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=radius, depth=length,
                                        location=(length / 2, 0, 0), rotation=(0, math.pi / 2, 0))
    seg = bpy.context.object
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=(length, 0, 0))
    tip = bpy.context.object
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=(0, 0, 0))
    root = bpy.context.object
    for o in (seg, tip, root):
        o.data.materials.append(mat)
    bpy.ops.object.select_all(action="DESELECT")
    for o in (seg, tip, root):
        o.select_set(True)
    bpy.context.view_layer.objects.active = seg
    bpy.ops.object.join()
    # Bake the cylinder's creation rotation so the segment runs along local +X,
    # then pivot at the joint (the segment's root) so posing rotates about the knuckle.
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    seg.name = name
    return seg


def palm(name):
    """Palm block: X along the fingers, Y across, Z thickness."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0.045, 0, 0))
    p = bpy.context.object
    p.scale = (0.095, 0.085, 0.030)
    bpy.ops.object.transform_apply(location=True, scale=True)
    bev = p.modifiers.new("round", "BEVEL")
    bev.width = 0.012
    bev.segments = 4
    p.data.materials.append(SKIN)
    p.name = name
    return p


# Finger layout on the palm's front edge (y across the hand).
FINGERS = {
    #           y      lengths (m)               radius
    "index":  (0.030, (0.042, 0.026, 0.020), 0.0095),
    "middle": (0.010, (0.046, 0.029, 0.021), 0.0100),
    "ring":   (-0.010, (0.043, 0.027, 0.020), 0.0095),
    "little": (-0.029, (0.034, 0.021, 0.017), 0.0085),
}


def build_finger(prefix, y, lengths, radius, curl, spread=0.0):
    """Three segments; curl = bend at each joint (radians, positive = toward palm)."""
    parts = []
    base = Matrix.Translation((0.092, y, 0.0)) @ Euler((0, 0, spread)).to_matrix().to_4x4()
    m = base
    for i, (length, bend) in enumerate(zip(lengths, curl)):
        m = m @ Euler((0, bend, 0)).to_matrix().to_4x4()
        seg = capsule(f"{prefix}_{i}", length, radius * (1.0 - 0.08 * i), SKIN if i < 2 else NAIL)
        seg.matrix_world = m
        parts.append(seg)
        m = m @ Matrix.Translation((length, 0, 0))
    return parts


def build_thumb(prefix, pose):
    """Thumb from the palm's index side. pose: 'side' (alongside), 'tuck' (over fingers),
    'up' (sticking up), 'down' (pointing down/forward)."""
    root = Matrix.Translation((0.020, 0.040, -0.004))
    angles = {
        "side": (Euler((0, 0, math.radians(35))), (0.15, 0.15)),
        "tuck": (Euler((0, math.radians(35), math.radians(-25))), (0.7, 0.6)),
        "up": (Euler((math.radians(-80), 0, math.radians(20))), (0.1, 0.1)),
        "down": (Euler((0, math.radians(80), math.radians(25))), (0.15, 0.1)),
    }
    rot, bends = angles[pose]
    m = root @ rot.to_matrix().to_4x4()
    parts = []
    for i, (length, bend) in enumerate(zip((0.036, 0.030), bends)):
        m = m @ Euler((0, bend, 0)).to_matrix().to_4x4()
        seg = capsule(f"{prefix}_t{i}", length, 0.0105 - 0.001 * i, SKIN if i == 0 else NAIL)
        seg.matrix_world = m
        parts.append(seg)
        m = m @ Matrix.Translation((length, 0, 0))
    return parts


FIST = (1.45, 1.55, 1.0)
FLAT = (0.0, 0.03, 0.03)
RELAXED_DROOP = (0.55, 0.45, 0.35)

# name: (finger curls by finger, thumb pose, whole-hand rotation (deg XYZ), height)
SIGNS = {
    "do":  ({"index": FIST, "middle": FIST, "ring": FIST, "little": FIST}, "tuck", (0, 0, 0), 0),
    "re":  ({"index": FLAT, "middle": FLAT, "ring": FLAT, "little": FLAT}, "side", (0, -40, 0), 1),
    "mi":  ({"index": FLAT, "middle": FLAT, "ring": FLAT, "little": FLAT}, "side", (0, 0, 0), 2),
    "fa":  ({"index": FIST, "middle": FIST, "ring": FIST, "little": FIST}, "down", (0, 0, 0), 3),
    "sol": ({"index": FLAT, "middle": FLAT, "ring": FLAT, "little": FLAT}, "up", (90, 0, 0), 4),
    "la":  ({"index": RELAXED_DROOP, "middle": RELAXED_DROOP, "ring": RELAXED_DROOP,
             "little": RELAXED_DROOP}, "side", (0, 35, 0), 5),
    "ti":  ({"index": (0.0, 0.05, 0.05), "middle": FIST, "ring": FIST, "little": FIST}, "tuck",
            (0, -45, 0), 6),
}


def build_sign(name, curls, thumb, rot_deg):
    p = palm(f"{name}_palm")
    parts = [p]
    for f, (y, lengths, radius) in FINGERS.items():
        spread = math.radians({"index": 4, "middle": 0, "ring": -4, "little": -9}[f])
        parts += build_finger(f"{name}_{f}", y, lengths, radius, curls[f], spread)
    parts += build_thumb(name, thumb)
    # Apply the palm's bevel before joining.
    bpy.context.view_layer.objects.active = p
    bpy.ops.object.select_all(action="DESELECT")
    p.select_set(True)
    bpy.ops.object.modifier_apply(modifier="round")
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = p
    bpy.ops.object.join()
    hand = bpy.context.object
    hand.name = name
    hand.data.name = name + "_mesh"
    # Pivot at the wrist; rotate as a whole.
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    hand.rotation_euler = Euler([math.radians(a) for a in rot_deg])
    bpy.ops.object.transform_apply(rotation=True)
    bpy.ops.object.shade_smooth()
    return hand


# ---------------------------------------------------------------- build
bpy.ops.wm.read_factory_settings(use_empty=True)
SKIN = make_material("HandWarm", (0.96, 0.78, 0.45))
NAIL = make_material("HandLight", (1.0, 0.92, 0.75), 0.35)

hands = []
for i, (name, (curls, thumb, rot, level)) in enumerate(SIGNS.items()):
    h = build_sign(name, curls, thumb, rot)
    hands.append((h, level))

# Lay them out side by side for previews; the app positions them itself, so
# reset to the origin before export.
for h, level in hands:
    h.location = (0, 0, 0)

bpy.ops.object.select_all(action="SELECT")
os.makedirs(os.path.dirname(OUT) or ".", exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_apply=True)
print("exported", OUT, "objects:", [h.name for h, _ in hands])

# ---------------------------------------------------------------- previews
if PREVIEW_DIR:
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.render.resolution_x = 360
    scene.render.resolution_y = 360
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("bg")
    scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 0.32
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    # The singer's view of their own hand is from behind/above; for a teacher
    # demonstrating, the learner sees the back of the hand from the front.
    # Preview from the front-right, slightly above.
    cam.location = (0.32, -0.30, 0.18)
    direction = Vector((0.06, 0.0, 0.0)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    for h, _ in hands:
        for other, _ in hands:
            other.hide_render = other is not h
        scene.render.filepath = os.path.join(PREVIEW_DIR, f"{h.name}.png")
        bpy.ops.render.render(write_still=True)
    print("previews in", PREVIEW_DIR)
