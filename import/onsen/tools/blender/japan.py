"""Modèles japonais de L'onsen de la colline, dans le style de L'Effacement.
blender -b --factory-startup --python japan.py -- [noms...]   (sans nom : tout reconstruire)

Conventions (celles de lib.py) : Z vers le haut dans Blender, couleurs sRGB stockées en linéaire,
alpha 0 = s'allume la nuit (le shader du jeu lit l'alpha des sommets).
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from lib import _obj
import bmesh
from mathutils import Vector, Matrix, noise as mnoise

VERMILION = "#c8452c"
BLACK = "#2a2422"


def _mix(a, b, t):
    ca, cb = col(a), col(b)
    return [ca[i] + (cb[i] - ca[i]) * t for i in range(3)] + [1.0]


def _rock_paint(base, moss, dark, moss_amount=0.55):
    b, d, m = col(base), col(dark), col(moss)

    def f(co, n):
        k = 0.5 + 0.5 * math.sin(co.z * 3.1 + mnoise.noise(co * 0.7) * 2.0)
        c = [d[i] + (b[i] - d[i]) * (0.55 + 0.45 * k) for i in range(3)]
        top = max(0.0, min(1.0, (n.z - moss_amount) * 4.0 + mnoise.noise(co * 1.3) * 0.6))
        c = [c[i] + (m[i] - c[i]) * top for i in range(3)]
        return [c[0], c[1], c[2], 1.0], False
    return f


# ================================================================ cerisiers
def _tube(name, pts, radii, sides=7, seed=0, wobble=0.18):
    """Branche facettée le long de pts, pointe fermée (repris de L'Effacement)."""
    bm = bmesh.new()
    rings = []
    a = None
    for i, p in enumerate(pts):
        d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized() if a is None else (a - d * a.dot(d)).normalized()
        b = d.cross(a)
        ring = []
        for k in range(sides):
            t = 2 * math.pi * k / sides
            w = 1.0 + wobble * mnoise.noise(p * 1.7 + Vector((k * 3.1, seed, 0)))
            ring.append(bm.verts.new(p + (a * math.cos(t) + b * math.sin(t)) * radii[i] * w))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
    tip = bm.verts.new(pts[-1] + (pts[-1] - pts[-2]).normalized() * radii[-1] * 2.0)
    for k in range(sides):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % sides], tip))
    bm.normal_update()
    return _obj(name, bm)


def _limb(rnd, start, direction, length, r0, r1, steps, gnarl, rise=0.0):
    pts, radii = [start], [r0]
    d = direction.normalized()
    for i in range(1, steps + 1):
        d = (d + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-0.5, 0.5) + rise)) * gnarl).normalized()
        pts.append(pts[-1] + d * length / steps)
        radii.append(r0 + (r1 - r0) * i / steps)
    return pts, radii


def _bark(ob):
    def f(co, n):
        k = 0.5 + 0.5 * mnoise.noise(Vector((co.x * 3.0, co.y * 3.0, co.z * 0.6)))
        return _mix("#2b1e1a", "#5a4038", min(1.0, k + max(0.0, n.z) * 0.25)), False
    paint_by(ob, f)


