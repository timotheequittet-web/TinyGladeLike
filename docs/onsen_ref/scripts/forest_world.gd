class_name ForestWorld
extends SpiritWorld
## Le monde de la Forêt — le bois des cèdres endormis. On le joue toujours à dos de Titou (scripts/titou.gd) :
## des îlots de mousse au-dessus d'une mer de brume, puis l'ascension d'un cèdre géant jusqu'à la canopée où dort
## l'esprit de la Forêt, un grand saro pris dans une malédiction d'épines.
##  S0 la prairie : deux ruisseaux à franchir (le second au galop) · S1 les racines : une racine en dos d'âne, deux
##  nœuds de racine où se poser juste, deux arches basses où se faufiler · S2 le grand cèdre : on grimpe son écorce
##  rousse de branche en branche, en spirale ; une bande de mousse glissante oblige à passer par le cèdre voisin et
##  à s'en élancer · S3 la branche aux châtaignes qui roulent, puis les rameaux qui cassent sous le poids · S4 la
##  canopée : pont de corde troué, courants de pétales qui portent, cimes étroites · S5 le nid du sommet : trois
##  nœuds d'épines à dissiper au grelot (un au bord, un en haut d'un chicot à grimper, un au bout d'une branche,
##  derrière une arche basse) ; le saro se réveille, la forêt fleurit, le torii s'allume.
## Repère local : y = 0 est la mer de brume (y tomber ramène à la dernière lanterne) ; on avance vers -Z puis +X.
## Angles autour d'un tronc en degrés, de +X vers +Z. Tailles réglées sur Titou (bond : 4 m de haut, ~10 m au trot).

const ORIGIN := Vector3(3200, 300, 0)
const C1 := Vector2(0, -104)            # le grand cèdre qu'on gravit
const C1_R := 4.5
const C2 := Vector2(-18.0, -116.6)      # son voisin : on y passe pour franchir la mousse glissante
const C2_R := 3.5
const SLICK := [32.0, 43.0]             # la bande de mousse glissante de C1
const C3 := Vector2(54.7, -88.0)        # le cèdre aux rameaux cassants (écorce lisse : on n'y grimpe pas)
const C3_R := 4.0
const SUMMIT := Vector3(182, 110, -53)
const SUMMIT_R := 14.0
## Branches de C1 : [angle, hauteur, longueur, largeur]
const BOUGHS := [[160.0, 21.0, 7.0, 3.2], [215.0, 30.0, 9.0, 3.2], [215.0, 44.0, 9.0, 3.8], [270.0, 53.0, 7.0, 3.2],
	[325.0, 62.0, 7.0, 3.2], [20.0, 70.5, 12.0, 4.6]]
const RAMP := [Vector3(18.5, 71.0, -97.5), Vector3(47.0, 79.0, -90.0)]   # la branche aux châtaignes
const NUT_SPEED := 9.0
const NUT_PERIOD := 5.2
const NUT_R := 1.0
const TWIGS := [[235.0, 81.5], [280.0, 84.0], [325.0, 86.5], [10.0, 89.0]]   # rameaux autour de C3 : [angle, hauteur]
const TWIG_R := 9.5
const TWIG_HOLD := 1.0                  # un rameau tient ce temps sous Titou…
const TWIG_BACK := 3.5                  # … et repousse après ça
const STREAMS := [[Vector3(90.5, 95.0, -57.5), Vector3(112.0, 102.5, -41.0)], [Vector3(152.5, 107.0, -36.5), Vector3(173.0, 113.5, -48.0)]]
const STREAM_R := 3.2
const STREAM_V := 11.0
const CROWNS := [[Vector3(87, 91.5, -60), 5.0], [Vector3(115, 99.5, -39), 5.5], [Vector3(128, 100.5, -35), 2.6],
	[Vector3(138.5, 102.0, -40), 2.4], [Vector3(149, 103.5, -35), 2.8]]
const GATE_CLEAR := 2.1                 # sous les arches : Titou debout (2,6 m) ne passe pas, aplati (1,8 m) oui
const GATES := [5.0, -0.5]              # x des deux arches de la corniche des racines

const BARK := Color(0.4, 0.3, 0.25)
const BARK_WARM := Color(0.66, 0.4, 0.24)   # l'écorce rousse : celle qui se grimpe
const MOSS := Color(0.36, 0.5, 0.22)
const MOSS_LIGHT := Color(0.52, 0.64, 0.28)
const LEAF := Color(0.2, 0.36, 0.2)
const EARTH := Color(0.4, 0.31, 0.24)
const THORN := Color(0.26, 0.16, 0.24)
const LILAC := Color(0.66, 0.5, 0.86)

var knots: Array[Dictionary] = []       # {p: Vector3, done: bool, thorns: Node3D, bloom: Node3D}
var nuts: Array[Dictionary] = []        # {node: Node3D, phase: float, side: float}
var twigs: Array[Dictionary] = []       # {body: AnimatableBody3D, p: Vector3, t: float, down: float}
var wake_t := -1.0                      # temps depuis le réveil de l'esprit (-1 : il dort)
var bloom := 0.0                        # 0 : sous-bois voilé ; 1 : la forêt a fleuri
var spirit: Node3D
var gate_ps: Array[Vector3] = []        # milieu de chaque arche basse (test)
var _portal := Vector3.ZERO
var _arrival := Vector3.ZERO
var _hints: Array = []
var _noise := FastNoiseLite.new()
var _t := 0.0
var _saved_env := {}
var _gst := SurfaceTool.new()           # le sol de tous les îlots : un seul maillage, une seule collision
var _gfaces := PackedVector3Array()
var _trunks := []                       # [centre, rayon, y0, y1, couleur] -> un MultiMesh
var _crowns := []                       # [pied de la couronne, rayon, hauteur]
var _plants := []                       # [nom, transform global] : arbres, fougères et buissons peints de la carte (Nature.plant)
var _blooms := [[], [], []]             # les fleurs, en trois vagues : elles n'éclosent qu'au réveil de l'esprit
var _flower_roots: Array[Node3D] = []
var _isles := []                        # [centre, rx, rz] des îlots herbus
var _coil: Node3D                       # les épines enroulées autour de l'esprit
var _coil_body: StaticBody3D
var _petals: Array[GPUParticles3D] = []
var _glow: OmniLight3D


func _init() -> void:
	id = "foret"
	title = "Le monde de la Forêt — le bois des cèdres endormis"
	hour = 16.4
	portal_text = "[E] Prier au petit autel : le torii des cèdres s'ouvre"
	portal_asleep = "Le petit torii dort sous les érables… il faudra d'abord savoir planer."


static func pol(c: Vector2, a: float, r: float, y: float) -> Vector3:
	## Point à r du centre c dans la direction a (degrés, de +X vers +Z), à la hauteur y.
	var ar := deg_to_rad(a)
	return Vector3(c.x + cos(ar) * r, y, c.y + sin(ar) * r)


func portal() -> Vector3:
	return _portal


func arrival() -> Vector3:
	return _arrival


# ---------------------------------------------------------------- construction

func _build() -> void:
	position = ORIGIN
	_noise.seed = 311
	_noise.frequency = 1.0
	_rng.seed = 2611
	_sb = StaticBody3D.new()
	_sb.name = "Sol"
	add_child(_sb)
	_gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	_s0_meadow()
	_s1_roots()
	_s2_cedar()
	_s3_nuts_and_twigs()
	_s4_canopy()
	_s5_summit()
	_far_trees()
	_finish()
	_shrine()
	_hints = [
		{p = Vector3(0, 6, -8), text = "Espace : Titou bondit. Garde la touche pour un grand bond, relâche tôt pour un petit."},
		{p = Vector3(0, 6, -31), text = "Ce ruisseau est large : Maj pour galoper, et le bond s'allonge."},
		{p = Vector3(9, 12.5, -93.5), text = "Ctrl : Titou s'aplatit et se faufile sous les racines basses."},
		{p = Vector3(-9, 12.5, -96), text = "L'écorce rousse se grimpe : cours contre elle. Les griffes de Titou ne tiennent qu'un moment — vise la branche suivante, en spirale."},
		{p = pol(C1, 215.0, 10.0, 30.0), text = "La mousse est trop glissante ici. Bondis sur le cèdre voisin, grimpe, puis Espace : Titou s'élance de la paroi."},
		{p = pol(C1, 20.0, 12.0, 70.5), text = "Des châtaignes dévalent la grande branche : bondis par-dessus au bon moment."},
		{p = Vector3(47.5, 79.0, -89.8), text = "Ces rameaux plient puis cassent sous le poids : ne t'attarde pas. Un saut trop court ? Titou s'agrippe au rebord."},
		{p = Vector3(87, 91.5, -60), text = "Bondis dans le courant de pétales : il porte Titou jusqu'à la cime suivante."},
		{p = SUMMIT + Vector3(-8.5, 0, 4.7), text = "Trois nœuds d'épines retiennent l'esprit endormi. Le grelot de Titou les dissipe : approche-toi de chacun."},
	]


