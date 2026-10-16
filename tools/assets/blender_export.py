"""Blender (фон, без окна): склеенный GLB → shiba.usdz с анимацией «Clips» для RealityKit.

Запуск (CI, Linux):
    blender -b --factory-startup --python-exit-code 1 --python tools/assets/blender_export.py -- \
        --glb build/shiba_clips.glb --clips build/clips.json --style tools/assets/style_a.json \
        --out build/shiba.usdz

Вход — результат build_clips.py (одна анимация на всю шкалу). Шаги:
  1. пустая сцена, 24 fps, импорт GLB;
  2. чистка: камеры/свет удаляем, у арматуры проверяем активную action;
  3. материалы стиля A: Base Color из палитры, Metallic 0, Roughness 1, Specular 0, без Coat/Sheen;
  4. диапазон кадров = вся шкала из clips.json (0 … N), экспорт USDZ.
Параметры экспортёра фильтруются по тому, что есть в этой версии Blender (4.5 LTS / 5.x).
"""
import argparse
import json
import os
import sys

import bpy

FPS = 24


def log(*a):
    print("[blender_export]", *a, flush=True)


def args_after_dashes():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--glb", required=True)
    ap.add_argument("--clips", required=True)
    ap.add_argument("--style")
    ap.add_argument("--out", required=True)
    ap.add_argument("--bone-heuristic", default=None, help="BLENDER | TEMPERANCE | FORTUNE (по умолчанию — как в аддоне)")
    return ap.parse_args(argv)


def op_props(op):
    try:
        return {p.identifier for p in op.get_rna_type().properties}
    except Exception:  # noqa: BLE001
        return None


def call_filtered(op, name, **kw):
    props = op_props(op)
    if props is not None:
        dropped = sorted(k for k in kw if k not in props)
        kw = {k: v for k, v in kw.items() if k in props}
        if dropped:
            log(f"{name}: нет параметров в этой версии, пропущены: {dropped}")
    log(f"{name}({', '.join(f'{k}={v!r}' for k, v in kw.items())})")
    res = op(**kw)
    if "FINISHED" not in res:
        raise RuntimeError(f"{name} вернул {res}")


def srgb_hex_to_linear(h):
    h = h.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return out + [1.0]


def set_input(node, names, value):
    for n in names:
        sock = node.inputs.get(n)
        if sock is not None:
            sock.default_value = value
            return True
    return False


def style_materials(style):
    pal = style.get("materials", {}) if style else {}
    params = style.get("params", {}) if style else {}
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            mat.use_nodes = True
        bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            log(f"материал {mat.name}: нет Principled BSDF, пропуск")
            continue
        # glTF-импорт мог повесить на цвет узлы (vertex color/текстуры) — у Quaternius их нет,
        # но на всякий случай отцепляем, чтобы цвет брался из палитры
        base = pal.get(mat.name)
        if base:
            sock = bsdf.inputs.get("Base Color")
            for link in list(sock.links):
                mat.node_tree.links.remove(link)
            sock.default_value = srgb_hex_to_linear(base["color"])
            mat.diffuse_color = sock.default_value
        set_input(bsdf, ["Metallic"], float(params.get("metallic", 0.0)))
        set_input(bsdf, ["Roughness"], float(params.get("roughness", 1.0)))
        set_input(bsdf, ["Specular IOR Level", "Specular"], float(params.get("specular", 0.0)))
        set_input(bsdf, ["Coat Weight", "Clearcoat"], 0.0)
        set_input(bsdf, ["Sheen Weight", "Sheen"], 0.0)
        set_input(bsdf, ["Emission Strength"], 0.0)
        mat.metallic = float(params.get("metallic", 0.0))
        mat.roughness = float(params.get("roughness", 1.0))
        log(f"материал {mat.name}: {'палитра' if base else 'без цвета в палитре'}")


def ensure_action(arm):
    ad = arm.animation_data or arm.animation_data_create()
    if ad.action is None:
        cand = [a for a in bpy.data.actions if "Clips" in a.name] or list(bpy.data.actions)
        if not cand:
            raise RuntimeError("в GLB нет анимации")
        ad.action = cand[0]
    # Blender 4.4+: у action есть слоты; без слота анимация не играет
    if hasattr(ad, "action_slot") and getattr(ad, "action_slot", None) is None:
        slots = list(getattr(ad, "action_suitable_slots", []) or getattr(ad.action, "slots", []))
        if slots:
            ad.action_slot = slots[0]
    # NLA-дорожки от импорта не нужны: экспортируется активная action
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    log(f"action: {ad.action.name}, frame_range={tuple(ad.action.frame_range)}")
    return ad.action


def main():
    a = args_after_dashes()
    clips = json.load(open(a.clips, encoding="utf-8"))
    style = json.load(open(a.style, encoding="utf-8")) if a.style else None
    log("Blender", bpy.app.version_string)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        import addon_utils
        addon_utils.enable("io_scene_gltf2", default_set=True)
    except Exception as e:  # noqa: BLE001
        log("io_scene_gltf2:", e)

    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0

    imp = dict(filepath=os.path.abspath(a.glb), import_shading="NORMALS", merge_vertices=False,
               guess_original_bind_pose=True)
    if a.bone_heuristic:
        imp["bone_heuristic"] = a.bone_heuristic
    call_filtered(bpy.ops.import_scene.gltf, "import_scene.gltf", **imp)

    for ob in list(scene.objects):
        if ob.type in {"CAMERA", "LIGHT"}:
            bpy.data.objects.remove(ob, do_unlink=True)
    arms = [o for o in scene.objects if o.type == "ARMATURE"]
    meshes = [o for o in scene.objects if o.type == "MESH"]
    if len(arms) != 1 or not meshes:
        raise RuntimeError(f"ожидалась 1 арматура и меш, есть: арматур {len(arms)}, мешей {len(meshes)}")
    arm = arms[0]
    action = ensure_action(arm)

    style_materials(style)

    last = int(round(clips["duration"] * clips.get("fps", FPS)))
    scene.frame_start = 0
    scene.frame_end = last
    fr = action.frame_range
    if abs(fr[0]) > 0.01 or abs(fr[1] - last) > 1.01:
        log(f"ВНИМАНИЕ: action {tuple(fr)} не совпадает с clips.json 0..{last}")

    tris = 0
    for ob in meshes:
        ob.data.calc_loop_triangles()
        tris += len(ob.data.loop_triangles)
    log(f"меши: {len(meshes)}, треугольников: {tris}, костей: {len(arm.data.bones)}, кадры 0..{last}")

    out = os.path.abspath(a.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    exp = dict(
        filepath=out,
        selected_objects_only=False,
        visible_objects_only=False,
        export_animation=True,
        export_hair=False,
        export_uvmaps=True,
        export_normals=True,
        export_materials=True,
        generate_preview_surface=True,
        export_textures=False,
        export_armatures=True,
        only_deform_bones=False,   # 46 костей — мелочь; так иерархия скелета точно цела
        export_shapekeys=False,
        export_cameras=False,
        export_lights=False,
        triangulate_meshes=True,
        convert_orientation=True,  # Y вверх, морда к +Z — как в glTF и как ждёт RealityKit
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        convert_scene_units="METERS",
        root_prim_path="/root",
        evaluation_mode="RENDER",
    )
    call_filtered(bpy.ops.wm.usd_export, "wm.usd_export", **exp)
    log(f"готово: {out}, {os.path.getsize(out)} байт")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