def _sakura_wood(variant):
    """Tronc court et tordu qui s'ouvre en larges branches presque horizontales (silhouette en parasol)."""
    rnd = random.Random(variant * 211)
    H = 2.1 + variant * 0.3
    lean = Vector((rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 1.0))
    pts, radii = _limb(rnd, Vector((0, 0, -0.5)), lean, H + 0.5, 0.55, 0.32, 5, 0.18)
    radii[0] *= 1.6
    objs = [_tube("trunk", pts, radii, 9, variant)]
    for i in range(4):   # racines qui s'agrippent au sol
        az = i * math.pi / 2 + rnd.uniform(-0.4, 0.4)
        p, r = _limb(rnd, Vector((0, 0, 0.35)), Vector((math.cos(az), math.sin(az), -0.4)), 1.4, 0.3, 0.06, 3, 0.15)
        objs.append(_tube(f"root{i}", p, r, 6, i))
    tips = []
    n = 4 + variant % 2
    for i in range(n):
        az = i * 2 * math.pi / n + rnd.uniform(-0.35, 0.35)
        base = pts[-1] if i % 2 == 0 else pts[-2]
        p, r = _limb(rnd, base, Vector((math.cos(az), math.sin(az), rnd.uniform(0.35, 0.7))), rnd.uniform(3.0, 4.2), 0.24, 0.07, 5, 0.25, 0.05)
        objs.append(_tube(f"limb{i}", p, r, 7, i + 10))
        tips.append(p[-1])
        tips.append(p[len(p) // 2] + Vector((0, 0, 0.5)))
        for j in range(2):
            fk = rnd.randint(2, 4)
            az2 = az + (j - 0.5) * rnd.uniform(1.0, 1.6)
            p2, r2 = _limb(rnd, p[fk], Vector((math.cos(az2), math.sin(az2), rnd.uniform(0.1, 0.5))), rnd.uniform(1.6, 2.4), r[fk] * 0.6, 0.03, 3, 0.3, 0.0)
            objs.append(_tube(f"twig{i}_{j}", p2, r2, 5, i * 7 + j))
            tips.append(p2[-1])
    return objs, tips


SAKURA_PALETTES = [("#d07a93", "#f2adc0", "#fcd3df"), ("#c9728d", "#ee9fb6", "#fad0dc"), ("#d6849b", "#f5b6c6", "#fcd8e2")]


def _blossom_crown(variant, tips, rnd, palette=None, scale=1.0):
    """Nuages de fleurs : un cœur rond et doux (ombré lisse) hérissé de petits éclats de pétales."""
    dark, mid, light = [col(c) for c in (palette or SAKURA_PALETTES[variant - 1])]
    bm = bmesh.new()
    face_cols = {}
    smooth_faces = set()
    zs = [t.z for t in tips]
    z0, z1 = min(zs) - 1.5, max(zs) + 1.5
    for ci, t in enumerate(tips):
        c = t + Vector((0, 0, 0.35))
        rad = rnd.uniform(1.15, 1.6) * scale
        core = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=rad * 0.98)["verts"]
        for v in core:
            v.co = c + Vector((v.co.x, v.co.y, v.co.z * 0.72)) * (1.0 + 0.18 * mnoise.noise(v.co * 2.0 + c))
        for f in {f for v in core for f in v.link_faces}:
            k = max(0.0, min(1.0, (f.calc_center_median().z - z0) / (z1 - z0) * 0.7 + 0.15))
            face_cols[f] = [dark[i] + (mid[i] - dark[i]) * k for i in range(3)]
            smooth_faces.add(f)
        for li in range(int(34 * scale * scale)):
            u = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
            u.z = u.z * 0.7 + 0.1
            dist = rad * (0.78 + 0.28 * math.sqrt(rnd.random()))
            p = c + u * dist
            s = rnd.uniform(0.24, 0.38) * math.sqrt(scale)
            q = (Matrix.Rotation(rnd.uniform(0, 6.28), 4, 'Z') @ Matrix.Rotation(rnd.uniform(-0.9, 0.9), 4, 'X')
                 @ Matrix.Rotation(rnd.uniform(-0.6, 0.6), 4, 'Y'))
            vs = [bm.verts.new(p + (q @ Vector(o)) * s) for o in
                  ((1, 0, 0), (-0.6, 0.6, 0), (-0.6, -0.6, 0), (0, 0, 0.2), (0, 0, -0.2))]
            fs = [bm.faces.new((vs[i], vs[(i + 1) % 3], vs[3])) for i in range(3)]
            fs += [bm.faces.new((vs[(i + 1) % 3], vs[i], vs[4])) for i in range(3)]
            t2 = (p.z - z0) / (z1 - z0) * 0.5 + (dist / rad) * 0.4 + mnoise.noise(p * 0.6) * 0.2 + rnd.uniform(-0.1, 0.1)
            t2 = max(0.0, min(1.0, t2))
            cc = [dark[i] + (mid[i] - dark[i]) * min(t2 * 2, 1) for i in range(3)] if t2 < 0.5 else \
                 [mid[i] + (light[i] - mid[i]) * (t2 - 0.5) * 2 for i in range(3)]
            for f in fs:
                face_cols[f] = cc
    bm.normal_update()
    order = {f: i for i, f in enumerate(bm.faces)}
    fc = [None] * len(bm.faces)
    sm = [False] * len(bm.faces)
    for f, cc in face_cols.items():
        fc[order[f]] = cc
        sm[order[f]] = f in smooth_faces
    me = bpy.data.meshes.new("crown")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("crown", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = sm[p.index]
    attr = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    me.color_attributes.active_color = attr
    for p in me.polygons:
        cc = fc[p.index] or dark
        for li in p.loop_indices:
            attr.data[li].color = (cc[0], cc[1], cc[2], 1.0)
    return ob


def sakura(variant):
    wood, tips = _sakura_wood(variant)
    for o in wood:
        _bark(o)
    crown = _blossom_crown(variant, tips, random.Random(variant * 13 + 5))
    join(wood + [crown], f"sakura_{variant}")


def sakura_shadow(variant):
    """Ombre légère : le bois et une boule bosselée par grappe."""
    wood, tips = _sakura_wood(variant)
    rnd = random.Random(variant * 13 + 5)
    blobs = []
    for i, t in enumerate(tips):
        rad = rnd.uniform(1.15, 1.6)
        b = ball(f"blob{i}", rad, t + Vector((0, 0, 0.35)), "#333333", scale=(1, 1, 0.75), subdiv=1, smooth=0)
        blobs.append(b)
    join(wood + blobs, f"sakura_{variant}_shadow")


# ================================================================ pin noir japonais (kuromatsu)
def _matsu_wood(variant):
    """Tronc qui penche et se tord en S, puis quelques longues branches presque horizontales (niwaki taillé)."""
    rnd = random.Random(variant * 97 + 3)
    lean = rnd.uniform(0.0, 2 * math.pi)
    side = Vector((math.cos(lean), math.sin(lean), 0))
    pts, radii = [Vector((0, 0, -0.5))], [0.62]
    H = 6.0 + variant * 0.6
    for i in range(1, 9):   # S : part d'un côté, revient de l'autre en montant
        u = i / 8.0
        off = side * (math.sin(u * math.pi * 1.3) * 1.7 + u * 0.8) + Vector((rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15), 0))
        pts.append(Vector((off.x, off.y, -0.5 + u * (H + 0.5))))
        radii.append(0.5 * (1.0 - u * 0.72))
    radii[0] *= 1.5
    objs = [_tube("trunk", pts, radii, 10, variant, wobble=0.24)]
    for i in range(3):   # racines
        az = lean + math.pi + (i - 1) * 1.1
        p, r = _limb(rnd, Vector((0, 0, 0.3)), Vector((math.cos(az), math.sin(az), -0.45)), 1.3, 0.3, 0.06, 3, 0.15)
        objs.append(_tube(f"root{i}", p, r, 6, i))
    pads = []   # [centre, rayon] des plateaux d'aiguilles
    n = 5 + variant % 2
    for i in range(n):
        k = 3 + i * (len(pts) - 4) // n
        az = lean + i * 2.4 + rnd.uniform(-0.3, 0.3)
        length = rnd.uniform(2.2, 3.4) * (1.0 - i / (n + 2))
        p, r = _limb(rnd, pts[k], Vector((math.cos(az), math.sin(az), rnd.uniform(-0.05, 0.25))), length, radii[k] * 0.55, 0.06, 4, 0.22, 0.02)
        objs.append(_tube(f"limb{i}", p, r, 7, i + 10))
        pads.append([p[-1] + Vector((0, 0, 0.25)), rnd.uniform(1.1, 1.5) * (1.0 - i / (n + 4))])
        if i % 2 == 0:   # un plateau plus petit à mi-branche
            pads.append([p[2] + Vector((0, 0, 0.35)), rnd.uniform(0.7, 0.9)])
    pads.append([pts[-1] + Vector((0, 0, 0.3)), 1.3])   # couronne au sommet
    return objs, pads


def _matsu_pads(pads, rnd):
    """Plateaux d'aiguilles : coussins plats (taille en nuages), sombres dessous, vert vif au-dessus."""
    dark, mid, light = col("#1f3a24"), col("#2f5a2e"), col("#5f8a3c")
    parts = []
    for i, (c, rad) in enumerate(pads):
        b = ball(f"pad{i}", rad, c, "#2f5a2e", scale=(1.25, 1.0, 0.42), rot=(0, 0, rnd.uniform(0, 360)), subdiv=2, smooth=180)
        for v in b.data.vertices:   # bosselé autour de son centre (rot= a déjà appliqué la position)
            v.co = c + (v.co - c) * (1.0 + 0.16 * mnoise.noise(v.co * 1.6))

        def f(co, n, c=c, rad=rad):
            k = max(0.0, min(1.0, 0.5 + (co.z - c.z) / (rad * 0.8) + mnoise.noise(co * 1.1) * 0.25))
            cc = [dark[j] + (mid[j] - dark[j]) * min(k * 2, 1) for j in range(3)] if k < 0.5 else \
                 [mid[j] + (light[j] - mid[j]) * (k - 0.5) * 2 for j in range(3)]
            return cc + [1.0], False
        paint_by(b, f)
        parts.append(b)
    return parts


def _matsu_bark(ob):
    def f(co, n):
        k = 0.5 + 0.5 * mnoise.noise(Vector((co.x * 4.0, co.y * 4.0, co.z * 1.2)))   # écorce en plaques
        return _mix("#2a2220", "#5b4a42", min(1.0, k * 0.9 + max(0.0, n.z) * 0.2)), False
    paint_by(ob, f)


def matsu(variant):
    wood, pads = _matsu_wood(variant)
    for o in wood:
        _matsu_bark(o)
    join(wood + _matsu_pads(pads, random.Random(variant * 5 + 1)), f"matsu_{variant}")


# ================================================================ sapin (forêts des versants)
def momi(variant):
    """Sapin des versants (≈ 9 m) : fût droit, étages de branches qui retombent, de plus en plus courts vers une
    pointe un peu penchée. Chaque étage = des coussins aplatis autour du fût (les cartes d'aiguilles s'y posent)."""
    rnd = random.Random(variant * 53 + 7)
    H = 8.4 + variant * 0.5
    lean = Vector((rnd.uniform(-0.12, 0.12), rnd.uniform(-0.12, 0.12), 1.0))
    pts, radii = _limb(rnd, Vector((0, 0, -0.4)), lean, H, 0.34, 0.05, 6, 0.04)
    radii[0] *= 1.4
    wood = [_tube("trunk", pts, radii, 8, variant, wobble=0.12)]
    dark, mid, light = col("#1d3a2c"), col("#2d5a3c"), col("#5a8a48")
    tiers = 10 + variant % 2
    pads = []
    for t in range(tiers):
        u = t / (tiers - 1)
        z = 1.5 + u * (H - 2.1)
        axis = Vector((0, 0, -0.4)) + lean.normalized() * (z + 0.4)   # le fût au niveau de l'étage
        reach = (1.0 - u) * 1.9 + 0.4   # étages larges en bas, pointe fine
        n = max(3, int(7 - u * 4))
        a0 = rnd.uniform(0, 2 * math.pi)
        for k in range(n):
            a = a0 + k * 2 * math.pi / n + rnd.uniform(-0.25, 0.25)
            d = reach * rnd.uniform(0.4, 0.62)
            c = axis + Vector((math.cos(a) * d, math.sin(a) * d, -d * 0.28))   # la branche retombe vers son bout
            r = reach * rnd.uniform(0.58, 0.72)
            b = ball(f"t{t}_{k}", r, c, "#2d5a3c", scale=(1.25, 1.25, 0.5), rot=(0, 0, math.degrees(a)), subdiv=1, smooth=180)
            pads.append((b, z, u))
    pads.append((ball("tip", 0.5, pts[-1] + Vector((0, 0, -0.2)), "#2d5a3c", scale=(1, 1, 1.6), subdiv=1, smooth=180), H, 1.0))
    parts = []
    for b, z, u in pads:
        def f(co, nrm, z=z, u=u):
            # sombre dessous et près du fût, clair sur le dessus de chaque étage et vers la pointe
            k = max(0.0, min(1.0, 0.45 + (co.z - z) * 1.2 + u * 0.25 + mnoise.noise(co * 0.9) * 0.2))
            cc = [dark[j] + (mid[j] - dark[j]) * min(k * 2, 1) for j in range(3)] if k < 0.5 else \
                 [mid[j] + (light[j] - mid[j]) * (k - 0.5) * 2 for j in range(3)]
            return cc + [1.0], False
        paint_by(b, f)
        parts.append(b)
    for o in wood:
        _matsu_bark(o)
    join(wood + parts, f"momi_{variant}")


def momi_shadow(variant):
    """Ombre légère du sapin : le fût et trois cônes empilés aux proportions des étages (les cartes n'en projettent pas)."""
    rnd = random.Random(variant * 53 + 7)
    H = 8.4 + variant * 0.5
    parts = [cyl("trunk", 0.25, 0.35, H * 0.4, (0, 0, H * 0.2), "#333333", verts=6, bevel=0)]
    for k, (z0, r) in enumerate([(1.0, 2.3), (H * 0.36, 1.7), (H * 0.62, 1.0)]):
        h = H * 0.42 if k < 2 else H * 0.42
        parts.append(cyl(f"cone{k}", 0.05, r, h, (0, 0, z0 + h * 0.5), "#333333", verts=8, bevel=0))
    join(parts, f"momi_{variant}_shadow")


def momi_1(): momi(1)
def momi_2(): momi(2)
def momi_1_shadow(): momi_shadow(1)


def matsu_1(): matsu(1)
def matsu_2(): matsu(2)


def sakura_1(): sakura(1)
def sakura_2(): sakura(2)
def sakura_3(): sakura(3)
def sakura_1_shadow(): sakura_shadow(1)
def sakura_2_shadow(): sakura_shadow(2)
def sakura_3_shadow(): sakura_shadow(3)


# ================================================================ torii
def _bent_beam(name, length, depth, height, z, lift, color):
    """Linteau dont les extrémités se relèvent en douceur (kasagi)."""
    o = box(name, (length, depth, height), (0, 0, 0), color, bevel=0, smooth=0)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.x - e.verts[1].co.x) > 0.1], cuts=14)
    for v in bm.verts:
        t = abs(v.co.x) / (length * 0.5)
        v.co.z += lift * t ** 7.0   # seules les extrémités se relèvent
        if v.co.z > 0:
            v.co.y *= 1.0 - 0.15 * t   # les bouts s'affinent un peu
    bm.to_mesh(o.data)
    bm.free()
    bevel_obj(o, 0.03)
    shade(o, 40)
    o.location.z = z
    apply(o)
    paint(o, color, grad=(0.85, 1.05))
    return o


def torii(span, h, name):
    """Torii : piliers vermillon sur socle noir, entretoise (nuki), linteau noir relevé (kasagi), plaque."""
    parts = []
    for sx in (-1, 1):
        x = sx * span * 0.5
        parts.append(cyl(f"pillar{sx}", 0.26, 0.21, h, (x, 0, h * 0.5), VERMILION, verts=16, bevel=0, smooth=180, grad=(0.75, 1.05)))
        parts.append(cyl(f"base{sx}", 0.34, 0.31, 0.5, (x, 0, 0.25), BLACK, verts=16, bevel=0.02, smooth=180))
        parts.append(box(f"wedge{sx}", (0.12, 0.42, 0.22), (x + sx * 0.32, 0, h * 0.78), BLACK, bevel=0.01))
    parts.append(box("nuki", (span + 1.2, 0.26, 0.24), (0, 0, h * 0.78), VERMILION, bevel=0.02))
    parts.append(box("shimaki", (span + 2.0, 0.42, 0.24), (0, 0, h + 0.06), VERMILION, bevel=0.02))
    parts.append(_bent_beam("kasagi", span + 3.0, 0.62, 0.34, h + 0.33, 0.34, BLACK))
    parts.append(box("gakuzuka", (0.22, 0.24, h * 0.22 - 0.1), (0, 0, h * 0.89), VERMILION, bevel=0.01))
    parts.append(box("plaque", (0.55, 0.12, 0.75), (0, -0.14, h * 0.9), BLACK, bevel=0.02))
    parts.append(box("plaque_or", (0.4, 0.13, 0.6), (0, -0.15, h * 0.9), "#c9a24a", bevel=0.0))
    join(parts, name)


def torii_3(): torii(2.6, 3.2, "torii_3")
def torii_4(): torii(4.4, 4.2, "torii_4")
def torii_6(): torii(6.0, 5.6, "torii_6")
def torii_7(): torii(7.2, 4.6, "torii_7")