func _s0_meadow() -> void:
	_isle(Vector3(0, 6, 0), 15.0, 13.0, 1)
	_isle(Vector3(0, 3.4, -16), 12.0, 6.0, 2, 8.0, 0.0)      # le lit du premier ruisseau (on y tombe sans mal)
	_isle(Vector3(0, 6, -27), 13.0, 8.5, 3)
	_isle(Vector3(0, 3.4, -40.5), 12.0, 8.0, 4, 8.0, 0.0)    # le lit du second, plus large
	_isle(Vector3(0, 6.5, -55), 14.0, 10.0, 5)
	for b: Array in [[-16.0, 5.2], [-40.5, 7.4]]:
		_water(Vector3(0, 3.62, b[0]), Vector2(23.0, b[1]))
		parts.append([Geo.glb("rock_1"), Geo.at(Vector3(-6.5, 3.2, float(b[0]) + 0.8), Vector3(0, 1.0, 0), Vector3.ONE * 0.8), Geo.OWN])
		parts.append([Geo.glb("rock_2"), Geo.at(Vector3(7.0, 3.2, float(b[0]) - 0.6), Vector3(0, 2.2, 0), Vector3.ONE * 0.7), Geo.OWN])
	# le torii de l'arrivée : la sortie
	var tor := Transform3D(Basis.from_scale(Vector3.ONE * 1.25), Vector3(0, 5.9, 9.5))
	var ia := Geo.ia_swap("torii", Geo.glb("torii_6"), tor, false)
	if ia:
		add_child(ia)
	else:
		parts.append([Geo.glb("torii_6"), tor, Geo.OWN])
	Props.torii_bodies(self, "torii_6", tor, ia != null)
	exits.append({p = Vector3(0, 6, 9.5), r = 4.5, text = "[E] Rentrer à l'archipel", open = func() -> bool: return true})
	add_lantern(Vector3(0, 6, 4), 0.0, parts)
	_mark(Vector3(0, 6, 4))
	_mark(Vector3(0, 6, -11), "walk")
	_mark(Vector3(0, 6, -20.5))
	_mark(Vector3(0, 6, -33.5), "walk")
	_mark(Vector3(0, 6.5, -47))
	add_lantern(Vector3(0, 6.5, -55), 0.0, parts)
	_mark(Vector3(0, 6.5, -55), "walk")
	for t: Array in [[-10.0, 2.0, 1.3], [10.5, -3.0, 1.1], [-9.0, -27.0, 1.2], [9.5, -55.0, 1.3], [-10.0, -57.0, 1.0]]:
		_sakura(Vector3(t[0], 6.0 if float(t[1]) > -40.0 else 6.5, t[1]), t[2])
	# le piton de la cascade, à l'est : l'eau tombe dans la brume
	_isle(Vector3(36, 34, -30), 9.0, 8.0, 6, 44.0)
	_sakura(Vector3(38, 34, -31), 1.4)
	var fall := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(5.0, 35.0)
	fall.mesh = q
	fall.material_override = Mats.water({fall = true, flow_speed = 1.4, streaks = 1.0, shallow = Color(0.7, 0.88, 0.9), foam = Color(0.97, 0.99, 1.0)})
	fall.position = Vector3(26.4, 16.5, -30)
	fall.rotation.y = -PI * 0.5
	add_child(fall)
	add_child(Fx.mist(Vector3(25, 1.5, -30), Vector3(6, 2, 6), 0.8))


func _s1_roots() -> void:
	# une racine en dos d'âne quitte l'îlot, puis deux nœuds de racine où il faut se poser juste
	var top := [Vector3(0, 6.5, -63), Vector3(-2, 7.6, -69), Vector3(-4, 8.8, -74.5)]
	_walk_root(top, 2.6)
	_limb(top[2] - Vector3(0, 1.0, 0), Vector3(-7, -6, -84), 1.3, 0.8, BARK)
	_mark(top[1], "walk")
	_mark(top[2] - Vector3(0, 0, -0.8), "walk")
	for kp: Vector3 in [Vector3(0, 9.6, -81), Vector3(6, 11.0, -86)]:
		_knob(kp, 1.9)
		_mark(kp)
	# la corniche au pied du grand cèdre, barrée par deux arches de racines
	_isle(Vector3(-2, 12.5, -95.5), 15.0, 5.5, 7, 9.0)
	_mark(Vector3(9, 12.5, -93.5))
	for gx: float in GATES:
		_gate(Vector3(gx, 12.5, -94.5))
	_mark(Vector3(2.2, 12.5, -94.5), "walk")
	add_lantern(Vector3(-9, 12.5, -96), -0.85, parts)
	_mark(Vector3(-9, 12.5, -96), "walk")
	_sakura(Vector3(11, 12.5, -94), 0.9)


func _s2_cedar() -> void:
	_trunk(C1, C1_R, -10.0, 100.0, true, SLICK)
	_trunk(C2, C2_R, -10.0, 92.0, true)
	# la bande de mousse glissante : un manchon vert vif, luisant, des gouttes
	parts.append([Geo.cyl(C1_R * 1.09, C1_R * 1.09, float(SLICK[1]) - float(SLICK[0]), 22), Geo.at(Vector3(C1.x, (float(SLICK[0]) + float(SLICK[1])) * 0.5, C1.y)), Color(0.3, 0.5, 0.2)])
	for k in 14:
		var a := k * 26.0
		parts.append([Geo.sphere(0.5, 8, 5), Geo.at(pol(C1, a, C1_R * 1.09, float(SLICK[0]) + fposmod(k * 3.7, 11.0)), Vector3.ZERO, Vector3(1.8, 0.7, 1.8)), Color(0.4, 0.6, 0.24)])
		_plant("fern", pol(C1, a + 9.0, C1_R * 1.1, float(SLICK[0]) + fposmod(k * 5.3, 10.0)), 1.6)
	for i in BOUGHS.size():
		var b: Array = BOUGHS[i]
		_bough(C1, C1_R, b[0], b[1], b[2], b[3])
		if i == 2:   # on y arrive du cèdre voisin : un bond jusqu'à son écorce, on grimpe, puis un bond mural
			_mark(pol(C2, 35.0, C2_R + Titou.R, float(BOUGHS[1][1]) + 1.5), "wall")
			_mark(pol(C1, b[0], C1_R + float(b[2]) - 1.5, b[1]), "leap")
		_mark(pol(C1, b[0], C1_R + float(b[2]) * 0.55, b[1]), "walk" if i == 2 else "climb")
	var b2: Array = BOUGHS[2]
	add_lantern(pol(C1, b2[0], C1_R + 3.5, b2[1]), deg_to_rad(-float(b2[0])) + PI * 0.5, parts)
	var b5: Array = BOUGHS[5]
	add_lantern(pol(C1, b5[0], C1_R + 5.0, b5[1]), deg_to_rad(-float(b5[0])) - PI * 0.5, parts)
	_shimenawa(Vector3(C1.x, 16.0, C1.y), C1_R * 1.08)


func _s3_nuts_and_twigs() -> void:
	_trunk(C3, C3_R, -10.0, 112.0, false)
	var a: Vector3 = RAMP[0]
	var b: Vector3 = RAMP[1]
	_ramp(a, b, 3.4)
	_mark(a.lerp(b, 0.08))
	_mark(a.lerp(b, 0.5), "walk")
	_mark(a.lerp(b, 0.95), "walk")
	_pad(Vector3(47.5, 79.0, -89.8), 3.0, false)
	for k in 2:
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = _nut_mesh()
		mi.material_override = Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.3})
		n.add_child(mi)
		add_child(n)
		nuts.append({node = n, phase = k * 0.5, side = 0.85 if k == 0 else -0.85})
	for td: Array in TWIGS:
		var p := pol(C3, td[0], TWIG_R, td[1])
		var body := AnimatableBody3D.new()
		body.sync_to_physics = false
		body.position = p
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 1.7
		sh.height = 0.6
		cs.shape = sh
		cs.position.y = -0.3
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		var out := (p - Vector3(C3.x, p.y, C3.y)).normalized()
		mi.mesh = Geo.merge([
			[Geo.sphere(1.9, 14, 6), Geo.at(Vector3(0, -0.42, 0), Vector3.ZERO, Vector3(1, 0.22, 1)), LEAF.lightened(0.12)],
			[Geo.cyl(1.45, 1.6, 0.1, 14), Geo.at(Vector3(0, -0.04, 0)), MOSS_LIGHT],
			[Geo.cyl(0.16, 0.3, TWIG_R - C3_R, 7), Transform3D(Basis(Quaternion(Vector3.UP, out)), -out * (TWIG_R - C3_R) * 0.5 - Vector3(0, 0.5, 0)), BARK.lightened(0.1)],
		])
		mi.material_override = Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.2})
		body.add_child(mi)
		add_child(body)
		twigs.append({body = body, p = p, t = 0.0, down = 0.0})
		_mark(p)
	_bough(C3, C3_R, 50.0, 91.0, 9.0, 4.2)
	var lp := pol(C3, 50.0, C3_R + 4.5, 91.0)
	add_lantern(lp, deg_to_rad(-50.0) - PI * 0.5, parts)
	_mark(lp)


