extends SceneTree
## Détoure une touffe peinte (Gemini, fond vert ou magenta pur) en texture de cartes pour Blossom.
## godot --headless --path . --script res://tools/foliage_key.gd -- source.jpg sortie.png [quadrant 0-3 | -1 = image entière] [gris] [feuilles] [rect=x,y,l,h]
## Le fond est reconnu à la couleur du coin. La touffe est recadrée au carré autour de ce qui reste.
## gris : la peinture passe en valeurs, ramenées autour de GREY_MEAN (le modèle Blender la recolore par ses
## couleurs de sommets sans l'assombrir).

const SIZE := 256
const MARGIN := 0.04      # marge autour de la touffe recadrée (part de la taille)
const GREY_MEAN := 0.82   # valeur moyenne d'une touffe en gris


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	var quad := int(a[2]) if a.size() > 2 else -1
	var grey := "gris" in a
	var leaves := "feuilles" in a   # feuillage tout vert sur magenta : détourage plus sévère des bords
	for arg: String in a:   # rect=x,y,l,h : ne garder que cette zone (capture d'écran avec l'interface autour)
		if arg.begins_with("rect="):
			var v := arg.trim_prefix("rect=").split_floats(",")
			src = src.get_region(Rect2i(int(v[0]), int(v[1]), int(v[2]), int(v[3])))
	if quad >= 0:   # planche 2 × 2 : une touffe par quart
		var hw := src.get_width() / 2
		var hh := src.get_height() / 2
		src = src.get_region(Rect2i((quad % 2) * hw, (quad / 2) * hh, hw, hh))
	src.convert(Image.FORMAT_RGBA8)
	var corner := src.get_pixel(2, 2)
	var magenta := corner.r > 0.6 and corner.b > 0.6 and corner.g < 0.4
	var box := Rect2i()
	var lum_sum := 0.0
	var lum_n := 0
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			# écart à la couleur du fond : le vert (ou le rouge et le bleu ensemble) dépasse nettement le reste
			# fond magenta : les touffes posées dessus sont vertes, sans bleu au-dessus du vert ; un bleu qui dépasse le vert
			# est du fond, même mêlé au bord d'une foliole (plus sévère que le seul écart au rouge et au bleu)
			# (mode « feuilles » seulement : une touffe à fleurs bleues garde la règle simple)
			var spill := (c.b - c.g) if magenta and leaves else ((minf(c.r, c.b) - c.g) if magenta else (c.g - maxf(c.r, c.b)))
			var alpha := 1.0 - (smoothstep(0.04, 0.22, spill) if magenta and leaves else smoothstep(0.12, 0.35, spill))
			# bords et tiges fines : on soustrait exactement la part de fond mêlée au pixel
			var mix := maxf(spill, 0.0)
			if magenta:
				c.r -= mix
				c.b -= mix
				if leaves:   # bord rosé d'une foliole : le rouge ne dépasse pas le vert
					c.r = minf(c.r, c.g + 0.08)
			else:
				c.g -= mix
			if grey:
				var l := c.get_luminance()
				c = Color(l, l, l)
				if alpha > 0.5:
					lum_sum += l
					lum_n += 1
			c.a = alpha
			src.set_pixel(x, y, c)
			if alpha > 0.5:
				box = Rect2i(x, y, 1, 1) if box.size == Vector2i.ZERO else box.expand(Vector2i(x, y))
	if grey and lum_n > 0:
		var k := GREY_MEAN / (lum_sum / lum_n)
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				var l := minf(c.r * k, 1.0)
				src.set_pixel(x, y, Color(l, l, l, c.a))
	# pixels transparents : la couleur moyenne de la touffe, sinon le fond déteint sur les bords à la réduction
	var avg := Color(0, 0, 0)
	var n := 0
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a > 0.9:
				avg += Color(c.r, c.g, c.b)
				n += 1
	avg = avg / float(maxi(n, 1))
	for y in src.get_height():
		for x in src.get_width():
			var c := src.get_pixel(x, y)
			if c.a < 0.5:
				src.set_pixel(x, y, Color(avg.r, avg.g, avg.b, c.a))
	# carré centré sur la touffe, avec un peu de marge (et dans l'image)
	var side := int(maxi(box.size.x, box.size.y) * (1.0 + MARGIN * 2.0))
	var c0 := box.get_center() - Vector2i(side, side) / 2
	var sq := Image.create(side, side, false, Image.FORMAT_RGBA8)
	sq.fill(Color(avg.r, avg.g, avg.b, 0))
	sq.blit_rect(src, Rect2i(c0, Vector2i(side, side)).intersection(Rect2i(Vector2i.ZERO, src.get_size())), Vector2i(maxi(0, -c0.x), maxi(0, -c0.y)))
	sq.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	sq.save_png(a[1])
	print("keyed ", a[1], " box ", box, " magenta " if magenta else " vert ")
	quit()