# ================================================================ lanterne de pierre
def _hex(name, r1, r2, h, z, color, lift=0.0):
    o = cyl(name, r1, r2, h, (0, 0, z), color, verts=6, bevel=0.015, smooth=0)
    if lift > 0.0:   # coins relevés du toit (warabite)
        for v in o.data.vertices:
            rr = Vector((v.co.x, v.co.y, 0)).length
            if rr > r1 * 0.9:
                v.co.z += lift
    return o


def toro():
    """Lanterne kasuga-dōrō (≈ 2,3 m) : la chambre de lumière s'allume la nuit, mousse sur les dessus."""
    stone, moss, dark = "#a39d91", "#7d9448", "#6c675f"
    parts = [
        _hex("kiso", 0.5, 0.44, 0.28, 0.14, stone),
        cyl("kiso2", 0.3, 0.26, 0.18, (0, 0, 0.37), stone, verts=12, bevel=0.01, smooth=0),
        cyl("sao", 0.15, 0.14, 0.95, (0, 0, 0.93), stone, verts=12, bevel=0, smooth=180),
        cyl("ring", 0.19, 0.19, 0.08, (0, 0, 0.93), stone, verts=12, bevel=0.01, smooth=0),
        _hex("chudai", 0.42, 0.32, 0.22, 1.5, stone),
        _hex("glow", 0.25, 0.25, 0.4, 1.81, "#ffd89a"),
    ]
    paint(parts[-1], "#ffd89a", emit=True)
    for i in range(6):   # montants de la chambre de lumière
        a = i * math.pi / 3
        parts.append(box(f"post{i}", (0.07, 0.07, 0.42), (math.cos(a) * 0.29, math.sin(a) * 0.29, 1.81), stone, bevel=0.0, smooth=0))
    parts.append(_hex("kasa", 0.66, 0.18, 0.34, 2.18, stone, lift=0.07))
    parts.append(ball("hoju", 0.13, (0, 0, 2.47), stone, scale=(1, 1, 1.15), subdiv=2))
    parts.append(cyl("hoju_tip", 0.0, 0.07, 0.12, (0, 0, 2.62), stone, verts=8, bevel=0))
    ob = join(parts, "toro")
    paint_moss = _rock_paint(stone, moss, dark, 0.6)
    me = ob.data
    attr = me.color_attributes["Col"]
    for li, loop in enumerate(me.loops):
        c = attr.data[li].color
        if c[3] < 0.5:
            continue   # garder la lumière
        v = me.vertices[loop.vertex_index]
        attr.data[li].color = paint_moss(v.co, v.normal)[0]


# ================================================================ rochers de bord
def ledge(variant):
    """Gros rocher arrondi et moussu pour le bord du plateau (l'île rocheuse du concept)."""
    sizes = [(3.2, 2.4, 2.2), (2.6, 2.2, 1.6), (4.0, 2.8, 2.6)]
    o = ball("ledge", 1.0, (0, 0, 0), "#9a9286", scale=sizes[variant - 1], subdiv=3, smooth=180)
    displace(o, 0.32 * min(sizes[variant - 1]), 0.7, variant * 9)
    for v in o.data.vertices:
        if v.co.z < -0.6:
            v.co.z = -0.6 + (v.co.z + 0.6) * 0.5
    shade(o, 180)
    paint_by(o, _rock_paint("#a39c90", "#66803a", "#6a645c", 0.5))
    o.name = f"ledge_{variant}"


def ledge_1(): ledge(1)
def ledge_2(): ledge(2)
def ledge_3(): ledge(3)