func _s4_canopy() -> void:
	var a := Vector3(63.5, 91.0, -77.5)
	var b := Vector3(84.0, 91.5, -62.0)
	_bridge(a, b, [[0.3, 0.42], [0.6, 0.72]], true, 3.2)
	_mark(bridge_pt(a, b, 0.15))
	_mark(bridge_pt(a, b, 0.51))
	_mark(bridge_pt(a, b, 0.88))
	for i in CROWNS.size():
		var cd: Array = CROWNS[i]
		_pad(cd[0], cd[1], true)
		_mark(cd[0], "carry" if i == 1 else "")
	var c1: Vector3 = CROWNS[1][0]
	add_lantern(c1 + Vector3(-1.5, 0, 1.5), -1.87, parts)
	for sd: Array in STREAMS:
		var s0: Vector3 = sd[0]
		var s1: Vector3 = sd[1]
		var fx := Fx.petals(s0, Vector3(1.6, 1.6, 1.6), 450)
		var pm := fx.process_material as ParticleProcessMaterial
		pm.direction = (s1 - s0).normalized()
		pm.spread = 3.0
		pm.gravity = Vector3.ZERO
		pm.initial_velocity_min = STREAM_V * 0.85
		pm.initial_velocity_max = STREAM_V * 1.15
		pm.scale_min = 2.2
		pm.scale_max = 4.0
		fx.lifetime = s0.distance_to(s1) / STREAM_V
		fx.preprocess = fx.lifetime
		fx.visibility_aabb = AABB(Vector3(-50, -30, -50), Vector3(100, 60, 100))
		add_child(fx)
		add_child(Fx.motes((s0 + s1) * 0.5, Vector3(absf(s1.x - s0.x) * 0.5 + 2.0, 4.0, absf(s1.z - s0.z) * 0.5 + 2.0), 90))


func _s5_summit() -> void:
	_isle(SUMMIT, SUMMIT_R, SUMMIT_R, 9, 6.0)
	_trunks.append([Vector2(SUMMIT.x, SUMMIT.z), 5.0, -10.0, SUMMIT.y - 2.0, BARK])
	for k in 12:   # le feuillage qui porte le nid
		var a := k * 30.0 + 8.0
		parts.append([Geo.sphere(4.6, 10, 6), Geo.at(pol(Vector2(SUMMIT.x, SUMMIT.z), a, SUMMIT_R - 1.5, SUMMIT.y - 4.4), Vector3.ZERO, Vector3(1, 0.62, 1)), LEAF.darkened(0.1)])
	for k in 64:
		_plant("bush", pol(Vector2(SUMMIT.x, SUMMIT.z), k * 5.6, SUMMIT_R + 0.3 + 1.2 * (k % 2), SUMMIT.y - 1.6 - 1.3 * (k % 3)), _rng.randf_range(1.7, 2.2))
	var sc := Vector2(SUMMIT.x, SUMMIT.z)
	var entry := SUMMIT + Vector3(-8.5, 0, 4.7)
	add_lantern(entry, -1.07, parts)
	_mark(entry, "carry")
	# l'esprit de la Forêt, endormi au milieu, et les épines enroulées autour de lui
	var fit := Geo.ia_fit("esprit_foret", AABB(Vector3(-1.06, 0, -2.75), Vector3(0.733, 1.715, 1.901) * 2.9))
	spirit = Node3D.new()
	if fit.is_empty():   # pas encore de modèle : une silhouette sobre de saro
		var mi := MeshInstance3D.new()
		mi.mesh = Geo.merge([[Geo.sphere(1.5, 14, 8), Geo.at(Vector3(0, 2.6, 0), Vector3.ZERO, Vector3(0.8, 0.85, 1.6)), Color(0.5, 0.46, 0.4)],
			[Geo.sphere(0.9, 12, 8), Geo.at(Vector3(0, 3.9, 2.2)), Color(0.56, 0.52, 0.46)],
			[Geo.sphere(1.3, 12, 6), Geo.at(Vector3(0, 3.5, 0.6), Vector3.ZERO, Vector3(0.8, 0.7, 1.2)), MOSS]])
		mi.material_override = Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.3})
		spirit.add_child(mi)
	else:
		spirit.add_child(Geo.ia_node(fit, Transform3D.IDENTITY, "", false))
	spirit.position = SUMMIT
	spirit.rotation.y = -1.07   # il regarde l'arrivée
	add_child(spirit)
	spirit.add_child(Fx.fireflies(Vector3(0, 3, 0), Vector3(4, 3, 4), 40))
	_coil = Node3D.new()
	_coil.position = SUMMIT
	add_child(_coil)
	var cp := []
	for ring in 9:
		_thorn_arc(cp, Vector3.ZERO, 4.7 - ring * 0.32 + 0.4 * sin(ring * 2.1), 0.3 + ring * 0.62, ring * 1.3, 0.15 - ring * 0.007)
	_coil.add_child(_mesh_of(cp))
	_coil_body = StaticBody3D.new()
	var ccs := CollisionShape3D.new()
	var csh := CylinderShape3D.new()
	csh.radius = 4.9
	csh.height = 6.0
	ccs.shape = csh
	ccs.position.y = 3.0
	_coil_body.add_child(ccs)
	_coil.add_child(_coil_body)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.9, 0.6)
	_glow.omni_range = 30.0
	_glow.light_energy = 0.0
	_glow.position = SUMMIT + Vector3(0, 6, 0)
	add_child(_glow)
	# nœud 1 : au bord du nid
	var k1 := pol(sc, 300.0, 10.5, SUMMIT.y)
	# nœud 2 : en haut d'un chicot à l'écorce rousse
	var snag := pol(sc, 40.0, 10.0, SUMMIT.y)
	_trunk(Vector2(snag.x, snag.z), 2.0, SUMMIT.y - 3.0, SUMMIT.y + 9.0, true)
	parts.append([Geo.cyl(1.95, 2.05, 0.2, 14), Geo.at(snag + Vector3(0, 8.95, 0)), Color(0.74, 0.6, 0.42)])
	# nœud 3 : au bout d'une branche étroite, derrière une arche basse
	_bough(sc, SUMMIT_R - 1.5, 230.0, SUMMIT.y, 13.0, 2.8)
	var gate := pol(sc, 230.0, 18.5, SUMMIT.y)
	_arch(gate, deg_to_rad(90.0 - 230.0), 2.8)
	gate_ps.append(gate)
	var k3 := pol(sc, 230.0, 24.0, SUMMIT.y)
	for kp: Vector3 in [k1, snag + Vector3(0, 9.0, 0), k3]:
		var th := Node3D.new()
		th.position = kp
		var tp := []
		_thorn_arc(tp, Vector3.ZERO, 0.9, 0.5, 0.0, 0.16)
		_thorn_arc(tp, Vector3(0, 0.5, 0), 0.6, 0.6, 1.5, 0.13)
		tp.append([Geo.sphere(0.42, 10, 8), Geo.at(Vector3(0, 1.1, 0)), Color(0.5, 0.14, 0.4)])
		th.add_child(_mesh_of(tp))
		add_child(th)
		var wn := Node3D.new()   # la glycine qui prend sa place
		wn.position = kp
		wn.add_child(_mesh_of(_wisteria(1.8, 6)))
		wn.visible = false
		add_child(wn)
		knots.append({p = kp, done = false, thorns = th, bloom = wn})
	_mark(k1, "walk")
	_mark(snag + Vector3(0, 9.0, 0), "climb")
	_mark(pol(sc, 230.0, 15.0, SUMMIT.y), "walk")
	_mark(k3 - (k3 - SUMMIT).normalized() * 1.5, "walk")
	# le torii du retour, éteint tant que l'esprit dort
	var ex := pol(sc, 100.0, 10.5, SUMMIT.y)
	parts.append([Geo.glb("torii_3"), Geo.at(ex - Vector3(0, 0.1, 0), Vector3(0, deg_to_rad(-100.0) + PI * 0.5, 0), Vector3.ONE * 1.6), Geo.OWN])
	exits.append({p = ex, r = 4.5, text = "[E] Rentrer à l'archipel (le chemin des fleurs)", open = func() -> bool: return freed})
	# pétales et lueurs du final (éteints jusqu'au réveil)
	for at: Vector3 in [SUMMIT + Vector3(0, 12, 0), Vector3(128, 110, -38), Vector3(60, 98, -85), Vector3(0, 60, -104), Vector3(0, 18, -30)]:
		var fx := Fx.petals(at, Vector3(18, 3, 18), 220)
		fx.emitting = false
		add_child(fx)
		_petals.append(fx)


