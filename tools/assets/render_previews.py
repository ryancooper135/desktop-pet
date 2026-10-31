"""Превью пса и вещей комнаты в Blender (волна 58): Workbench, без GPU-зависимых движков, цвет как в палитре.

Запуск (Blender 5.2, headless):
  blender -b --factory-startup --python-exit-code 1 --python tools/assets/render_previews.py -- \
      --glb build/shiba_clips.glb --clips build/shiba.clips.json --poses idle,sit,lie,sleep,paw \
      --style tools/assets/style_a.json --out-dir design/wave58/png/raw --prefix shiba
  # исходник Quaternius как есть (первый кадр его анимации):
  ... -- --glb tools/assets/source/shiba.glb --poses idle@0 --out-dir ... --prefix shiba_orig
  # сцена: пёс + миска + мячик из бандла, размеры как в комнате (пёс 0,42 м, миска r 0,09, мяч r 0,05):
  ... -- --glb build/shiba_clips.glb --clips build/shiba.clips.json --poses idle --scene \
      --bowl app/Resources/Pets/bowl.usdz --ball app/Resources/Pets/ball.usdz --out-dir ... --prefix scene_shiba

Поза — середина клипа из clips.json (имя) или «имя@кадр». Камера одна на все позы задания (общая рамка),
поэтому размеры поз сравнимы. Сон: глаза перекрашиваются по style.eyes_closed, как в приложении.
Листы собирает tools/assets/preview_sheets.py (обычный Python + Pillow).
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

DOG_HEIGHT = 0.42      # PetModel.height в PetStage.swift
BOWL_POS = (-0.30, -0.75)  # RoomPlan.Keep.bowlHome (x, z приложения)
BALL_POS = (0.15, 0.30)    # RoomPlan.Keep.ballHome
BOWL_COLOR = "#34323A"     # RoomColors.bowl — приложение красит миску сам


def args_after_dashes():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--clips")
    ap.add_argument("--poses", default="idle")
    ap.add_argument("--style")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--size", type=int, default=720)
    ap.add_argument("--yaw", type=float, default=35.0, help="градусы от фронта пса")
    ap.add_argument("--pitch", type=float, default=18.0)
    ap.add_argument("--scene", action="store_true")
    ap.add_argument("--studio", default="paint.sl", help="студийный свет Workbench (paint.sl — светлее, цвета ближе к палитре)")
    ap.add_argument("--bowl")
    ap.add_argument("--ball")
    return ap.parse_args(argv)


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgba(h):
    h = h.lstrip("#")
    return tuple(srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


def bsdf_of(mat):
    if not mat.use_nodes:
        return None
    return next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)


def sync_viewport_colors():
    """Workbench берёт diffuse_color; glTF/USD-импорт кладёт цвет в Base Color — переносим."""
    for mat in bpy.data.materials:
        b = bsdf_of(mat)
        if b is not None and not b.inputs["Base Color"].links:
            mat.diffuse_color = tuple(b.inputs["Base Color"].default_value)
        mat.roughness = 1.0
        mat.metallic = 0.0


def set_color(mat, rgba):
    b = bsdf_of(mat)
    if b is not None:
        for link in list(b.inputs["Base Color"].links):
            mat.node_tree.links.remove(link)
        b.inputs["Base Color"].default_value = rgba
    mat.diffuse_color = rgba


def import_any(path):
    before = set(bpy.data.objects)
    if path.lower().endswith((".usdz", ".usd", ".usda", ".usdc")):
        bpy.ops.wm.usd_import(filepath=os.path.abspath(path))
    else:
        bpy.ops.import_scene.gltf(filepath=os.path.abspath(path))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(o, do_unlink=True)
    return [o for o in bpy.data.objects if o not in before]


def world_points(objs):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in objs:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        pts.extend(mw @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    return pts


def bbox(pts):
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def root_of(objs):
    roots = [o for o in objs if o.parent is None]
    if len(roots) == 1:
        return roots[0]
    e = bpy.data.objects.new("root", None)
    bpy.context.scene.collection.objects.link(e)
    for o in roots:
        o.parent = e
    return e


def fit_prop(objs, radius, x, z_app):
    """Вещь в масштаб комнаты: наибольший горизонтальный радиус = radius, дно на полу, позиция как в приложении."""
    root = root_of(objs)
    bpy.context.view_layer.update()
    lo, hi = bbox(world_points(objs))
    r = max(hi.x - lo.x, hi.y - lo.y) / 2
    k = radius / r if r > 0 else 1.0
    root.scale = root.scale * k
    bpy.context.view_layer.update()
    lo, hi = bbox(world_points(objs))
    c = (lo + hi) / 2
    # приложение: x вправо, y вверх, z к камере; Blender после импорта: x, -z, y
    root.location += Vector((x - c.x, -z_app - c.y, -lo.z))
    bpy.context.view_layer.update()


def make_camera(points, yaw_deg, pitch_deg, margin=1.12):
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    # Пёс после glTF-импорта смотрит в -Y Blender (+Z glTF); камера спереди-сбоку и чуть сверху.
    d = Vector((math.sin(yaw) * math.cos(pitch), -math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    inv = rot.inverted()
    local = [inv @ p for p in points]
    xs, ys, zs = [p.x for p in local], [p.y for p in local], [p.z for p in local]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    span = max(max(xs) - min(xs), max(ys) - min(ys)) * margin
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = span
    cam_data.clip_start, cam_data.clip_end = 0.001, 100
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.matrix_world = rot @ Matrix.Translation(Vector((cx, cy, max(zs) + 5 * span)))
    bpy.context.scene.camera = cam
    return cam


def setup_render(size, studio):
    s = bpy.context.scene
    s.render.engine = "BLENDER_WORKBENCH"
    s.render.resolution_x = s.render.resolution_y = size
    s.render.resolution_percentage = 100
    s.render.film_transparent = True
    s.render.image_settings.file_format = "PNG"
    s.render.image_settings.color_mode = "RGBA"
    s.view_settings.view_transform = "Standard"   # палитра без тонмаппинга, как sRGB hex
    s.view_settings.look = "None"
    sh = s.display.shading
    sh.light = "STUDIO"
    try:
        sh.studio_light = studio
    except Exception as e:  # noqa: BLE001
        print("studio_light:", e)
    sh.color_type = "TEXTURE"
    sh.show_cavity = False
    sh.show_object_outline = False
    sh.show_shadows = True
    sh.shadow_intensity = 0.25
    s.display.light_direction = (0.35, -0.45, 0.82)
    try:
        s.display.render_aa = "16"
    except Exception:  # noqa: BLE001
        pass


def main():
    a = args_after_dashes()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        import addon_utils
        addon_utils.enable("io_scene_gltf2", default_set=True)
    except Exception as e:  # noqa: BLE001
        print("io_scene_gltf2:", e)
    scene = bpy.context.scene
    scene.render.fps = 24

    clips = json.load(open(a.clips, encoding="utf-8"))["clips"] if a.clips else {}
    style = json.load(open(a.style, encoding="utf-8")) if a.style else {}

    dog = import_any(a.glb)
    sync_viewport_colors()
    arm = next((o for o in dog if o.type == "ARMATURE"), None)
    if arm and arm.animation_data:
        for tr in list(arm.animation_data.nla_tracks):
            tr.mute = True
        idle = next((x for x in bpy.data.actions if "idle" in x.name.lower()), None)
        if not a.clips and idle is not None:   # исходник Quaternius: его собственный Idle
            arm.animation_data.action = idle
        elif arm.animation_data.action is None and bpy.data.actions:
            arm.animation_data.action = bpy.data.actions[0]
        ad = arm.animation_data
        if hasattr(ad, "action_slot") and ad.action is not None and ad.action_slot is None:
            slots = list(getattr(ad, "action_suitable_slots", []) or ad.action.slots)
            if slots:
                ad.action_slot = slots[0]
        print("action:", ad.action.name if ad.action else None)

    poses = []
    for spec in a.poses.split(","):
        name, _, fr = spec.partition("@")
        if fr:
            frame = int(fr)
        else:
            c = clips[name]
            frame = int(round((c["start"] + c["end"]) / 2 * 24))
        poses.append((name, frame))

    # пёс в масштаб комнаты: высота idle = 0,42 м, лапы на полу, центр в нуле
    droot = root_of(dog)
    scene.frame_set(poses[0][1])
    lo, hi = bbox(world_points(dog))
    k = DOG_HEIGHT / (hi.z - lo.z)
    droot.scale = droot.scale * k
    bpy.context.view_layer.update()
    lo, hi = bbox(world_points(dog))
    droot.location += Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    bpy.context.view_layer.update()

    extra = []
    if a.scene:
        if a.bowl:
            bowl = import_any(a.bowl)
            for o in bowl:
                for slot in getattr(o, "material_slots", []):
                    if slot.material:
                        set_color(slot.material, hex_rgba(BOWL_COLOR))
            fit_prop(bowl, 0.09, *BOWL_POS)
            extra += bowl
        if a.ball:
            ball = import_any(a.ball)
            sync_viewport_colors()
            fit_prop(ball, 0.05, *BALL_POS)
            extra += ball
        # коврик-круг вместо бесконечного пола: в Workbench светлый пол под углом уходит в серый
        bpy.ops.mesh.primitive_circle_add(vertices=64, radius=0.7, fill_type="NGON", location=(-0.05, 0.22, -0.001))
        floor = bpy.context.active_object
        fm = bpy.data.materials.new("floor")
        set_color(fm, hex_rgba("#FFFFFF"))
        floor.data.materials.append(fm)

    pts = []
    for _, fr in poses:
        scene.frame_set(fr)
        pts += world_points(dog + extra)
    make_camera(pts, a.yaw, a.pitch, margin=1.08 if a.scene else 1.12)
    setup_render(a.size, a.studio)

    closed = style.get("eyes_closed", {})
    pal = style.get("materials", {})
    os.makedirs(a.out_dir, exist_ok=True)
    for name, fr in poses:
        swapped = {}
        if name == "sleep" and closed:
            for mname, to in closed.items():
                m = bpy.data.materials.get(mname)
                if m is not None and to in pal:
                    swapped[m] = tuple(m.diffuse_color)
                    m.diffuse_color = hex_rgba(pal[to]["color"])
        scene.frame_set(fr)
        scene.render.filepath = os.path.abspath(os.path.join(a.out_dir, f"{a.prefix}_{name}.png"))
        bpy.ops.render.render(write_still=True)
        print(f"render {a.prefix}_{name} frame {fr}")
        for m, c in swapped.items():
            m.diffuse_color = c


if __name__ == "__main__":
    main()