# ================================================================ toits
def _roof_surface(name, ridge, height, droop, lift, color, alpha, thickness=0.035, edge=None, gable=None):
    """Toit en croupe sur une emprise 1 x 1 (X = longueur, Y = profondeur), faîtage le long de X.
    Pans légèrement concaves (droop) et coins relevés (lift) : la silhouette des toits japonais.
    gable = (vb, xg) : irimoya — les croupes s'arrêtent à la hauteur relative vb, les pans longs montent jusqu'au
    faîtage avec une demi-longueur xg, laissant un pignon vertical en x = ±xg (ridge est alors ignoré)."""
    n = 10
    bm = bmesh.new()
    # une grille par pan : u le long de la rive (-1..1), v de la rive (0) au faîtage (1)
    def half_x(v):
        if gable:
            return 0.5 - (0.5 - gable[1]) * min(v / gable[0], 1.0)
        return 0.5 - (0.5 - ridge) * v
    def pt(side, u, v):
        if side in (0, 1):   # pans longs (devant / derrière)
            y = (0.5 - 0.5 * v) * (1 if side == 0 else -1)
            x = u * half_x(v)
        else:                # croupes (jusqu'à la cassure du pignon en irimoya)
            if gable:
                v *= gable[0]
            x = half_x(v) * (1 if side == 2 else -1)
            yr = 0.5 * (1 - v)
            y = u * yr
        z = height * v - droop * math.sin(math.pi * v) * 0.5
        corner = abs(u) ** 6 * (1 - v) ** 2
        return Vector((x, y, z + lift * corner))
    for side in range(4):
        rows = []
        for j in range(n + 1):
            v = j / n
            row = [bm.verts.new(pt(side, -1 + 2 * i / n, v)) for i in range(n + 1)]
            rows.append(row)
        for j in range(n):
            for i in range(n):
                f = bm.faces.new((rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < 0:
            f.normal_flip()
    ob = _obj(name, bm)
    sol = ob.modifiers.new("sol", 'SOLIDIFY')
    sol.thickness = thickness
    sol.offset = -1
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="sol")
    shade(ob, 50)
    c = col(color, alpha)
    dark = col("#3a2a22")
    me = ob.data
    attr = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    me.color_attributes.active_color = attr
    cut = col(edge, alpha) if edge else None
    for p in me.polygons:
        under = p.normal.z < 0.15
        k = 0.85 + 0.25 * max(0.0, min(1.0, p.center.z / max(height, 0.01)))
        cc = (dark[0], dark[1], dark[2], 1.0) if under else (c[0] * k, c[1] * k, c[2] * k, c[3])
        if cut and p.normal.z < 0.35:   # tranche du chaume au bord du toit : paille coupée, claire
            # (penchée comme le dessous du toit : on la reconnaît à sa forme de bande, large de l'épaisseur)
            vs = [me.vertices[i].co for i in p.vertices]
            short = min((vs[i] - vs[(i + 1) % len(vs)]).length for i in range(len(vs)))
            if short < thickness * 1.5:
                cc = (cut[0], cut[1], cut[2], cut[3])
        for li in p.loop_indices:
            attr.data[li].color = cc
    return ob


def roof_tile():
    """Toit de tuiles irimoya : croupe concave, coins relevés, petit pignon blanc, faîtage aux bouts ornés."""
    h = 0.42
    parts = [_roof_surface("pans", 0.24, h, 0.06, 0.07, "#5b687d", 0.7)]
    for sx in (-1, 1):   # pignons (irimoya)
        gab = prism(f"gable{sx}", [(-0.13, 0), (0.13, 0), (0, 0.15)], 0.02, (sx * 0.235, 0, h - 0.15), "#e3d6bb", rot=(90, 0, 90), bevel=0)
        parts.append(gab)
        parts.append(box(f"oni{sx}", (0.05, 0.07, 0.07), (sx * 0.26, 0, h + 0.035), "#2f3540", bevel=0.005))
    parts.append(box("ridge", (0.5, 0.05, 0.04), (0, 0, h + 0.012), "#3c4554", bevel=0.005))
    join(parts, "roof_tile")


def roof_thatch():
    """Toit de chaume (kayabuki) : épais, pans à peine bombés, tranche de paille coupée claire au bord ;
    faîtage en botte de paille sombre coiffé de traverses de bois (karasu-odori), comme les fermes de Totoro.
    Le grain (rangs, brins, mousse, paille grisée) est peint par toon.gdshader (alpha 0,6 = chaume)."""
    h = 0.46
    parts = [_roof_surface("pans", 0.2, h, -0.03, 0.0, "#86683a", 0.6, thickness=0.075, edge="#c4a46a")]
    parts.append(cyl("ridge", 0.055, 0.055, 0.46, (0, 0, h + 0.005), "#5a4a32", rot=(0, 90, 0), verts=12, bevel=0, smooth=180))
    for i in range(7):   # traverses en X sur le faîtage
        x = -0.18 + i * 0.06
        for s in (-1, 1):
            b = box(f"x{i}{s}", (0.012, 0.11, 0.012), (x, 0, h + 0.03), "#3a2c22", bevel=0.0, smooth=0)
            b.rotation_euler = (s * 0.6, 0, 0)
            apply(b)
            parts.append(b)
    parts.append(box("beam", (0.46, 0.014, 0.014), (0, 0, h + 0.062), "#3a2c22", bevel=0.0, smooth=0))
    join(parts, "roof_thatch")


def roof_kaya():
    """Grand chaume irimoya des vieilles fermes (minka) : croupes basses et dodues, pignon de planches sombres
    sous le faîtage, épaisse tranche de paille au bord, faîtage fin coiffé de traverses."""
    h, vb, xg, droop = 0.5, 0.42, 0.34, -0.06
    parts = [_roof_surface("pans", 0.0, h, droop, 0.0, "#86683a", 0.6, thickness=0.09, edge="#c4a46a", gable=(vb, xg))]
    zf = lambda v: h * v - droop * math.sin(math.pi * v) * 0.5
    for sx in (-1, 1):   # pignon : triangle de planches en retrait sous le chaume qui déborde
        x = sx * (xg - 0.04)
        pts = [(0.5 * (1 - v), zf(v) - 0.035) for v in [vb + (1 - vb) * i / 8 for i in range(9)]]
        tri = [(-y, z) for y, z in pts] + list(reversed(pts))[1:]
        z0 = zf(vb)
        parts.append(prism(f"gable{sx}", [(y, z - z0) for y, z in tri], 0.02, (x, 0, z0), "#4a3326", rot=(90, 0, 90), bevel=0, smooth=0))
        for i in range(5):   # couvre-joints verts plus clairs
            y = -0.16 + i * 0.08
            top = zf(1 - abs(y) / 0.5) - z0 - 0.06
            if top > 0.02:
                parts.append(box(f"batten{sx}{i}", (0.012, 0.01, top), (x + sx * 0.012, y, z0 + top * 0.5), "#6b4a32", bevel=0, smooth=0))
        parts.append(box(f"vent{sx}", (0.01, 0.1, 0.05), (x + sx * 0.014, 0, z0 + 0.09), "#2a1e17", bevel=0, smooth=0))
    zr = zf(1.0)
    parts.append(cyl("ridge", 0.024, 0.024, 2 * xg + 0.04, (0, 0, zr + 0.004), "#5a4a32", rot=(0, 90, 0), verts=12, bevel=0, smooth=180))
    for i in range(9):   # traverses en X (karasu-odori)
        xx = -xg + 0.02 + i * (2 * xg - 0.04) / 8
        for s in (-1, 1):
            b = box(f"x{i}{s}", (0.01, 0.07, 0.01), (xx, 0, zr + 0.02), "#3a2c22", bevel=0.0, smooth=0)
            b.rotation_euler = (s * 0.6, 0, 0)
            apply(b)
            parts.append(b)
    parts.append(box("beam", (2 * xg + 0.02, 0.012, 0.012), (0, 0, zr + 0.042), "#3a2c22", bevel=0.0, smooth=0))
    join(parts, "roof_kaya")

# ================================================================ murs en travées
# Une travée fait 1,8 m de large (un ken) et 3 m de haut, origine au pied, au milieu ; épaisseur selon Y.
# La face extérieure est -Y (devient +Z dans Godot). Le jeu les étire à la largeur et la hauteur voulues.
BAY_W, BAY_H, T = 1.8, 3.0, 0.2
WOOD_W = "#8f5f3c"
WOOD_D = "#4a3326"
WOOD_L = "#c9a274"
PLASTER_W = "#efe6d1"
PAPER_W = "#f8efd6"
NOREN_W = "#2f4270"
NAGESHI = 2.42


def tint(hexc, k):
    c = hexc.lstrip("#")
    return tuple(min(1.0, int(c[i:i + 2], 16) / 255.0 * k) for i in (0, 2, 4))


def _frame(parts, frieze=PLASTER_W):
    """Sablière basse (dodai), linteau (nageshi), poutre haute (keta) et frise entre les deux."""
    parts.append(box("dodai", (BAY_W, T + 0.04, 0.14), (0, 0, 0.07), WOOD_D, bevel=0.012))
    parts.append(box("nageshi", (BAY_W, T + 0.08, 0.12), (0, 0, NAGESHI), WOOD_D, bevel=0.012))
    parts.append(box("keta", (BAY_W, T + 0.06, 0.18), (0, 0, BAY_H - 0.09), WOOD_D, bevel=0.012))
    z0, z1 = NAGESHI + 0.06, BAY_H - 0.18
    parts.append(box("frieze", (BAY_W - 0.02, T * 0.7, z1 - z0), (0, 0, (z0 + z1) / 2), frieze, bevel=0, grad=(0.95, 1.0)))


def _planks(parts, z0, z1, name, base=WOOD_W, n=7, battens=True):
    """Planches verticales légèrement inégales, avec deux lattes horizontales."""
    rnd = random.Random(hash(name) & 0xffff)
    w = BAY_W / n
    for i in range(n):
        x = -BAY_W / 2 + w * (i + 0.5)
        parts.append(box(f"{name}{i}", (w - 0.012, T * 0.8, z1 - z0), (x, rnd.uniform(-0.006, 0.006), (z0 + z1) / 2),
                         tint(base, rnd.uniform(0.82, 1.08)), bevel=0.006, grad=(0.8, 1.05), jitter=0.02))
    if battens:
        for z in (z0 + 0.12, z1 - 0.12):
            parts.append(box(f"{name}b{z:.2f}", (BAY_W, T * 0.95, 0.06), (0, 0, z), WOOD_D, bevel=0.006))


def _shoji(parts, x0, x1, z0, z1, name, glow=True):
    """Panneau shoji : cadre clair, papier (qui s'allume la nuit), croisillons kumiko des deux côtés."""
    cx, w, h = (x0 + x1) / 2, x1 - x0, z1 - z0
    paper = box(f"{name}p", (w - 0.06, T * 0.2, h - 0.06), (cx, 0, (z0 + z1) / 2), PAPER_W, bevel=0, emit=glow)
    parts.append(paper)
    fr = 0.05
    for zz in (z0 + fr / 2, z1 - fr / 2):
        parts.append(box(f"{name}h{zz:.2f}", (w, T * 0.55, fr), (cx, 0, zz), WOOD_L, bevel=0.004))
    for xx in (x0 + fr / 2, x1 - fr / 2):
        parts.append(box(f"{name}v{xx:.2f}", (fr, T * 0.55, h), (xx, 0, (z0 + z1) / 2), WOOD_L, bevel=0.004))
    for k in range(1, 3):
        xx = x0 + w * k / 3
        parts.append(box(f"{name}kv{k}", (0.022, T * 0.4, h - 0.08), (xx, 0, (z0 + z1) / 2), WOOD_L, bevel=0))
    for k in range(1, 5):
        zz = z0 + h * k / 5
        parts.append(box(f"{name}kh{k}", (w - 0.08, T * 0.4, 0.022), (cx, 0, zz), WOOD_L, bevel=0))


def bay_shoji():
    """Façade : soubassement de planches, deux shoji coulissants, frise enduite."""
    parts = []
    _frame(parts)
    _planks(parts, 0.14, 0.72, "koshi", n=6, battens=False)
    parts.append(box("koshi_rail", (BAY_W, T + 0.02, 0.06), (0, 0, 0.74), WOOD_D, bevel=0.006))
    _shoji(parts, -BAY_W / 2 + 0.02, 0.02, 0.77, NAGESHI - 0.06, "l")
    _shoji(parts, -0.02, BAY_W / 2 - 0.02, 0.77, NAGESHI - 0.06, "r")
    join(parts, "bay_shoji")


def bay_plaster():
    """Mur enduit : planches en bas, enduit clair encadré au-dessus."""
    parts = []
    _frame(parts)
    _planks(parts, 0.14, 1.05, "koshi", n=6)
    parts.append(box("plaster", (BAY_W - 0.02, T * 0.75, NAGESHI - 1.11), (0, 0, (1.05 + NAGESHI - 0.06) / 2 + 0.03), PLASTER_W, bevel=0, grad=(0.9, 1.0)))
    parts.append(box("nuki", (BAY_W, T * 0.85, 0.07), (0, 0, 1.75), WOOD_W, bevel=0.006))
    join(parts, "bay_plaster")


def _slat_window(parts, cx, cz, w, h, name, glow=True):
    """Fenêtre à barreaux (renji-mado) : cadre, barreaux de bambou, papier lumineux derrière."""
    parts.append(box(f"{name}bg", (w, T * 0.3, h), (cx, T * 0.1, cz), PAPER_W, bevel=0, emit=glow))
    for zz in (cz - h / 2, cz + h / 2):
        parts.append(box(f"{name}fh{zz:.2f}", (w + 0.1, T + 0.04, 0.06), (cx, 0, zz), WOOD_D, bevel=0.006))
    for xx in (cx - w / 2, cx + w / 2):
        parts.append(box(f"{name}fv{xx:.2f}", (0.06, T + 0.04, h + 0.06), (xx, 0, cz), WOOD_D, bevel=0.006))
    for k in range(1, 7):
        xx = cx - w / 2 + w * k / 7
        parts.append(cyl(f"{name}s{k}", 0.018, 0.018, h, (xx, -T * 0.3, cz), "#b39a5c", verts=6, bevel=0, smooth=180))


def bay_window():
    """Mur enduit percé d'une fenêtre à barreaux."""
    parts = []
    _frame(parts)
    _planks(parts, 0.14, 1.05, "koshi", n=6)
    zc, wh = 1.72, 0.62
    lo = box("plaster_lo", (BAY_W - 0.02, T * 0.75, zc - wh / 2 - 1.05), (0, 0, (1.05 + zc - wh / 2) / 2), PLASTER_W, bevel=0)
    hi = box("plaster_hi", (BAY_W - 0.02, T * 0.75, NAGESHI - 0.06 - zc - wh / 2), (0, 0, (zc + wh / 2 + NAGESHI - 0.06) / 2), PLASTER_W, bevel=0)
    parts += [lo, hi]
    for sx in (-1, 1):
        parts.append(box(f"side{sx}", (0.37, T * 0.75, wh), (sx * (BAY_W / 2 - 0.185), 0, zc), PLASTER_W, bevel=0))
    _slat_window(parts, 0, zc, 1.0, wh, "win")
    join(parts, "bay_window")


def bay_plank():
    """Mur rustique tout en planches (niveau « rustique »)."""
    parts = []
    _frame(parts, frieze=tint(WOOD_W, 0.8))
    _planks(parts, 0.14, NAGESHI - 0.06, "itabari", base="#7c5234", n=7)
    join(parts, "bay_plank")


def bay_plank_window():
    """Mur rustique en planches, petite fenêtre à barreaux."""
    parts = []
    _frame(parts, frieze=tint(WOOD_W, 0.8))
    _planks(parts, 0.14, 1.35, "itabari", base="#7c5234", n=7)
    _planks(parts, 2.0, NAGESHI - 0.06, "itabari_h", base="#7c5234", n=7, battens=False)
    for sx in (-1, 1):
        parts.append(box(f"side{sx}", (0.42, T * 0.8, 0.65), (sx * (BAY_W / 2 - 0.21), 0, 1.675), tint("#7c5234", 0.95), bevel=0.006))
    _slat_window(parts, 0, 1.675, 0.96, 0.6, "win")
    join(parts, "bay_plank_window")


def _noren(parts, z_top, length, color=NOREN_W, mark=True):
    """Noren : trois pans de tissu suspendus à une tringle, côté extérieur."""
    y = -T / 2 - 0.05
    parts.append(cyl("rod", 0.02, 0.02, BAY_W - 0.1, (0, y, z_top), WOOD_D, rot=(0, 90, 0), verts=6, bevel=0))
    w = (BAY_W - 0.2) / 3
    for i in range(3):
        x = -BAY_W / 2 + 0.1 + w * (i + 0.5)
        parts.append(box(f"cloth{i}", (w - 0.04, 0.02, length), (x, y, z_top - length / 2 - 0.02), color, bevel=0, grad=(0.85, 1.05)))
    if mark:   # symbole des sources chaudes, en blanc sur le pan du milieu
        parts.append(torus("mark", 0.13, 0.025, (0, y - 0.015, z_top - length * 0.55), "#f4efe4", rot=(90, 0, 0), segs=20, rsegs=6))
        for k in (-1, 0, 1):
            parts.append(box(f"steam{k}", (0.03, 0.01, 0.16), (k * 0.07, y - 0.015, z_top - length * 0.55 + 0.21), "#f4efe4", bevel=0))


def bay_door():
    """Entrée ouverte : seuil, linteau bas (kamoi), frise, noren qui pend à l'extérieur."""
    parts = []
    _frame(parts)
    parts.append(box("kamoi", (BAY_W, T + 0.04, 0.1), (0, 0, 2.2), WOOD_D, bevel=0.01))
    parts.append(box("ranma", (BAY_W - 0.02, T * 0.7, NAGESHI - 2.25 - 0.06), (0, 0, (2.25 + NAGESHI - 0.06) / 2), PLASTER_W, bevel=0))
    _noren(parts, 2.14, 0.62)
    join(parts, "bay_door")


def bay_entry():
    """Entrée fermée : shoji coulissants et noren devant (maisons qu'on ne visite pas)."""
    parts = []
    _frame(parts)
    _planks(parts, 0.14, 0.4, "koshi", n=6, battens=False)
    _shoji(parts, -BAY_W / 2 + 0.02, 0.02, 0.42, NAGESHI - 0.06, "l")
    _shoji(parts, -0.02, BAY_W / 2 - 0.02, 0.42, NAGESHI - 0.06, "r")
    _noren(parts, 2.3, 0.6)
    join(parts, "bay_entry")


def post():
    """Poteau de bois sur sa pierre de fondation (aux angles et entre les travées)."""
    parts = [box("hashira", (0.24, 0.24, BAY_H), (0, 0, BAY_H / 2), "#5a3e2c", bevel=0.02, grad=(0.75, 1.05))]
    stone = ball("ishi", 0.22, (0, 0, 0.0), "#9a948a", scale=(1.2, 1.2, 0.55), subdiv=2, smooth=0)
    displace(stone, 0.04, 3.0, 2)
    parts.append(stone)
    join(parts, "post")

# ================================================================ végétation de jardin
def _chips(bm, center, radius, count, size, colors, rnd, face_cols, flat=0.75, up=0.1, shell=(0.75, 1.05)):
    """Éclats facettés (feuilles, pétales) répartis sur une coque ellipsoïdale ; couleurs tirées dans `colors`."""
    for _ in range(count):
        u = Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 1))).normalized()
        u.z = abs(u.z) * flat + up
        p = center + Vector((u.x * radius[0], u.y * radius[1], u.z * radius[2])) * rnd.uniform(*shell)
        s = rnd.uniform(*size)
        q = (Matrix.Rotation(rnd.uniform(0, 6.28), 4, 'Z') @ Matrix.Rotation(rnd.uniform(-0.9, 0.9), 4, 'X'))
        vs = [bm.verts.new(p + (q @ Vector(o)) * s) for o in ((1, 0, 0), (-0.6, 0.6, 0), (-0.6, -0.6, 0), (0, 0, 0.2), (0, 0, -0.2))]
        cc = colors[rnd.randrange(len(colors))]
        k = rnd.uniform(0.85, 1.12)
        for i in range(3):
            face_cols[bm.faces.new((vs[i], vs[(i + 1) % 3], vs[3]))] = [c * k for c in cc]
            face_cols[bm.faces.new((vs[(i + 1) % 3], vs[i], vs[4]))] = [c * k for c in cc]