# ---------------------------------------------------------------- briques du décor

func _isle(c: Vector3, rx: float, rz: float, seed_v: int, depth := 12.0, flora := 1.0) -> void:
	## Îlot de terre moussue : dessus plat à c.y, bord en bourrelet, flancs de terre et de roche qui s'amincissent.
	const SEG := 36
	var prof := [[0.0, 1.0], [-0.5, 1.05], [-1.8, 0.95], [-depth * 0.45, 0.8], [-depth, 0.5]]
	var rings := []
	for pr: Array in prof:
		var row := []
		var dy: float = pr[0]
		for s in SEG + 1:
			var a := TAU * s / SEG
			var e := rx * rz / sqrt(pow(rz * cos(a), 2.0) + pow(rx * sin(a), 2.0))
			var nz := _noise.get_noise_3d(cos(a) * 1.6 + seed_v * 3.1, sin(a) * 1.6, dy * 0.2)
			row.append(c + Vector3(cos(a), 0, sin(a)) * e * float(pr[1]) * (1.0 + 0.06 * nz * (1.0 if dy > -1.0 else 2.5)) + Vector3(0, dy, 0))
		rings.append(row)
	var side_col := func(v: Vector3) -> Color:
		var d := c.y - v.y
		var n := _noise.get_noise_3d(v.x * 0.3, v.y * 0.5, v.z * 0.3)
		var col := MOSS.lerp(EARTH, smoothstep(0.3, 1.6, d + n))
		return col.lerp(Color(0.5, 0.5, 0.48), smoothstep(2.0, depth * 0.6, d + n * 2.0) * 0.8).darkened(0.25 * smoothstep(depth * 0.4, depth, d))
	for j in rings.size() - 1:
		for s in SEG:
			var q: Array = [rings[j][s], rings[j + 1][s], rings[j + 1][s + 1], rings[j][s + 1]]
			for tri: Array in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				for v: Vector3 in tri:
					_gst.set_color((side_col.call(v) as Color).srgb_to_linear())
					_gst.add_vertex(v)
					_gfaces.append(v)
	const RINGS := 6
	var grid := [rings[0]]
	for k in range(1, RINGS + 1):
		var row := []
		var u := float(k) / RINGS
		for s in SEG + 1:
			var e: Vector3 = rings[0][s]
			row.append(Vector3(lerpf(e.x, c.x, u), c.y + 0.05 * minf(1.0, u * 4.0), lerpf(e.z, c.z, u)))
		grid.append(row)
	var top_col := func(v: Vector3) -> Color:
		var n := _noise.get_noise_3d(v.x * 0.25 + seed_v, v.z * 0.25, 5.0) * 0.5 + 0.5
		var m := _noise.get_noise_3d(v.x * 1.1, v.z * 1.1, 17.0) * 0.5 + 0.5
		return Color(0.2, 0.33, 0.13).lerp(Color(0.3, 0.44, 0.17), n).lerp(Color(0.42, 0.46, 0.22), m * 0.25)
	for k in RINGS:
		for s in SEG:
			var q: Array = [grid[k][s], grid[k][s + 1], grid[k + 1][s + 1], grid[k + 1][s]]
			for tri: Array in [[q[0], q[1], q[2]], [q[0], q[2], q[3]]]:
				for v: Vector3 in tri:
					_gst.set_color((top_col.call(v) as Color).srgb_to_linear())
					_gst.add_vertex(v)
					_gfaces.append(v)
	if flora > 0.0:
		_isles.append([c, rx, rz])
	for k in int(rx * rz * 0.16 * flora):   # fougères et buissons au bord, fleurs partout (elles n'éclosent qu'au réveil de l'esprit)
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(0.7, 0.93)
		_plant("fern" if k % 4 != 0 else "bush", c + Vector3(cos(a) * rx * d, 0, sin(a) * rz * d), _rng.randf_range(0.9, 1.5))
	for k in int(rx * rz * 0.45 * flora):
		var a := _rng.randf() * TAU
		var d := sqrt(_rng.randf()) * 0.9
		_flower(c + Vector3(cos(a) * rx * d, 0, sin(a) * rz * d))


func _plant(nm: String, lp: Vector3, s: float) -> void:
	_plants.append([nm, Geo.at(ORIGIN + lp - Vector3(0, 0.05, 0), Vector3(0, _rng.randf() * TAU, 0), Vector3.ONE * s)])


func _flower(lp: Vector3) -> void:
	var k := _rng.randi() % 3
	(_blooms[k] as Array).append([["flowers_meadow", "flowers_warm", "flower"][k], Geo.at(ORIGIN + lp, Vector3(0, _rng.randf() * TAU, 0), Vector3.ONE * _rng.randf_range(0.9, 1.5))])


func _water(c: Vector3, size: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.position = c
	mi.material_override = Mats.water({depth_scale = 1.2, wave = 0.04, ripple = 0.9, ripple_scale = 3.0, opacity = 0.7,
		shallow = Color(0.6, 0.82, 0.8), deep = Color(0.3, 0.5, 0.52), foam_amount = 1.2, shore_width = 0.5})
	add_child(mi)


func _limb(a: Vector3, b: Vector3, r0: float, r1: float, col: Color) -> void:
	## Membre de bois (racine, rameau, liane) de a (rayon r0) à b (rayon r1) ; décor seul, sans collision.
	var d := b - a
	var up := d.normalized()
	var bs := Basis(Quaternion(Vector3.UP, up)) if up.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	parts.append([Geo.cyl(r1, r0, d.length(), 9), Transform3D(bs, (a + b) * 0.5), col])
	parts.append([Geo.sphere(r1, 8, 5), Geo.at(b), col])


func _walk_root(top: Array, w: float) -> void:
	## Racine sur laquelle on marche : « top » est la ligne de son dos.
	for i in top.size() - 1:
		var a: Vector3 = top[i]
		var b: Vector3 = top[i + 1]
		var d := b - a
		var bs := Basis.looking_at(d.normalized())
		_box(Vector3(w, 1.2, d.length() + 0.3), Transform3D(bs, (a + b) * 0.5 - bs.y * 0.6))
		_limb(a - Vector3(0, w * 0.42, 0), b - Vector3(0, w * 0.42, 0), w * 0.55, w * 0.52, BARK)
		parts.append([Geo.box(Vector3(w * 0.72, 0.14, d.length())), Transform3D(bs, (a + b) * 0.5 - bs.y * 0.05), MOSS])


func _knob(c: Vector3, r: float) -> void:
	## Nœud de racine qui sort de la brume : un dessus rond, étroit.
	_cyl_col(r, 1.4, c - Vector3(0, 0.7, 0))
	parts.append([Geo.sphere(r * 1.12, 12, 8), Geo.at(c - Vector3(0, r * 0.62, 0), Vector3.ZERO, Vector3(1, 0.62, 1)), BARK])
	parts.append([Geo.cyl(r * 0.8, r * 0.92, 0.12, 14), Geo.at(c - Vector3(0, 0.03, 0)), MOSS_LIGHT])
	_limb(c - Vector3(0, 0.8, 0), Vector3(c.x + 1.5, -6.0, c.z + 1.0), r * 0.8, r * 0.5, BARK)
	_limb(c - Vector3(0, 0.6, 0), Vector3(c.x - 3.0, c.y - 5.0, c.z - 3.5), r * 0.5, r * 0.25, BARK.darkened(0.1))


func _gate(c: Vector3) -> void:
	## Arche de racines en travers de la corniche (elle court le long de X) : on ne passe que dessous, aplati.
	_arch(c, PI * 0.5, 4.0)
	gate_ps.append(c)
	# de part et d'autre de l'ouverture, les racines ferment la corniche jusqu'au tronc et jusqu'au vide
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(2.6, 9.0, 4.5), Transform3D(Basis(), c + Vector3(0, 4.5, sz * 4.25)))
		for k in 3:
			_limb(c + Vector3(-0.8 + k * 0.8, -1.0, sz * (2.6 + k * 1.3)), c + Vector3(0.3 - k * 0.3, 8.5, sz * (2.4 + k * 0.9)), 0.9, 0.7, BARK.darkened(0.08 * k))


