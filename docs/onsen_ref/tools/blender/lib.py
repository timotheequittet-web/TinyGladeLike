"""Procedural modeling helpers (copied from L'Effacement, D:\effacement\tools\blender\lib.py). Blender 4.2, -b --python.

Conventions:
- Characters face +Y in Blender (=> -Z in Godot after glTF Y-up conversion).
- Colors are given in sRGB hex/tuples and stored linear in a FLOAT_COLOR corner attribute "Col".
- Alpha < 1 marks emissive areas (the Godot toon shader reads 1 - alpha as emission).
- Pure magenta (#FF00FF) is replaced by the player's team color in game.
"""
import bpy
import bmesh
import math
import random
import os
from mathutils import Vector, Matrix, noise

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models")
OUT = os.path.normpath(OUT)
TEAM = "#ff00ff"


def lin1(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def col(c, a=1.0):
    """'#rrggbb' or (r,g,b) in sRGB 0..1 -> linear RGBA."""
    if isinstance(c, str):
        c = c.lstrip("#")
        c = tuple(int(c[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return (lin1(c[0]), lin1(c[1]), lin1(c[2]), a)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


# ------------------------------------------------------------------ objects
def _obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def _finish(ob, loc, rot, color, emit, bevel, smooth, grad, jitter):
    if bevel > 0:
        bevel_obj(ob, bevel)
    shade(ob, smooth)
    ob.location = Vector(loc)
    if rot:
        ob.rotation_euler = [math.radians(r) for r in rot]
        apply(ob)
    paint(ob, color, emit, grad, jitter)
    return ob


def box(name, size, loc=(0, 0, 0), color="#888888", rot=None, bevel=0.03, emit=False, smooth=40, grad=(0.82, 1.08), jitter=0.04, taper=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if taper and v.co.z > 0:
            v.co.x *= taper[0]
            v.co.y *= taper[1]
    ob = _obj(name, bm)
    return _finish(ob, loc, rot, color, emit, bevel, smooth, grad, jitter)


def cyl(name, r1, r2, depth, loc=(0, 0, 0), color="#888888", rot=None, verts=12, bevel=0.02, emit=False, smooth=40, grad=(0.82, 1.08), jitter=0.04, cap=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=verts, radius1=r1, radius2=r2, depth=depth)
    ob = _obj(name, bm)
    return _finish(ob, loc, rot, color, emit, bevel, smooth, grad, jitter)


def ball(name, r, loc=(0, 0, 0), color="#888888", scale=(1, 1, 1), rot=None, subdiv=2, emit=False, smooth=180, grad=(0.82, 1.08), jitter=0.04):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    ob = _obj(name, bm)
    return _finish(ob, loc, rot, color, emit, 0.0, smooth, grad, jitter)


def uvball(name, r, loc=(0, 0, 0), color="#888888", scale=(1, 1, 1), rot=None, segs=16, rings=8, emit=False, smooth=180, grad=(0.82, 1.08), jitter=0.04):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    for v in bm.verts:
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    ob = _obj(name, bm)
    return _finish(ob, loc, rot, color, emit, 0.0, smooth, grad, jitter)


def torus(name, R, r, loc=(0, 0, 0), color="#888888", rot=None, segs=24, rsegs=8, emit=False, grad=(0.9, 1.05), jitter=0.03):
    bm = bmesh.new()
    verts = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        ring = []
        for j in range(rsegs):
            b = 2 * math.pi * j / rsegs
            x = (R + r * math.cos(b)) * math.cos(a)
            y = (R + r * math.cos(b)) * math.sin(a)
            z = r * math.sin(b)
            ring.append(bm.verts.new((x, y, z)))
        verts.append(ring)
    for i in range(segs):
        for j in range(rsegs):
            a = verts[i][j]
            b = verts[(i + 1) % segs][j]
            c = verts[(i + 1) % segs][(j + 1) % rsegs]
            d = verts[i][(j + 1) % rsegs]
            bm.faces.new((a, b, c, d))
    bm.normal_update()
    ob = _obj(name, bm)
    return _finish(ob, loc, rot, color, emit, 0.0, 180, grad, jitter)


def prism(name, pts, height, loc=(0, 0, 0), color="#888888", rot=None, bevel=0.02, emit=False, smooth=30, grad=(0.85, 1.08), jitter=0.04):
    """Extrude a 2D polygon (XY) up by height."""
    bm = bmesh.new()
    vs = [bm.verts.new((p[0], p[1], 0)) for p in pts]
    f = bm.faces.new(vs)
    bm.normal_update()
    if f.normal.z < 0:
        f.normal_flip()
    r = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in r["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += height
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = _obj(name, bm)
    return _finish(ob, loc, rot, color, emit, bevel, smooth, grad, jitter)


def empty(name, loc=(0, 0, 0), parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    e.location = Vector(loc)
    if parent:
        set_parent(e, parent)
    return e


# ------------------------------------------------------------------ operations
def apply(ob):
    ob.data.transform(ob.matrix_basis)
    ob.matrix_basis = Matrix.Identity(4)


def bevel_obj(ob, width, segments=2):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    edges = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(30)]
    if edges:
        bmesh.ops.bevel(bm, geom=edges, offset=width, segments=segments, profile=0.5, affect='EDGES', clamp_overlap=True)
    bm.to_mesh(ob.data)
    bm.free()


def shade(ob, angle):
    """Smooth shading with hard edges above `angle` degrees (split edges = auto smooth)."""
    me = ob.data
    for p in me.polygons:
        p.use_smooth = angle > 0
    if 0 < angle < 180:
        bm = bmesh.new()
        bm.from_mesh(me)
        sharp = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(angle)]
        if sharp:
            bmesh.ops.split_edges(bm, edges=sharp)
        bm.to_mesh(me)
        bm.free()


def paint(ob, color, emit=False, grad=(0.82, 1.08), jitter=0.04, seed=None):
    """Fill the Col attribute with a vertical gradient + jitter (painted look)."""
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    attr = me.color_attributes["Col"]
    me.color_attributes.active_color = attr
    base = col(color, (1.0 - float(emit)) if emit else 1.0)
    zs = [v.co.z for v in me.vertices] or [0]
    z0, z1 = min(zs), max(zs)
    rnd = random.Random(seed if seed is not None else hash(ob.name) & 0xffff)
    vj = {}
    for li, loop in enumerate(me.loops):
        v = me.vertices[loop.vertex_index]
        t = (v.co.z - z0) / (z1 - z0) if z1 > z0 else 1.0
        g = grad[0] + (grad[1] - grad[0]) * t
        if loop.vertex_index not in vj:
            vj[loop.vertex_index] = 1.0 + rnd.uniform(-jitter, jitter)
        k = g * vj[loop.vertex_index]
        if emit:
            k = 1.0 if emit is True else 1.0
        if color == TEAM:
            attr.data[li].color = (1.0, 0.0, 1.0, base[3])
        else:
            attr.data[li].color = (base[0] * k, base[1] * k, base[2] * k, base[3])


def paint_by(ob, fn):
    """Custom per-vertex paint: fn(co, normal) -> (sRGB hex/tuple, emissive bool)."""
    me = ob.data
    if "Col" not in me.color_attributes:
        me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    attr = me.color_attributes["Col"]
    me.color_attributes.active_color = attr
    for li, loop in enumerate(me.loops):
        v = me.vertices[loop.vertex_index]
        c, e = fn(v.co, v.normal)
        attr.data[li].color = col(c, 0.0 if e else 1.0) if not isinstance(c, list) else c


def displace(ob, strength=0.3, scale=1.0, seed=0, axis_scale=(1, 1, 1)):
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    me = ob.data
    for v in me.vertices:
        p = v.co * scale + off
        n = noise.noise(p) + 0.5 * noise.noise(p * 2.3)
        d = v.co.normalized() if v.co.length > 0.0001 else Vector((0, 0, 1))
        v.co += Vector((d.x * axis_scale[0], d.y * axis_scale[1], d.z * axis_scale[2])) * n * strength


def decimate(ob, ratio):
    m = ob.modifiers.new("dec", 'DECIMATE')
    m.ratio = ratio
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="dec")


def subdivide(ob, levels=1):
    m = ob.modifiers.new("sub", 'SUBSURF')
    m.levels = levels
    m.render_levels = levels
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="sub")


def join(objs, name):
    objs = [o for o in objs if o is not None]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def set_origin(ob, point):
    point = Vector(point)
    ob.data.transform(Matrix.Translation(ob.location - point))
    ob.location = point


def set_parent(child, parent):
    bpy.context.view_layer.update()
    mw = child.matrix_world.copy()
    child.parent = parent
    child.matrix_world = mw


def part(name, objs, joint, parent=None):
    """Join objs into one rigid part whose origin is the joint, optionally parented."""
    ob = join(objs, name)
    set_origin(ob, joint)
    if parent:
        bpy.context.view_layer.update()
        set_parent(ob, parent)
    return ob


def mirror_x(ob, name):
    c = ob.copy()
    c.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(c)
    c.name = name
    c.data.transform(Matrix.Scale(-1, 4, (1, 0, 0)))
    c.location.x = -ob.location.x
    bm = bmesh.new()
    bm.from_mesh(c.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(c.data)
    bm.free()
    return c


def array_radial(ob, count, radius, name, z=0.0, start=0.0, face_out=True):
    out = [ob]
    for i in range(1, count):
        c = ob.copy()
        c.data = ob.data.copy()
        bpy.context.scene.collection.objects.link(c)
        out.append(c)
    for i, o in enumerate(out):
        a = start + 2 * math.pi * i / count
        o.data.transform(Matrix.Rotation(a, 4, 'Z') if face_out else Matrix.Identity(4))
        o.location = Vector((math.cos(a) * radius, math.sin(a) * radius, z))
        apply(o)
    return join(out, name)


def dup(ob, loc=None, rot=None, scale=None, name=None):
    c = ob.copy()
    c.data = ob.data.copy()
    bpy.context.scene.collection.objects.link(c)
    if name:
        c.name = name
    m = Matrix.Identity(4)
    if scale is not None:
        s = scale if isinstance(scale, (tuple, list)) else (scale, scale, scale)
        m = Matrix.Diagonal((s[0], s[1], s[2], 1.0)) @ m
    if rot is not None:
        m = (Matrix.Rotation(math.radians(rot[2]), 4, 'Z') @ Matrix.Rotation(math.radians(rot[1]), 4, 'Y') @ Matrix.Rotation(math.radians(rot[0]), 4, 'X')) @ m
    c.data.transform(m)
    if loc is not None:
        c.location = Vector(loc)
    apply(c)
    return c


# ------------------------------------------------------------------ export
def export(name, objs=None):
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    objs = objs if objs is not None else list(bpy.context.scene.objects)
    for o in objs:
        o.select_set(True)
        for c in o.children_recursive:
            c.select_set(True)
    # couleurs bornées à [0, 1] : les éclaircissements au hasard (× 1,12) dépassaient 1, et à l'import le canal
    # repassait à 0 (un rose devenait cyan, sur les massifs et la mousse du camphrier)
    for o in objs:
        for ob in [o] + list(o.children_recursive):
            if ob.type == 'MESH':
                for attr in ob.data.color_attributes:
                    for d in attr.data:
                        c = d.color
                        d.color = (min(max(c[0], 0.0), 1.0), min(max(c[1], 0.0), 1.0), min(max(c[2], 0.0), 1.0), min(max(c[3], 0.0), 1.0))
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
        export_vertex_color='ACTIVE', export_materials='NONE', export_animations=False,
        export_cameras=False, export_lights=False)
    print("EXPORTED", name)


def clear():
    for o in list(bpy.context.scene.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


def build(name, fn):
    """Clear, build via fn(), export everything in the scene as `name`."""
    clear()
    random.seed(hash(name) & 0xffff)
    fn()
    export(name)