def _blob_core(bm, center, radius, color, face_cols, seed):
    core = bmesh.ops.create_icosphere(bm, subdivisions=2, radius=1.0)["verts"]
    for v in core:
        n = 1.0 + 0.2 * mnoise.noise(v.co * 2.0 + Vector((seed, 0, 0)))
        v.co = center + Vector((v.co.x * radius[0], v.co.y * radius[1], max(v.co.z, -0.3) * radius[2])) * n
    for f in {f for v in core for f in v.link_faces}:
        face_cols[f] = list(color[:3])


def _bm_object(name, bm, face_cols, smooth=False):
    bm.normal_update()
    order = {f: i for i, f in enumerate(bm.faces)}
    fc = [None] * len(bm.faces)
    for f, cc in face_cols.items():
        fc[order[f]] = cc
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = smooth
    attr = me.color_attributes.new(name="Col", type='FLOAT_COLOR', domain='CORNER')
    me.color_attributes.active_color = attr
    for p in me.polygons:
        cc = fc[p.index] or [0.1, 0.2, 0.05]
        for li in p.loop_indices:
            attr.data[li].color = (cc[0], cc[1], cc[2], 1.0)
    return ob


def hydrangea(name, flowers):
    """Hortensia : touffe de feuilles larges et grosses boules de fleurs (ajisai)."""
    rnd = random.Random(hash(name) & 0xffff)
    bm = bmesh.new()
    fcs = {}
    leaf = [col("#3d6b2a"), col("#4f7f30"), col("#2f5622")]
    _blob_core(bm, Vector((0, 0, 0.42)), (0.7, 0.6, 0.45), col("#2c4d20"), fcs, 1)
    _chips(bm, Vector((0, 0, 0.4)), (0.75, 0.65, 0.45), 70, (0.16, 0.24), leaf, rnd, fcs)
    fl = [col(c) for c in flowers]
    for i in range(7):
        a = i * 2.4 + rnd.uniform(-0.3, 0.3)
        r = 0.42 if i else 0.0
        c = Vector((math.cos(a) * r, math.sin(a) * r, 0.75 + rnd.uniform(-0.08, 0.12)))
        _blob_core(bm, c, (0.2, 0.2, 0.18), fl[0], fcs, i + 3)
        _chips(bm, c, (0.22, 0.22, 0.2), 26, (0.07, 0.1), fl, rnd, fcs, flat=1.0, up=-0.2, shell=(0.85, 1.0))
    _bm_object(name, bm, fcs)


def azalea(name, flowers):
    """Azalée taillée en coussin, couverte de petites fleurs (tsutsuji des jardins japonais)."""
    rnd = random.Random(hash(name) & 0xffff)
    bm = bmesh.new()
    fcs = {}
    _blob_core(bm, Vector((0, 0, 0.3)), (0.8, 0.7, 0.42), col("#355e24"), fcs, 2)
    _chips(bm, Vector((0, 0, 0.3)), (0.82, 0.72, 0.42), 60, (0.1, 0.14), [col("#3f6d2a"), col("#4c7a30")], rnd, fcs)
    _chips(bm, Vector((0, 0, 0.32)), (0.84, 0.74, 0.44), 150, (0.06, 0.09), [col(c) for c in flowers], rnd, fcs, flat=0.9, up=0.15, shell=(0.92, 1.03))
    _bm_object(name, bm, fcs)


def fern():
    """Fougère : neuf frondes arquées aux bords découpés en folioles."""
    rnd = random.Random(31)
    bm = bmesh.new()
    fcs = {}
    for k in range(9):
        a = k * 2 * math.pi / 9 + rnd.uniform(-0.2, 0.2)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        L = rnd.uniform(0.75, 1.05)
        n = 12
        prev = None
        for i in range(n + 1):
            t = i / n
            p = d * L * t + Vector((0, 0, math.sin(t * math.pi * 0.8) * 0.55 * L))
            w = 0.16 * math.sin(math.pi * min(1.0, t * 1.1)) * (1.0 if i % 2 == 0 else 0.55)   # folioles en dents
            vl = bm.verts.new(p - side * w)
            vc = bm.verts.new(p + Vector((0, 0, 0.015)))
            vr = bm.verts.new(p + side * w)
            if prev:
                cc = _mix("#2f5a24", "#7eaa3e", t)[:3]
                for f in (bm.faces.new((prev[0], vl, vc, prev[1])), bm.faces.new((prev[1], vc, vr, prev[2]))):
                    fcs[f] = cc
            prev = (vl, vc, vr)
    _bm_object("fern", bm, fcs)


def bamboo():
    """Bosquet de bambous : tiges vert tendre à nœuds, bouquets de feuilles fines en hauteur."""
    rnd = random.Random(17)
    parts = []
    bm = bmesh.new()
    fcs = {}
    for k in range(8):
        a = rnd.uniform(0, 6.28)
        r = rnd.uniform(0.0, 0.9)
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        h = rnd.uniform(6.0, 8.5)
        lean = Vector((rnd.uniform(-0.25, 0.25), rnd.uniform(-0.25, 0.25), 1.0)).normalized()
        rad = rnd.uniform(0.05, 0.08)
        st = cyl(f"stalk{k}", rad * 0.8, rad, h, (0, 0, h / 2), "#7ea64a", verts=8, bevel=0, smooth=180, grad=(0.75, 1.1))
        rot = Vector((0, 0, 1)).rotation_difference(lean).to_matrix().to_4x4()
        st.data.transform(rot)
        st.location = base
        apply(st)
        parts.append(st)
        for j in range(int(h / 0.55)):
            z = 0.4 + j * 0.55
            ring = cyl(f"node{k}_{j}", rad * 1.18, rad * 1.18, 0.05, (0, 0, z), "#5f8a35", verts=8, bevel=0, smooth=0)
            ring.data.transform(rot)
            ring.location = base
            apply(ring)
            parts.append(ring)
        top = base + lean * h
        _chips(bm, top - lean * 1.4, (1.1, 1.1, 1.6), 55, (0.22, 0.32), [col("#5d8f34"), col("#7aab45"), col("#46762a")], rnd, fcs, flat=0.6, up=-0.2)
    leaves = _bm_object("leaves", bm, fcs)
    # feuilles allongées : on étire les éclats
    join(parts + [leaves], "bamboo")


def iris():
    """Touffe d'iris de bord d'eau : feuilles en lames et fleurs violettes."""
    rnd = random.Random(5)
    bm = bmesh.new()
    fcs = {}
    for k in range(14):
        a = rnd.uniform(0, 6.28)
        d = Vector((math.cos(a), math.sin(a), 0)) * rnd.uniform(0.0, 0.15)
        h = rnd.uniform(0.6, 1.0)
        lean = Vector((math.cos(a) * 0.25, math.sin(a) * 0.25, 1.0)).normalized()
        side = lean.cross(Vector((0, 0, 1))).normalized() if abs(lean.z) < 0.999 else Vector((1, 0, 0))
        w = 0.035
        v0, v1, v2 = bm.verts.new(d - side * w), bm.verts.new(d + side * w), bm.verts.new(d + lean * h)
        fcs[bm.faces.new((v0, v1, v2))] = _mix("#2f5a28", "#6f9a40", rnd.random())[:3]
    for k in range(4):
        a = k * 1.6 + 0.3
        c = Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, rnd.uniform(0.75, 0.95)))
        _chips(bm, c, (0.08, 0.08, 0.06), 9, (0.06, 0.09), [col("#6a4bb0"), col("#8466c8"), col("#f2d35a")], rnd, fcs, flat=1.0, up=0.0)
    _bm_object("iris", bm, fcs)