func _arch(c: Vector3, yaw: float, width: float) -> void:
	## Arche basse (GATE_CLEAR de haut, « width » de large) : le passage va le long de l'axe -Z tourné de yaw.
	var bs := Basis(Vector3.UP, yaw)
	_box(Vector3(width + 1.0, 7.0, 2.6), Transform3D(bs, c + Vector3(0, GATE_CLEAR + 3.5, 0)))
	var side := bs.x
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(1.4, GATE_CLEAR + 0.2, 2.6), Transform3D(bs, c + side * sx * (width * 0.5 + 0.7) + Vector3(0, GATE_CLEAR * 0.5, 0)))
		_limb(c + side * sx * (width * 0.5 + 0.8) - Vector3(0, 1.0, 0), c + side * sx * (width * 0.5 + 0.2) + Vector3(0, GATE_CLEAR + 1.2, 0), 1.0, 0.9, BARK)
	for k in 3:   # les grosses racines qui passent par-dessus
		var z := bs.z * (k - 1) * 0.8
		_limb(c - side * (width * 0.5 + 1.2) + Vector3(0, GATE_CLEAR + 1.1 + k * 1.6, 0) + z, c + side * (width * 0.5 + 1.2) + Vector3(0, GATE_CLEAR + 1.3 + k * 1.5, 0) + z, 1.15, 1.05, BARK.darkened(0.06 * k))
	for k in 11:   # lambeaux de mousse qui pendent : on voit qu'il faut baisser la tête
		var o := side * (k - 5) * width * 0.09 + bs.z * (0.9 if k % 2 == 0 else -0.9)
		var len_ := 0.35 + 0.3 * fposmod(k * 0.37, 1.0)
		parts.append([Geo.cyl(0.1, 0.02, len_, 5), Geo.at(c + o + Vector3(0, GATE_CLEAR + 0.45 - len_ * 0.5, 0)), MOSS.darkened(0.15 * (k % 3))])


func _trunk(c: Vector2, r: float, y0: float, y1: float, climb: bool, slick := []) -> void:
	## Tronc de cèdre : un corps de collision à lui (méta « grimpable » si son écorce rousse se grimpe), sa couronne.
	_trunks.append([c, r, y0, y1, BARK_WARM if climb else BARK])
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = y1 - y0
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(c.x, (y0 + y1) * 0.5, c.y)
	if climb:
		body.set_meta("grimpable", true)
		if not slick.is_empty():
			body.set_meta("lisse", [ORIGIN.y + float(slick[0]), ORIGIN.y + float(slick[1])])
	add_child(body)
	if y1 - y0 > 60.0:
		_crowns.append([Vector3(c.x, y1 - 22.0, c.y), r * 3.6, 46.0])


func _bough(c: Vector2, tr: float, a: float, y: float, length: float, w: float) -> void:
	## Grosse branche horizontale qui sort d'un tronc (rayon tr) dans la direction a ; son dessus est à y.
	var d := pol(Vector2.ZERO, a, 1.0, 0.0)
	var side := d.cross(Vector3.UP)
	var mid := Vector3(c.x, y, c.y) + d * (tr - 0.5 + (length + 0.5) * 0.5)
	var bs := Basis(side, Vector3.UP, side.cross(Vector3.UP))
	_box(Vector3(w, 1.2, length + 0.5), Transform3D(bs, mid - Vector3(0, 0.6, 0)))
	parts.append([Geo.cyl(w * 0.4, w * 0.56, length + 1.0, 10), Transform3D(Basis(side, d, Vector3.UP * 0.6), mid - Vector3(0, w * 0.3, 0)), BARK.lightened(0.06)])
	parts.append([Geo.box(Vector3(w * 0.74, 0.14, length)), Transform3D(bs, mid - Vector3(0, 0.05, 0)), MOSS])
	var tip := Vector3(c.x, y, c.y) + d * (tr + length)
	for k in 3:   # bouquets de feuillage au bout et dessous
		parts.append([Geo.sphere(w * 0.6, 9, 5), Geo.at(tip + side * (k - 1) * w * 0.5 + d * (0.4 if k == 1 else -0.6) - Vector3(0, w * 0.55, 0), Vector3.ZERO, Vector3(1, 0.55, 1)), LEAF.darkened(0.1)])
		for j in 2:
			_plant("bush", tip + side * (k - 1) * w * 0.5 + d * (0.9 - j * 1.2 if k == 1 else -0.2 - j * 0.8) - Vector3(0, w * 0.5 + j * 0.6, 0), 2.0)


func _ramp(a: Vector3, b: Vector3, w: float) -> void:
	## Grande branche en pente de a à b (dessus), large de w.
	var d := b - a
	var bs := Basis.looking_at(d.normalized())
	_box(Vector3(w, 1.2, d.length() + 0.4), Transform3D(bs, (a + b) * 0.5 - bs.y * 0.6))
	parts.append([Geo.cyl(w * 0.52, w * 0.6, d.length() + 1.0, 10), Transform3D(Basis(bs.x, -bs.z, bs.y * 0.6), (a + b) * 0.5 - bs.y * w * 0.33), BARK.lightened(0.06)])
	parts.append([Geo.box(Vector3(w * 0.74, 0.14, d.length())), Transform3D(bs, (a + b) * 0.5 - bs.y * 0.05), MOSS])
	_limb(b + d.normalized() * 0.5 - Vector3(0, 1.0, 0), Vector3(C3.x, b.y + 1.5, C3.y), w * 0.5, w * 0.6, BARK.lightened(0.06))


func _pad(c: Vector3, r: float, stem: bool) -> void:
	## Cime ronde où se poser : un coussin de feuillage, dessus de mousse claire ; « stem » : son tronc dans la brume.
	_cyl_col(r, 1.2, c - Vector3(0, 0.6, 0))
	parts.append([Geo.sphere(r * 1.12, 14, 7), Geo.at(c - Vector3(0, r * 0.36, 0), Vector3.ZERO, Vector3(1, 0.36, 1)), LEAF.darkened(0.05)])
	parts.append([Geo.cyl(r * 0.84, r * 0.95, 0.12, 16), Geo.at(c - Vector3(0, 0.03, 0)), Color(0.26, 0.4, 0.16)])
	for k in 7:
		var a := k * 51.0 + r * 40.0
		parts.append([Geo.sphere(r * 0.5, 8, 5), Geo.at(pol(Vector2(c.x, c.z), a, r * 0.9, c.y - r * 0.6), Vector3.ZERO, Vector3(1, 0.6, 1)), LEAF.darkened(0.1)])
	for k in int(r * 6.0):   # (les buissons ne s'agrandissent pas au-delà de ×2 : leurs feuilles peintes gardent leur taille)
		_plant("bush", pol(Vector2(c.x, c.z), k * 360.0 / int(r * 6.0), r * (0.92 + 0.1 * (k % 2)), c.y - 1.5 - 0.5 * (k % 3)), _rng.randf_range(1.6, 2.1))
	_isles.append([c, r * 0.8, r * 0.8])
	if stem:
		_trunks.append([Vector2(c.x, c.z), maxf(r * 0.3, 1.0), -10.0, c.y - 1.0, BARK])
		for k in int(r * r * 0.5):
			var a := _rng.randf() * TAU
			_flower(c + Vector3(cos(a), 0, sin(a)) * r * 0.7 * sqrt(_rng.randf()))


func _sakura(at: Vector3, s: float) -> void:
	_plant("sakura%d" % (_rng.randi() % 3), at, s * 1.25)
	_cyl_col(0.45 * s, 4.0, at + Vector3(0, 2.0, 0))
	add_child(Fx.petals(at + Vector3(0, 5.0 * s, 0), Vector3(3, 1, 3), 24))


func _shimenawa(c: Vector3, r: float) -> void:
	## Corde sacrée rouge et blanche autour d'un tronc, comme le collier de Titou, et ses bandes de papier.
	for k in 90:
		var a := k * 4.0
		parts.append([Geo.sphere(0.2, 6, 4), Geo.at(pol(Vector2(c.x, c.z), a, r, c.y + 0.3 * sin(deg_to_rad(a) * 5.0)), Vector3.ZERO, Vector3(1.5, 1, 1.5)), Color(0.8, 0.2, 0.17) if (k / 2) % 2 == 0 else SHIDE])
		if k % 9 == 0:
			parts.append([Geo.box(Vector3(0.3, 0.9, 0.02)), Geo.at(pol(Vector2(c.x, c.z), a, r + 0.3, c.y - 0.7), Vector3(0, -deg_to_rad(a) + PI * 0.5, 0)), SHIDE])


func _thorn_arc(into: Array, c: Vector3, r: float, y: float, a0: float, thick: float) -> void:
	## Un tour de ronce autour de c : tige sombre qui ondule, hérissée d'épines.
	var prev := Vector3.ZERO
	for k in 25:
		var a := a0 + TAU * k / 24.0
		var p := c + Vector3(cos(a) * r, y + 0.35 * sin(a * 3.0 + a0), sin(a) * r)
		if k > 0:
			var d := (p - prev).normalized()
			into.append([Geo.cyl(thick, thick, prev.distance_to(p) + thick, 6), Transform3D(Basis(Quaternion(Vector3.UP, d)), (prev + p) * 0.5), THORN])
			var out := Vector3(cos(a), 0.5 * sin(k * 2.3), sin(a)).normalized() * (1.0 if k % 2 == 0 else -1.0)
			into.append([Geo.cyl(0.0, thick * 0.7, thick * 3.6, 4), Transform3D(Basis(Quaternion(Vector3.UP, out)), p + out * thick * 1.9), THORN.lightened(0.12)])
		prev = p