def _flower_head(bm, fcs, center, r, petal_col, heart_col, rnd, petals=5, tilt=0.35):
    """Corolle : pétales ovales en étoile autour d'un cœur rond, légèrement inclinée vers le soleil."""
    q = Matrix.Rotation(rnd.uniform(0, 6.28), 4, 'Z') @ Matrix.Rotation(rnd.uniform(-tilt, tilt), 4, 'X')
    pc = col(petal_col)
    for k in range(petals):
        a = k * 2 * math.pi / petals
        d = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-d.y, d.x, 0))
        tip, base = d * r, d * r * 0.18
        vs = [bm.verts.new(center + q @ v) for v in (base, base + side * r * 0.32 + d * r * 0.45 + Vector((0, 0, r * 0.12)),
                                                     tip + Vector((0, 0, r * 0.18)), base - side * r * 0.32 + d * r * 0.45 + Vector((0, 0, r * 0.12)))]
        k2 = rnd.uniform(0.9, 1.08)
        fcs[bm.faces.new(vs)] = [c * k2 for c in pc[:3]]
        back = [bm.verts.new(v.co - Vector((0, 0, 0.004))) for v in vs[::-1]]   # dos du pétale (faces séparées)
        fcs[bm.faces.new(back)] = [c * k2 * 0.85 for c in pc[:3]]
    heart = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r * 0.26)["verts"]
    for v in heart:
        v.co = center + q @ Vector((v.co.x, v.co.y, v.co.z * 0.6 + r * 0.08))
    for f in {f for v in heart for f in v.link_faces}:
        fcs[f] = col(heart_col)[:3]


def flower_patch(name, palette):
    """Massif de fleurs des champs : touffes basses, tiges vertes bien visibles, vraies corolles
    à hauteur de l'herbe (elles ne flottent pas au-dessus du pré)."""
    rnd = random.Random(hash(name) & 0xffff)
    bm = bmesh.new()
    fcs = {}
    stem = col("#3f6a26")
    leaf = [col("#3a6424"), col("#4e7d2e")]
    for k in range(16):
        a, rr = rnd.uniform(0, 6.28), math.sqrt(rnd.random()) * 0.55
        p = Vector((math.cos(a) * rr, math.sin(a) * rr, 0))
        h = rnd.uniform(0.26, 0.46)   # la corolle dépasse juste de l'herbe
        lean = Vector((rnd.uniform(-0.06, 0.06), rnd.uniform(-0.06, 0.06), 0))
        top = p + lean + Vector((0, 0, h))
        st = bmesh.ops.create_cone(bm, cap_ends=False, segments=5, radius1=0.011, radius2=0.007, depth=h)["verts"]
        for v in st:
            t = (v.co.z + h / 2) / h
            v.co = p + lean * t + Vector((v.co.x, v.co.y, v.co.z + h / 2))
        for f in {f for v in st for f in v.link_faces}:
            fcs[f] = stem[:3]
        for j in range(2):   # deux feuilles au pied de la tige
            la = rnd.uniform(0, 6.28)
            d = Vector((math.cos(la), math.sin(la), 0.5)).normalized()
            sd = Vector((-d.y, d.x, 0)) * 0.025
            b0 = p + Vector((0, 0, 0.02))
            vs = [bm.verts.new(b0 - sd), bm.verts.new(b0 + d * 0.11 + Vector((0, 0, 0.02))), bm.verts.new(b0 + sd)]
            fcs[bm.faces.new(vs)] = leaf[j][:3]
            fcs[bm.faces.new([bm.verts.new(v.co - Vector((0, 0, 0.003))) for v in vs[::-1]])] = leaf[j][:3]
        pc = palette[rnd.randrange(len(palette))]
        _flower_head(bm, fcs, top, rnd.uniform(0.07, 0.1), pc, "#f2c94a" if pc != "#f7e15a" else "#e08a2a", rnd)
    _bm_object(name, bm, fcs)

MOMIJI_PALETTES = [("#5e1418", "#962a2a", "#c9493a"), ("#6a1c16", "#a8382a", "#d8673c"),
                   ("#7a3410", "#c2611f", "#eb9a3a"), ("#7a5a12", "#c99a22", "#f2cf4a")]


def momiji(variant):
    """Érable japonais à feuilles rouges : même port en parasol que le cerisier, couronne rouge et orangée."""
    wood, tips = _sakura_wood(variant + 3)
    for o in wood:
        _bark(o)
    crown = _blossom_crown(1, tips, random.Random(variant * 29 + 1), MOMIJI_PALETTES[variant - 1])
    join(wood + [crown], f"momiji_{variant}")


def momiji_shadow(variant):
    wood, tips = _sakura_wood(variant + 3)
    blobs = [ball(f"b{i}", 1.3, t + Vector((0, 0, 0.35)), "#333333", scale=(1, 1, 0.75), subdiv=1, smooth=0) for i, t in enumerate(tips)]
    join(wood + blobs, f"momiji_{variant}_shadow")


def hydrangea_blue(): hydrangea("hydrangea_blue", ["#5b7fd6", "#7d9be6", "#9a86d8", "#b3c6f2"])
def hydrangea_pink(): hydrangea("hydrangea_pink", ["#e27aa6", "#f0a0c0", "#c983c9", "#f7c6dc"])
def azalea_pink(): azalea("azalea_pink", ["#f06fa0", "#f792b8", "#e45a8e"])
def azalea_red(): azalea("azalea_red", ["#e0443a", "#f06a4e", "#c9302e"])
def flowers_meadow(): flower_patch("flowers_meadow", ["#ffffff", "#f7e15a", "#f5a3c0", "#a9b8f0"])
def flowers_warm(): flower_patch("flowers_warm", ["#f7c94a", "#f08a3c", "#ffffff", "#e8605a"])
def momiji_1(): momiji(1)
def momiji_2(): momiji(2)
def momiji_3(): momiji(3)
def momiji_4(): momiji(4)
def momiji_1_shadow(): momiji_shadow(1)
def momiji_2_shadow(): momiji_shadow(2)

VEG = ["hydrangea_blue", "hydrangea_pink", "azalea_pink", "azalea_red", "fern", "bamboo", "iris",
       "flowers_meadow", "flowers_warm", "momiji_1", "momiji_2", "momiji_3", "momiji_4", "momiji_1_shadow", "momiji_2_shadow"]

def cliff_rock(variant):
    """Gros bloc de falaise arrondi (≈ 7 m de haut) : flancs gris à strates, sommet couvert de mousse.
    Posés en couronne, ils forment le bord rocheux du plateau de l'onsen (concept)."""
    sizes = [(2.6, 2.1, 3.6), (3.2, 2.4, 3.2), (2.2, 2.0, 4.0)]
    sx, sy, sz = sizes[variant - 1]
    o = ball("cliff", 1.0, (0, 0, 0), "#9a9286", scale=(sx, sy, sz), subdiv=4, smooth=180)
    displace(o, 0.28 * min(sx, sy), 0.55, variant * 13)
    for v in o.data.vertices:   # sommet un peu aplati, base enterrée
        if v.co.z > sz * 0.55:
            v.co.z = sz * 0.55 + (v.co.z - sz * 0.55) * 0.45
    o.location.z = sz
    apply(o)
    shade(o, 180)
    paint_by(o, _rock_paint("#7f7d78", "#5f7d33", "#4c4a47", 0.12))
    o.name = f"cliff_rock_{variant}"


def cliff_rock_1(): cliff_rock(1)
def cliff_rock_2(): cliff_rock(2)
def cliff_rock_3(): cliff_rock(3)



# ================================================================ décor Ghibli : lanternes de papier, grand camphrier

def chochin(name="chochin", paper="#c43a22", rib="#6a1a12"):
    """Lanterne de papier (chōchin) ≈ 0,75 m : ventre ovale lumineux, côtes de bambou, couvercles laqués noirs.
    Origine au centre ; l'anneau d'accroche est à +0,37 m."""
    parts = [uvball("paper", 0.24, (0, 0, 0), paper, scale=(1, 1, 1.3), segs=16, rings=10, emit=True)]
    for i in range(1, 7):
        z = -0.312 + i * 0.089
        r = 0.24 * math.sqrt(max(0.0, 1 - (z / 0.312) ** 2)) + 0.006
        parts.append(torus(f"rib{i}", r, 0.009, (0, 0, z), rib, segs=20, rsegs=4))
    parts.append(cyl("top", 0.115, 0.13, 0.08, (0, 0, 0.3), "#1c1714", verts=14))
    parts.append(cyl("bottom", 0.13, 0.115, 0.08, (0, 0, -0.3), "#1c1714", verts=14))
    parts.append(torus("hook", 0.035, 0.01, (0, 0, 0.37), "#1c1714", rot=(90, 0, 0), segs=10, rsegs=4))
    join(parts, name)


def chochin_white(): chochin("chochin_white", "#d8bf94", "#7a5a34")


CAMPHOR_PALETTE = ("#24492a", "#3f7a35", "#8cc25a")


def camphor():
    """Grand camphrier sacré (kusunoki), ≈ 13 m (agrandi en jeu) : tronc fait de cinq troncs tordus fondus ensemble,
    contreforts, couronne en dôme de nuages verts, creux sombre au pied, corde sacrée (shimenawa) et papiers shide."""
    rnd = random.Random(77)
    wood = []
    for i in range(5):
        az = i * 2 * math.pi / 5 + rnd.uniform(-0.3, 0.3)
        pts, radii = _limb(rnd, Vector((math.cos(az) * 0.6, math.sin(az) * 0.6, -0.5)), Vector((math.cos(az) * 0.06, math.sin(az) * 0.06, 1.0)),
                           4.8, 1.05, 0.55, 6, 0.07)
        wood.append(_tube(f"trunk{i}", pts, radii, 9, i, wobble=0.22))
    for i in range(8):   # contreforts qui plongent dans le sol
        az = i * 2 * math.pi / 8 + rnd.uniform(-0.25, 0.25)
        p, r = _limb(rnd, Vector((math.cos(az) * 1.0, math.sin(az) * 1.0, 1.3)), Vector((math.cos(az), math.sin(az), -0.5)), rnd.uniform(2.4, 3.0), 0.85, 0.3, 4, 0.06)
        wood.append(_tube(f"root{i}", p, r, 7, i + 20))
    tips = []
    for i in range(9):   # branches maîtresses : elles montent puis s'étalent
        az = i * 2 * math.pi / 9 + rnd.uniform(-0.2, 0.2)
        base = Vector((math.cos(az) * 0.8, math.sin(az) * 0.8, rnd.uniform(3.4, 4.4)))
        p, r = _limb(rnd, base, Vector((math.cos(az), math.sin(az), rnd.uniform(0.7, 1.2))), rnd.uniform(4.2, 5.6), 0.55, 0.12, 6, 0.16, 0.06)
        wood.append(_tube(f"limb{i}", p, r, 7, i + 40))
        tips += [p[-1], p[len(p) // 2] + Vector((0, 0, 1.0))]
        for j in range(2):
            fk = rnd.randint(2, 4)
            az2 = az + (j - 0.5) * rnd.uniform(0.9, 1.5)
            p2, r2 = _limb(rnd, p[fk], Vector((math.cos(az2), math.sin(az2), rnd.uniform(0.3, 0.8))), rnd.uniform(2.0, 3.0), r[fk] * 0.6, 0.04, 3, 0.25)
            wood.append(_tube(f"twig{i}_{j}", p2, r2, 5, i * 7 + j))
            tips.append(p2[-1])
    for i in range(7):   # le dôme : de gros nuages en haut et au centre
        a = i * 2 * math.pi / 7
        tips.append(Vector((math.cos(a) * 2.6, math.sin(a) * 2.6, rnd.uniform(9.5, 10.6))))
    tips.append(Vector((0, 0, 11.4)))

    def bark(co, n):
        k = 0.5 + 0.5 * mnoise.noise(Vector((co.x * 2.2, co.y * 2.2, co.z * 0.5)))
        c = _mix("#3a2e28", "#7a6a5c", k)
        moss = max(0.0, n.z - 0.6) * 1.5 * (0.5 + 0.5 * mnoise.noise(co * 0.8))
        return _mix(c, "#5f7d33", min(1.0, moss * 0.7)), False
    for o in wood:
        paint_by(o, bark)
    crown = _blossom_crown(1, tips, random.Random(5), CAMPHOR_PALETTE, scale=1.7)
    # creux sombre au pied (côté -Y = face au joueur en jeu, +Z de Godot)
    hollow = ball("hollow", 0.75, (0, -1.6, 0.85), "#0d0907", scale=(0.8, 0.35, 1.25), subdiv=2, jitter=0.0)
    # corde sacrée : un gros boudin de paille et deux torons qui s'enroulent autour
    R, zr = 2.05, 2.7
    rope = [torus("rope", R, 0.22, (0, 0, zr), "#c9b27a", segs=40, rsegs=8)]
    for s in range(2):
        pts, rad = [], []
        for k in range(97):
            t = k / 96 * 2 * math.pi
            tw = t * 9 + s * math.pi
            radial = Vector((math.cos(t), math.sin(t), 0))
            pts.append(radial * (R + math.cos(tw) * 0.17) + Vector((0, 0, zr + math.sin(tw) * 0.17)))
            rad.append(0.09)
        strand = _tube(f"strand{s}", pts, rad, 5, s, wobble=0.0)
        paint(strand, "#a88f58")
        rope.append(strand)
    for k in range(6):   # papiers shide en zigzag
        a = k * 2 * math.pi / 6 + 0.3
        radial = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-radial.y, radial.x, 0))
        for j in range(4):
            c = radial * (R + 0.2) + side * (0.07 if j % 2 else -0.07) + Vector((0, 0, zr - 0.25 - j * 0.16))
            b = box(f"shide{k}_{j}", (0.16, 0.02, 0.15), (0, 0, 0), "#f4f1e6", bevel=0.0, smooth=0)
            b.rotation_euler = (0, 0, a + math.pi / 2)
            b.location = c
            apply(b)
            rope.append(b)
        tassel = cyl(f"tassel{k}", 0.05, 0.09, 0.35, (0, 0, 0), "#b89c62", verts=6, bevel=0)
        tassel.location = radial * (R + 0.05) + side * 0.35 + Vector((0, 0, zr - 0.32))
        apply(tassel)
        rope.append(tassel)
    join(wood + [crown, hollow] + rope, "camphor")


def camphor_shadow():
    """Ombre du camphrier : un dôme bosselé posé sur un fût (le feuillage détaillé ne projette pas d'ombre)."""
    parts = [cyl("trunk", 1.3, 1.6, 5.0, (0, 0, 2.5), "#333333", verts=10, bevel=0)]
    rnd = random.Random(3)
    for i in range(10):
        a = i * 2 * math.pi / 10
        parts.append(ball(f"b{i}", rnd.uniform(2.6, 3.4), (math.cos(a) * 5.0, math.sin(a) * 5.0, rnd.uniform(7.0, 8.5)), "#333333", scale=(1, 1, 0.7), subdiv=1, smooth=0))
    parts.append(ball("top", 4.2, (0, 0, 9.8), "#333333", scale=(1, 1, 0.65), subdiv=1, smooth=0))
    join(parts, "camphor_shadow")



# ================================================================ décor Ghibli : jizō, esprits des bois, carillon

def jizo():
    """Statuette de jizō (≈ 0,95 m) : pierre ronde et moussue, yeux fermés, bavoir et bonnet rouges."""
    stone, moss, dark = "#9a958c", "#6f8a3c", "#6a665e"
    parts = [_hex("socle", 0.32, 0.28, 0.16, 0.08, stone),
             cyl("corps", 0.17, 0.22, 0.52, (0, 0, 0.42), stone, verts=14, bevel=0.06, smooth=180),
             ball("tete", 0.155, (0, 0, 0.82), stone, scale=(1, 0.95, 1.05), subdiv=3)]
    for sx in (-1, 1):   # yeux fermés : deux petits traits arqués
        e = box(f"oeil{sx}", (0.055, 0.012, 0.012), (sx * 0.055, -0.145, 0.84), "#3a3632", bevel=0.0, smooth=0)
        e.rotation_euler = (0, sx * 0.25, 0)
        apply(e)
        parts.append(e)
    parts.append(ball("mains", 0.06, (0, -0.2, 0.47), stone, scale=(1.4, 0.8, 1), subdiv=2))
    paint_moss = _rock_paint(stone, moss, dark, 0.75)
    for o in parts:
        paint_by(o, paint_moss)
    bib = prism("bavoir", [(-0.2, 0), (0.2, 0), (0.12, -0.17), (0, -0.22), (-0.12, -0.17)], 0.025, (0, 0, 0), "#c8352a")
    bib.rotation_euler = (math.radians(80), 0, 0)
    bib.location = (0, -0.2, 0.66)
    apply(bib)
    cap = ball("bonnet", 0.165, (0, 0, 0.86), "#c23a2c", scale=(1, 1, 0.85), subdiv=2)
    for v in cap.data.vertices:   # demi-sphère : seulement le dessus de la tête
        if v.co.z < 0.03:
            v.co.z = 0.03
    pom = ball("pompon", 0.04, (0, 0, 1.0), "#d9483a", subdiv=1)
    join(parts + [bib, cap, pom], "jizo")


def kodama():
    """Petit esprit des bois (≈ 0,55 m) : tout blanc, grosse tête ronde, deux yeux noirs, une pousse verte.
    Le blanc est lumineux (il luit doucement le soir)."""
    white = "#eef0e6"
    body = cyl("corps", 0.08, 0.12, 0.26, (0, 0, 0.13), white, verts=12, bevel=0.03, smooth=180, emit=True)
    head = ball("tete", 0.16, (0, 0, 0.4), white, scale=(1, 0.92, 0.88), subdiv=3, emit=True)
    parts = [body, head]
    for sx in (-1, 1):
        parts.append(ball(f"oeil{sx}", 0.028, (sx * 0.06, -0.13, 0.42), "#1a1716", subdiv=1))
        parts.append(cyl(f"bras{sx}", 0.025, 0.025, 0.14, (sx * 0.12, 0, 0.2), white, rot=(0, sx * 30, 0), verts=6, bevel=0, emit=True))
    parts.append(ball("bouche", 0.018, (0, -0.135, 0.36), "#1a1716", scale=(1.3, 0.6, 0.8), subdiv=1))
    parts.append(cyl("tige", 0.008, 0.01, 0.08, (0, 0, 0.57), "#5d8a34", verts=5, bevel=0))
    leaf = ball("feuille", 0.045, (0.03, 0, 0.62), "#7ab648", scale=(1.4, 0.35, 0.7), subdiv=1)
    parts.append(leaf)
    join(parts, "kodama")


def furin():
    """Carillon à vent (fūrin) : cloche de verre peinte, battant, bande de papier qui prend le vent. Origine au crochet."""
    parts = [cyl("fil", 0.004, 0.004, 0.06, (0, 0, -0.03), "#2a2420", verts=4, bevel=0)]
    bell = ball("cloche", 0.07, (0, 0, -0.1), "#a8dcea", scale=(1, 1, 0.9), subdiv=2)
    for v in bell.data.vertices:   # ouverte vers le bas
        if v.co.z < -0.03:
            v.co.z = -0.03
    parts.append(bell)
    parts.append(torus("motif", 0.068, 0.006, (0, 0, -0.115), "#d9483a", segs=16, rsegs=4))
    parts.append(cyl("battant", 0.003, 0.003, 0.12, (0, 0, -0.19), "#2a2420", verts=4, bevel=0))
    parts.append(box("tanzaku", (0.05, 0.004, 0.17), (0, 0, -0.33), "#f0cf62", bevel=0.0, smooth=0))
    join(parts, "furin")

# ================================================================ place du village : estrade de fête, échoppes
KOHAKU_R, KOHAKU_W = "#c8352a", "#f4efe2"