func _wisteria(r: float, n: int) -> Array:
	## Grappes de glycine qui pendent en couronne (rayon r) : des perles lilas de plus en plus petites.
	var out := [[Geo.sphere(0.6, 8, 5), Geo.at(Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1.6, 0.5, 1.6)), MOSS_LIGHT]]
	for k in n:
		var a := TAU * k / n
		var base := Vector3(cos(a) * r * 0.5, 2.6, sin(a) * r * 0.5)
		out.append([Geo.cyl(0.05, 0.07, 2.6, 5), Geo.at(base * Vector3(0.5, 0.5, 0.5)), Color(0.42, 0.34, 0.22)])
		for j in 6:
			out.append([Geo.sphere(0.3 - j * 0.035, 6, 4), Geo.at(base + Vector3(cos(a) * r * 0.5, -0.3 - j * 0.34, sin(a) * r * 0.5)), LILAC.lightened(0.06 * (j % 2)).lerp(Color(0.9, 0.8, 0.98), j / 8.0)])
	return out


func _mesh_of(p: Array) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.merge(p)
	mi.material_override = Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.25, detail = 0.0})
	return mi


func _nut_mesh() -> ArrayMesh:
	## Bogue de châtaigne : une boule vert-jaune hérissée de piquants.
	var p := [[Geo.sphere(NUT_R * 0.82, 12, 8), Transform3D(), Color(0.56, 0.62, 0.26)]]
	for k in 34:
		var d := Vector3(cos(k * 2.4) * sin(k * 0.19 + 0.2), cos(k * 0.19 + 0.2), sin(k * 2.4) * sin(k * 0.19 + 0.2)).normalized()
		p.append([Geo.cyl(0.0, 0.12, 0.42, 4), Transform3D(Basis(Quaternion(Vector3.UP, d)) if d.y > -0.99 else Basis(Vector3.RIGHT, PI), d * NUT_R * 0.92), Color(0.7, 0.72, 0.34)])
	return Geo.merge(p)


func _far_trees() -> void:
	## La futaie autour du parcours : des cèdres géants jusque dans la brume (décor seul).
	var n := 0
	while n < 54:
		var p := Vector2(_rng.randf_range(-150.0, 330.0), _rng.randf_range(-250.0, 110.0))
		var ok := true
		for r in route:
			if Vector2(r.x - p.x, r.z - p.y).length() < 24.0:
				ok = false
		for t: Array in _trunks:
			if (t[0] as Vector2).distance_to(p) < 22.0:
				ok = false
		if Vector2(p.x - 36.0, p.y + 30.0).length() < 26.0 or Vector2(p.x - SUMMIT.x, p.y - SUMMIT.z).length() < 34.0 or not ok:
			continue
		n += 1
		var h := _rng.randf_range(70.0, 118.0)
		var r := _rng.randf_range(3.0, 5.0)
		_trunks.append([p, r, -10.0, h, BARK.darkened(_rng.randf() * 0.15)])
		_crowns.append([Vector3(p.x, h - 24.0, p.y), r * 3.6, 46.0 + _rng.randf() * 10.0])


func _finish() -> void:
	## Le sol, le décor fusionné, les troncs, les couronnes, les fougères, les fleurs, la brume, les rais de lumière.
	_gst.generate_normals()
	var gmi := MeshInstance3D.new()
	gmi.mesh = _gst.commit()
	gmi.material_override = Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.12})
	add_child(gmi)
	var gcs := CollisionShape3D.new()
	var gsh := ConcavePolygonShape3D.new()
	gsh.set_faces(_gfaces)
	gsh.backface_collision = true
	gcs.shape = gsh
	_sb.add_child(gcs)
	var mi := MeshInstance3D.new()
	mi.mesh = Geo.merge(parts)
	mi.material_override = Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.15})
	add_child(mi)
	# troncs : un cylindre cannelé aux fibres verticales, étiré et teinté par arbre
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEG := 36
	const ROWS := 10
	for j in ROWS:
		for s in SEG:
			for cnr: Array in [[0, 0], [0, 1], [1, 1], [0, 0], [1, 1], [1, 0]]:
				var a := TAU * (s + int(cnr[0])) / SEG
				var y := float(j + int(cnr[1])) / ROWS
				var rib := sin(a * 9.0 + 2.0 * sin(y * 5.0))   # cannelures qui serpentent un peu en montant
				var rr := 1.03 + 0.06 * rib + 0.025 * sin(a * 17.0 + 1.3)
				var tone := 0.74 + 0.22 * rib + 0.08 * sin(a * 23.0 + y * 31.0)
				var moss := clampf(1.0 - y * 4.0 + 0.6 * sin(a * 3.0 + y * 12.0), 0.0, 1.0) * 0.55   # mousse au pied, par plaques
				st.set_color(Color(tone, tone * 0.97, tone * 0.94).lerp(Color(0.5, 0.95, 0.42), moss))
				st.add_vertex(Vector3(cos(a) * rr, y, sin(a) * rr))
	st.generate_normals()
	var tm := MultiMesh.new()
	tm.transform_format = MultiMesh.TRANSFORM_3D
	tm.use_colors = true
	tm.mesh = st.commit()
	tm.instance_count = _trunks.size()
	for i in _trunks.size():
		var t: Array = _trunks[i]
		var c: Vector2 = t[0]
		var r: float = t[1]
		var y0: float = t[2]
		tm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(r, float(t[3]) - y0, r)), Vector3(c.x, y0, c.y)))
		tm.set_instance_color(i, (t[4] as Color).srgb_to_linear())
	_mm(tm, Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.2}))
	# couronnes : le sapin peint de la carte (Nature, « pine »), agrandi en cèdre géant, son fût caché dans le nôtre
	var nature: Nature = world.get_node("Nature")
	# (ses cartes d'aiguilles ne grandissent pas avec lui : dessous, une masse sombre de jupes de cône tient la silhouette)
	var pine_box := Geo.arrays_aabb(Geo.glb("momi_1"))
	var cp := []
	for k in 22:   # des masses rondes qui montent en spirale et se resserrent : un nuage de feuillage, pas un cône
		var u := k / 21.0
		var rr := (1.0 - u * 0.8) * 0.62
		var a := k * 2.4
		cp.append([Geo.sphere(1.0, 12, 7), Geo.at(Vector3(cos(a) * rr * 0.75, 0.08 + u * 0.88, sin(a) * rr * 0.75), Vector3.ZERO, Vector3(rr * 0.85, 0.1 + 0.03 * sin(k * 1.7), rr * 0.85)),
			Color(0.1, 0.21, 0.12).lerp(Color(0.24, 0.4, 0.18), u * 0.8 + 0.2 * sin(k * 2.1))])
	var cm := MultiMesh.new()
	cm.transform_format = MultiMesh.TRANSFORM_3D
	cm.mesh = Geo.merge(cp)
	cm.instance_count = _crowns.size()
	for i in _crowns.size():
		var cr: Array = _crowns[i]
		var foot: Vector3 = cr[0]
		var h: float = cr[2]
		var s := h / pine_box.size.y
		_plants.append(["pine", Geo.at(ORIGIN + foot, Vector3(0, _rng.randf() * TAU, 0), Vector3.ONE * s)])
		cm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.3).scaled(Vector3(pine_box.size.x * s * 0.56, h * 0.95, pine_box.size.x * s * 0.56)), foot))
	_mm(cm, Mats.toon(Color.WHITE, {vertex_color = true, rim = 0.2, detail = 0.0}))
	var green := nature.plant(_plants)
	green.reparent(self)
	for k in 3:
		var fr := nature.plant(_blooms[k])
		fr.reparent(self)
		fr.visible = false
		_flower_roots.append(fr)
	# l'herbe des îlots : les brins des prés de la carte
	for isl: Array in _isles:
		var c: Vector3 = isl[0]
		var rx: float = isl[1]
		var rz: float = isl[2]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = nature.grass_mesh()
		mm.instance_count = int(rx * rz * PI * 2.6)
		for i in mm.instance_count:
			var a := _rng.randf() * TAU
			var d := sqrt(_rng.randf()) * 0.97
			var sc := _rng.randf_range(0.85, 1.25)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(sc, sc * _rng.randf_range(0.8, 1.4), sc)), Vector3(cos(a) * rx * d, -0.03, sin(a) * rz * d)))
			mm.set_instance_color(i, Color(0.24, 0.4, 0.12) * _rng.randf_range(0.85, 1.15))
		var gi := MultiMeshInstance3D.new()
		gi.multimesh = mm
		gi.position = c
		gi.material_override = nature.grass_material()
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gi.visibility_range_end = 120.0
		gi.layers = Nature.GRASS_LAYER
		add_child(gi)
	# la mer de brume, et sous elle un fond clair : on ne voit jamais le vide
	var floor_ := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(2400, 2400)
	floor_.mesh = fp
	floor_.position = Vector3(90, -1.5, -60)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.7, 0.82, 0.7)
	floor_.material_override = fm
	add_child(floor_)
	for at: Vector3 in [Vector3(0, 1.5, -16), Vector3(0, 1.5, -40), Vector3(0, 2, -78), Vector3(-10, 2, -104)]:
		add_child(Fx.mist(at, Vector3(14, 1.5, 8), 0.7))
	add_child(Fx.motes(Vector3(0, 10, -30), Vector3(18, 6, 34), 160))
	add_child(Fx.motes(SUMMIT + Vector3(0, 5, 0), Vector3(14, 5, 14), 120))
	# rais de soleil dorés entre les troncs (cônes additifs, shaders/light_pillar.gdshader), penchés comme le soleil
	var ray := CylinderMesh.new()
	ray.top_radius = 0.7
	ray.bottom_radius = 2.2
	ray.height = 1.0
	ray.radial_segments = 14
	ray.cap_top = false
	ray.cap_bottom = false
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	rmat.disable_fog = true
	rmat.albedo_color = Color(1.0, 0.86, 0.5, 0.035)
	var grad := GradientTexture2D.new()   # (les flancs d'un CylinderMesh occupent la moitié haute de la texture)
	grad.gradient = Gradient.new()
	grad.gradient.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	grad.gradient.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	grad.fill_from = Vector2(0.5, 0.0)
	grad.fill_to = Vector2(0.5, 0.5)
	rmat.albedo_texture = grad
	rmat.proximity_fade_enabled = true
	rmat.proximity_fade_distance = 4.0
	var rm := MultiMesh.new()
	rm.transform_format = MultiMesh.TRANSFORM_3D
	rm.mesh = ray
	var feet := [Vector3(-7, 4, -6), Vector3(8, 4, -24), Vector3(-5, 2, -42), Vector3(6, 5, -58), Vector3(-3, 6, -78), Vector3(9, 10, -92),
		Vector3(-16, 16, -100), Vector3(-10, 26, -116), Vector3(8, 40, -118), Vector3(14, 60, -100), Vector3(34, 66, -96), Vector3(50, 74, -98),
		Vector3(70, 82, -72), Vector3(100, 88, -52), Vector3(134, 94, -40), Vector3(160, 100, -42), SUMMIT + Vector3(6, -4, 4), SUMMIT + Vector3(-7, -4, -6)]
	rm.instance_count = feet.size()
	var lean := Vector3(-0.42, 1.0, 0.3).normalized()   # vers le soleil de l'après-midi
	for i in feet.size():
		var len_ := 46.0 + 9.0 * (i % 4)
		rm.set_instance_transform(i, Transform3D(Basis(Quaternion(Vector3.UP, lean)) * Basis.from_scale(Vector3(1.0 + 0.25 * (i % 3), len_, 1.0 + 0.25 * (i % 3))), (feet[i] as Vector3) + lean * len_ * 0.5))
	var rmi := _mm(rm, rmat)
	rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _mm(mm: MultiMesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-400, -40, -400), Vector3(900, 240, 700))
	add_child(mmi)
	return mmi


func _shrine() -> void:
	## Sur l'île de la Forêt de l'archipel : un petit torii, un autel de pierre et deux lanternes, face au lagon.
	var arch: Archipelago = world.archipelago
	var k := 0
	for i in Archipelago.ISLES.size():
		if Archipelago.ISLES[i].id == "foret":
			k = i
	var ic := Archipelago.isle_center(k)
	var to_c := (Archipelago.C - ic).normalized()
	var at := ic
	var best := INF
	var rr := float(Archipelago.ISLES[k].r)
	for ai in range(-5, 6):   # le replat le plus plat de la grève qui regarde le lagon : au sec à marée haute, sous la ligne des arbres
		for di in range(7, 13):
			var q := ic + to_c.rotated(ai * 0.17) * rr * di * 0.1
			var h := arch.height_at(q.x, q.y)
			var bump := 0.0
			for o: Vector2 in [Vector2(3.5, 0), Vector2(-3.5, 0), Vector2(0, 3.5), Vector2(0, -3.5)]:
				bump = maxf(bump, absf(arch.height_at(q.x + o.x, q.y + o.y) - h))
			if h > 1.3 and h < 2.4 and bump + absf(ai) * 0.02 < best:
				best = bump + absf(ai) * 0.02
				at = q
	var dir := (Archipelago.C - at).normalized()
	var y := arch.height_at(at.x, at.y)
	var yaw := atan2(dir.x, dir.y)   # l'autel regarde le lagon
	var n := StaticBody3D.new()
	n.name = "AutelForet"
	n.position = Vector3(at.x, y, at.y)
	n.rotation.y = yaw
	var stone := Color(0.62, 0.6, 0.55)
	var sp := [
		[Geo.box(Vector3(3.4, 0.5, 2.4)), Geo.at(Vector3(0, 0.05, 0)), stone],
		[Geo.box(Vector3(1.8, 0.9, 1.1)), Geo.at(Vector3(0, 0.7, 0)), stone.lightened(0.08)],
		[Geo.box(Vector3(2.1, 0.16, 1.4)), Geo.at(Vector3(0, 1.2, 0)), stone.darkened(0.1)],
		[Geo.glb("torii_3"), Geo.at(Vector3(0, -0.2, 3.2), Vector3.ZERO, Vector3.ONE * 1.5), Geo.OWN],
		[Geo.glb("toro"), Geo.at(Vector3(2.6, -0.1, 0.4), Vector3.ZERO, Vector3.ONE * 0.8), Geo.OWN],
		[Geo.glb("toro"), Geo.at(Vector3(-2.6, -0.1, 0.4), Vector3.ZERO, Vector3.ONE * 0.8), Geo.OWN],
		[Geo.sphere(0.2, 8, 6), Geo.at(Vector3(0, 1.48, 0)), Color(0.95, 0.78, 0.25)],   # un grelot doré posé en offrande
	]
	for j in 9:   # la corde rouge et blanche de l'autel
		sp.append([Geo.sphere(0.13, 6, 4), Geo.at(Vector3(-0.8 + j * 0.2, 1.05 - 0.12 * sin(j * PI / 8.0), 0.57)), Color(0.8, 0.2, 0.17) if j % 2 == 0 else SHIDE])
	n.add_child(_mesh_of(sp))
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.8, 1.6, 1.1)
	cs.shape = sh
	cs.position.y = 0.6
	n.add_child(cs)
	world.add_child(n)
	_portal = n.position + Vector3(0, 1.0, 0)
	var back := at + dir * 3.2
	_arrival = Vector3(back.x, arch.height_at(back.x, back.y) + 0.5, back.y)


# ---------------------------------------------------------------- entrer, reprendre, sortir

func _place(p: Player, k: int) -> void:
	## Ici on ne pose pas le joueur : on pose Titou à la lanterne, et le joueur dessus.
	var l: Dictionary = lanterns[k]
	var yaw: float = l.yaw
	var t: Titou = world.titou
	p.fall_y = global_position.y + 0.3
	t.teleport(to_global(l.p) + Vector3(0, 0.3, 0), yaw)
	t.mount(p)
	p.yaw = yaw
	p.pitch = -0.3


func _cat_fell() -> void:
	if not inside:
		return
	var t: Titou = world.titou
	Sfx.play("plop", t.global_position, -2.0)
	var l: Dictionary = lanterns[reached]
	t.teleport(to_global(l.p) + Vector3(0, 0.3, 0), l.yaw)
	for p: Player in t.riders:
		p.yaw = l.yaw


func _on_enter() -> void:
	_saved_env = {fog = world.env.fog_density, fog_h = world.env.fog_height, fog_hd = world.env.fog_height_density,
		cloud = world.sky_mat.get_shader_parameter("cloud_cover"), vol = world.env.volumetric_fog_density}
	world.env.volumetric_fog_density = 0.008
	world.env.fog_height = ORIGIN.y + 2.0
	world.env.fog_height_density = 0.045
	var t: Titou = world.titou
	t.locked = true
	t.fall_y = ORIGIN.y + 0.3
	t.visible = true
	if not t.fell.is_connected(_cat_fell):
		t.fell.connect(_cat_fell)
	if freed and wake_t < 0.0:   # libéré lors d'une partie précédente : tout est déjà en fleurs
		for k: Dictionary in knots:
			_clear_knot(k)
		_awake(1.0)
	elif not freed:
		Sfx.prepare("rise")