def yagura():
    """Estrade de fête (yagura) ≈ 6 m : quatre poteaux, plancher à 2,1 m, rideau rouge et blanc (kōhaku) plissé tout
    autour, balustrade, bandeau kōhaku sous un petit toit pyramidal aux coins relevés, grand tambour taiko sur le
    plancher, escalier côté -Y (face à l'escalier de l'onsen en jeu). Origine au sol, au centre."""
    H, S, TOP = 2.1, 4.2, 4.7   # plancher, côté, pied du toit
    h = S / 2
    parts = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(box(f"post{sx}{sy}", (0.24, 0.24, TOP), (sx * (h - 0.12), sy * (h - 0.12), TOP / 2), WOOD_W, grad=(0.75, 1.05)))
            parts.append(box(f"foot{sx}{sy}", (0.5, 0.5, 0.22), (sx * (h - 0.12), sy * (h - 0.12), 0.06), "#8e8a80", bevel=0.04))
    parts.append(box("deck", (S + 0.36, S + 0.36, 0.18), (0, 0, H), WOOD_D, bevel=0.02))
    parts.append(box("deck_top", (S + 0.2, S + 0.2, 0.04), (0, 0, H + 0.1), WOOD_L, bevel=0.0, jitter=0.06))

    def ring(z0, z1, off, n, name, fold=0.035):
        ## bandes verticales rouges et blanches sur les quatre faces, une sur deux un peu ressortie : des plis
        w = S / n
        for face in range(4):
            for i in range(n):
                t = -h + w * (i + 0.5)
                o = h + off + (fold if i % 2 else 0.0)
                c = KOHAKU_R if i % 2 else KOHAKU_W
                size = (w + 0.01, 0.03, z1 - z0) if face < 2 else (0.03, w + 0.01, z1 - z0)
                loc = ((t, -o if face == 0 else o, (z0 + z1) / 2) if face < 2 else (-o if face == 2 else o, t, (z0 + z1) / 2))
                parts.append(box(f"{name}{face}_{i}", size, loc, c, bevel=0.0, smooth=0, grad=(0.88, 1.04), jitter=0.02))
        for face in range(4):   # la cordelette qui tient le rideau
            size = (S + 0.2, 0.06, 0.06) if face < 2 else (0.06, S + 0.2, 0.06)
            o = h + off + 0.05
            loc = ((0, -o if face == 0 else o, z1) if face < 2 else (-o if face == 2 else o, 0, z1))
            parts.append(box(f"{name}cord{face}", size, loc, "#2a2422", bevel=0.0, smooth=0))
    ring(0.25, H - 0.12, 0.06, 12, "maku")
    ring(TOP - 0.55, TOP - 0.06, 0.04, 10, "band", fold=0.025)

    # balustrade : trois côtés pleins, ouverte au milieu de la face de l'escalier
    for face in range(4):
        for z in (H + 0.45, H + 0.85):
            if face == 0:
                for sx in (-1, 1):
                    parts.append(box(f"rail{face}{sx}{z:.1f}", (h - 0.55, 0.08, 0.08), (sx * (h + 0.55) / 2, -h + 0.02, z), WOOD_W, bevel=0.01))
            else:
                size = (S, 0.08, 0.08) if face == 1 else (0.08, S, 0.08)
                loc = (0, h - 0.02, z) if face == 1 else ((-h + 0.02) if face == 2 else (h - 0.02), 0, z)
                parts.append(box(f"rail{face}{z:.1f}", size, loc, WOOD_W, bevel=0.01))
    # toit pyramidal (bardeaux sombres), coins relevés, bouton doré au sommet
    roof = cyl("roof", (h + 0.9) * 1.414, 0.12, 1.3, (0, 0, TOP + 0.6), "#4a4246", rot=(0, 0, 45), verts=4, bevel=0.03, smooth=0, grad=(0.8, 1.1))
    for v in roof.data.vertices:
        rr = Vector((v.co.x, v.co.y, 0)).length
        if rr > (h + 0.9) * 1.3:
            v.co.z += 0.32
    parts.append(roof)
    parts.append(box("roof_edge", (S + 1.0, S + 1.0, 0.1), (0, 0, TOP - 0.02), WOOD_D, bevel=0.02))
    parts.append(ball("hoju", 0.2, (0, 0, TOP + 1.35), "#d9b04a", subdiv=2))
    # tambour taiko sur son support, peaux face aux côtés ±X
    drum = cyl("taiko", 0.5, 0.5, 0.78, (0, 0, 0), "#9a3d24", rot=(0, 90, 0), verts=20, bevel=0.0, smooth=180, grad=(0.8, 1.05))
    for v in drum.data.vertices:
        k = 1.0 - (v.co.x / 0.39) ** 2
        v.co.y *= 1.0 + 0.16 * k
        v.co.z *= 1.0 + 0.16 * k
    drum.location = (0, 0.6, H + 0.95)
    apply(drum)
    parts.append(drum)
    for sx in (-1, 1):
        parts.append(cyl(f"skin{sx}", 0.47, 0.47, 0.03, (sx * 0.4, 0.6, H + 0.95), "#eadfc4", rot=(0, 90, 0), verts=20, bevel=0.0, smooth=180))
        parts.append(torus(f"studs{sx}", 0.47, 0.035, (sx * 0.39, 0.6, H + 0.95), "#2a2422", rot=(0, 90, 0), segs=20, rsegs=4))
        parts.append(ball(f"tomoe{sx}", 0.12, (sx * 0.42, 0.6, H + 0.95), "#c8352a", scale=(0.2, 1, 1), subdiv=1))
        parts.append(box(f"stand{sx}", (0.1, 0.12, 0.85), (sx * 0.25, 0.6, H + 0.5), WOOD_D, rot=(0, sx * 18, 0), bevel=0.01))
        parts.append(cyl(f"bachi{sx}", 0.025, 0.03, 0.42, (0.62, 0.25 + sx * 0.08, H + 0.14), WOOD_L, rot=(90, 0, 10), verts=6, bevel=0.0))
    # escalier raide côté -Y : deux limons et huit marches
    run, n = 2.4, 8
    y0 = -h - run
    ln = math.hypot(run, H)
    ang = math.degrees(math.atan2(H, run))
    for sx in (-1, 1):
        parts.append(box(f"stringer{sx}", (0.1, ln, 0.22), (sx * 0.58, y0 + run / 2, H / 2), WOOD_D, rot=(ang, 0, 0), bevel=0.01))
    for i in range(n):
        f = (i + 0.5) / n
        parts.append(box(f"step{i}", (1.1, run / n + 0.06, 0.06), (0, y0 + run * f, H * f), WOOD_L, bevel=0.01))
    join(parts, "yagura")


def _dango(parts, x, y, z, name, rnd):
    """Brochette de trois boulettes rose, blanche et verte (hanami dango)."""
    parts.append(cyl(f"{name}s", 0.008, 0.008, 0.32, (x, y, z + 0.1), WOOD_L, verts=4, bevel=0.0, rot=(rnd.uniform(-8, 8), 70, 0)))
    for k, c in enumerate(("#f2a6b8", "#f6f1e4", "#9cc46a")):
        parts.append(ball(f"{name}{k}", 0.035, (x - 0.06 + k * 0.07, y, z + 0.02 + k * 0.025), c, subdiv=1))


def yatai(name="yatai", canopy=KOHAKU_R, noren="#2f4270", goods="dango"):
    """Échoppe de fête (yatai) ≈ 2,5 m, sur roues : comptoir de bois, auvent rayé incliné vers le client (-Y),
    noren bleu sous l'auvent, friandises sur le comptoir. Origine au sol, au centre."""
    rnd = random.Random(hash(name) & 0xffff)
    parts = [box("cart", (2.0, 0.9, 0.85), (0, 0, 0.62), WOOD_W, grad=(0.75, 1.05)),
             box("top", (2.2, 1.05, 0.06), (0, -0.05, 1.07), WOOD_L, bevel=0.01)]
    for sx in (-1, 1):
        parts.append(cyl(f"wheel{sx}", 0.36, 0.36, 0.08, (sx * 1.05, 0.0, 0.36), WOOD_D, rot=(0, 90, 0), verts=14, bevel=0.01))
        parts.append(cyl(f"hub{sx}", 0.08, 0.08, 0.1, (sx * 1.07, 0.0, 0.36), "#2a2422", rot=(0, 90, 0), verts=8, bevel=0.0))
        for sy in (-1, 1):
            parts.append(box(f"pole{sx}{sy}", (0.07, 0.07, 1.35), (sx * 0.98, sy * 0.42, 1.75), WOOD_D, bevel=0.01))
    # auvent : bandes rayées, la pente descend vers l'avant
    n = 8
    w = 2.3 / n
    for i in range(n):
        parts.append(box(f"canopy{i}", (w + 0.005, 1.4, 0.04), (-1.15 + w * (i + 0.5), -0.12, 2.45), canopy if i % 2 else "#f4efe2",
                         rot=(-14, 0, 0), bevel=0.0, smooth=0, grad=(0.85, 1.05)))
    for i in range(3):   # noren : trois pans sous l'avant de l'auvent
        parts.append(box(f"noren{i}", (0.62, 0.02, 0.36), (-0.66 + i * 0.66, -0.78, 2.05), noren, bevel=0.0, smooth=0, grad=(0.9, 1.05)))
    if goods == "dango":
        for i in range(7):
            _dango(parts, -0.75 + i * 0.25, -0.3 + rnd.uniform(-0.05, 0.05), 1.12, f"dango{i}", rnd)
    else:   # kakigori : bols de glace pilée, sirops de couleur
        for i, c in enumerate(("#e2443a", "#5aa0e0", "#9cc46a", "#f2c84a")):
            x = -0.7 + i * 0.46
            parts.append(cyl(f"bowl{i}", 0.13, 0.09, 0.09, (x, -0.3, 1.15), "#dfe8ee", verts=12, bevel=0.0))
            parts.append(ball(f"ice{i}", 0.13, (x, -0.3, 1.25), "#f6f8fa", scale=(1, 1, 0.9), subdiv=2))
            parts.append(ball(f"syrup{i}", 0.1, (x, -0.3, 1.3), c, scale=(1, 1, 0.5), subdiv=1))
    parts.append(box("sign", (0.7, 0.05, 0.3), (0, -0.5, 1.4), "#f4efe2", bevel=0.01))
    join(parts, name)


def yatai_glace(): yatai("yatai_glace", "#3f7fbf", "#c8352a", "kakigori")


ALL = VEG + ["cliff_rock_1", "cliff_rock_2", "cliff_rock_3", "bay_shoji", "bay_plaster", "bay_window", "bay_plank", "bay_plank_window", "bay_door", "bay_entry", "post", "roof_tile", "roof_thatch", "roof_kaya", "sakura_1", "sakura_2", "sakura_3", "sakura_1_shadow", "sakura_2_shadow", "sakura_3_shadow",
       "torii_3", "torii_4", "torii_6", "torii_7", "toro", "ledge_1", "ledge_2", "ledge_3", "chochin", "chochin_white", "camphor", "camphor_shadow", "jizo", "kodama", "furin", "matsu_1", "matsu_2", "momi_1", "momi_2", "momi_1_shadow"]

if __name__ == "__main__":
    reset()
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n in (argv or ALL):
        build(n, globals()[n])