func _on_leave() -> void:
	world.env.fog_density = _saved_env.fog
	world.env.fog_height = _saved_env.fog_h
	world.env.fog_height_density = _saved_env.fog_hd
	world.env.volumetric_fog_density = _saved_env.vol
	world.sky_mat.set_shader_parameter("cloud_cover", _saved_env.cloud)
	(world.titou as Titou).go_home()
	if freed:
		world.hud.notify("Titou est rentré dans son grand panier, sous le camphrier géant. Va le voir : [E] pour monter.")


func sky() -> void:
	var k := bloom
	var top := Color(0.4, 0.58, 0.56).lerp(Color(0.36, 0.6, 0.88), k)
	var hor := Color(0.86, 0.88, 0.7).lerp(Color(1.0, 0.9, 0.7), k)
	var sun := Color(1.0, 0.9, 0.68).lerp(Color(1.0, 0.93, 0.76), k)
	world.sky_mat.set_shader_parameter("top_color", top)
	world.sky_mat.set_shader_parameter("horizon_color", hor)
	world.sky_mat.set_shader_parameter("sun_color", sun)
	world.sky_mat.set_shader_parameter("cloud_cover", lerpf(0.6, 0.3, k))
	world.sun.light_color = sun
	world.sun.light_energy = lerpf(1.05, 1.4, k)
	world.env.ambient_light_energy = lerpf(0.95, 1.05, k)
	world.env.fog_light_color = Color(0.62, 0.76, 0.6).lerp(Color(0.95, 0.88, 0.7), k)
	world.env.fog_density = lerpf(0.0017, 0.0011, k)


# ---------------------------------------------------------------- les nœuds d'épines, le réveil

func interaction(pos: Vector3) -> Dictionary:
	if inside and wake_t < 0.0 and not freed:
		var lp := to_local(pos)
		var n := knots.filter(func(x: Dictionary) -> bool: return x.done).size()
		for k: Dictionary in knots:
			if not k.done and lp.distance_to(k.p) < 4.2:
				return {text = "[E] Faire tinter le grelot de Titou (%d/3)" % (n + 1), interact = _ring.bind(k)}
	return super(pos)


func _clear_knot(k: Dictionary) -> void:
	k.done = true
	(k.thorns as Node3D).visible = false
	(k.bloom as Node3D).visible = true


func _ring(k: Dictionary) -> void:
	if k.done:
		return
	for i in 3:
		get_tree().create_timer(i * 0.16).timeout.connect(func() -> void: Sfx.play("grelot", Vector3.INF, -2.0, 0.02))
	Sfx.play("shimmer", Vector3.INF, -10.0)
	var th: Node3D = k.thorns
	var bl: Node3D = k.bloom
	k.done = true
	bl.visible = true
	bl.scale = Vector3.ONE * 0.05
	var tw := create_tween()
	tw.tween_property(th, "scale", Vector3.ONE * 0.02, 0.7).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(bl, "scale", Vector3.ONE, 0.9).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: th.visible = false)
	add_child(Fx.burst((k.p as Vector3) + Vector3(0, 1, 0), 1.2, 40, LILAC))
	var left := knots.filter(func(x: Dictionary) -> bool: return not x.done).size()
	if left > 0:
		world.hud.notify("Les épines tombent en poussière, la glycine refleurit ! Encore %d nœud%s." % [left, "s" if left > 1 else ""])
		return
	world.hud.notify("Le dernier nœud se défait… l'esprit de la Forêt ouvre les yeux.")
	wake_t = 0.0
	Sfx.play("rise", Vector3.INF, -3.0, 0.0)


func _awake(k: float) -> void:
	## L'état du monde pour un réveil avancé de k (0 : endormi sous les ronces ; 1 : debout, la forêt en fleurs).
	bloom = k
	var up := smoothstep(0.0, 0.35, k)
	spirit.position = SUMMIT + Vector3(0, lerpf(-1.1, 0.0, up) + (0.12 * sin(_t * 1.1) if k >= 1.0 else 0.0), 0)
	spirit.rotation.x = lerpf(0.2, 0.0, up)   # endormi : affaissé, le mufle bas
	spirit.scale = Vector3.ONE * lerpf(1.0, 1.12, smoothstep(0.2, 0.6, k)) * (1.0 + 0.012 * sin(_t * 1.4))
	_coil.scale = Vector3.ONE * maxf(1.0 - smoothstep(0.0, 0.25, k), 0.001)
	_coil.visible = k < 0.25
	if k > 0.2 and is_instance_valid(_coil_body):
		_coil_body.queue_free()
	_glow.light_energy = 5.0 * sin(PI * clampf(k * 1.4, 0.0, 1.0)) + 1.2 * k
	for i in _flower_roots.size():
		_flower_roots[i].visible = k > 0.22 + i * 0.2
	for fx in _petals:
		fx.emitting = k > 0.3


func _physics_process(delta: float) -> void:
	super(delta)
	_t += delta
	var t: Titou = world.titou
	var lp := to_local(t.global_position)
	for h: Dictionary in _hints:
		if lp.distance_to(h.p) < 7.0:
			world.hud.notify(h.text)
			_hints.erase(h)
			break
	# châtaignes : elles tombent du feuillage en haut de la branche, la dévalent, basculent dans le vide au bout
	var a: Vector3 = RAMP[0]
	var b: Vector3 = RAMP[1]
	var down := (a - b).normalized()
	var side := down.cross(Vector3.UP).normalized()
	var run := a.distance_to(b) + 1.0
	for nd: Dictionary in nuts:
		var s := fposmod(_t / NUT_PERIOD + float(nd.phase), 1.0) * NUT_PERIOD * NUT_SPEED   # chemin parcouru
		var node: Node3D = nd.node
		var roll := maxf(s - 5.0, 0.0)
		var p := b + down * roll + side * float(nd.side) + Vector3(0, NUT_R + maxf(5.0 - s, 0.0) * 1.6, 0)   # (d'abord la chute depuis le feuillage)
		var over := roll - run
		if over > 0.0:   # passé le bout, elle tombe
			p.y -= over * over * 0.4
		node.visible = over < 11.0
		node.position = p
		node.rotate(side, -delta * NUT_SPEED / NUT_R)
		if node.visible and (lp + Vector3(0, 1.2, 0)).distance_to(p) < NUT_R + 1.1 and t.state == Titou.RUN:
			t.knock(down * 7.0 + side * signf((lp - p).dot(side) + 0.01) * 7.0 + Vector3(0, 7.0, 0))
	# rameaux : sous Titou ils ploient, craquent, tombent ; ils repoussent un peu plus tard
	for tw: Dictionary in twigs:
		var body: AnimatableBody3D = tw.body
		var tp: Vector3 = tw.p
		var fallen: float = tw.down
		if fallen > 0.0:
			tw.down = fallen - delta
			body.position.y -= delta * 14.0
			if fallen - delta <= 0.0:
				body.position = tp
				body.rotation = Vector3.ZERO
				body.collision_layer = 1
				tw.t = 0.0
			continue
		var on := t.is_on_floor() and Vector2(lp.x - tp.x, lp.z - tp.z).length() < 2.2 and absf(lp.y - tp.y) < 0.6
		var held: float = maxf(0.0, float(tw.t) + (delta if on else -delta * 0.5))
		tw.t = held
		body.position.y = tp.y - 0.5 * smoothstep(0.0, TWIG_HOLD, held)
		body.rotation.z = 0.12 * sin(_t * 30.0) * smoothstep(TWIG_HOLD * 0.5, TWIG_HOLD, held)
		if held >= TWIG_HOLD:
			Sfx.play("snap", to_global(tp), -2.0)
			body.collision_layer = 0
			tw.down = TWIG_BACK
	# courants de pétales : dedans, Titou est porté le long de leur axe
	t.carry = Vector3.ZERO
	if inside and not t.is_on_floor():
		for sd: Array in STREAMS:
			var s0: Vector3 = sd[0]
			var s1: Vector3 = sd[1]
			var ax := (s1 - s0).normalized()
			var u := (lp + Vector3(0, 1.2, 0) - s0).dot(ax)
			var on_axis := s0 + ax * u
			if u > -1.5 and u < s0.distance_to(s1) and (lp + Vector3(0, 1.2, 0)).distance_to(on_axis) < STREAM_R:
				t.carry = ax * STREAM_V + (on_axis - lp - Vector3(0, 1.2, 0)) * 1.5
	# l'esprit
	if wake_t >= 0.0:
		wake_t += delta
		_awake(smoothstep(0.5, 10.0, wake_t))
		if wake_t > 9.0 and not freed:
			freed = true
			world.hud.notify("L'esprit de la Forêt est libre ! Titou est à toi : il t'attendra dans son panier, sous le camphrier géant. Le torii du nid s'est allumé.")
			Sfx.play("catch_rare", Vector3.INF, -2.0)
			Save.write(world)
	elif freed:
		_awake(1.0)
	else:
		_awake(0.0)
