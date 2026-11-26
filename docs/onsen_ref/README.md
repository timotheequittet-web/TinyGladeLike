# Référence Onsen

Sources reprises du projet « L'onsen de la colline » (même auteur), gardées pour
référence et pour régénérer les modèles. Godot ignore ce dossier (`.gdignore`).

- `scripts/` : `blossom.gd` (couronnes en cartes face caméra, porté dans
  `addons/bastide/core/kit/bastide_crown_builder.gd`), `nature.gd`, `forest_world.gd`, `geo.gd`.
- `shaders/` : `blossom.gdshader` (porté en `addons/bastide/shaders/bastide_crown.gdshader`),
  `grass.gdshader`, `toon.gdshader`.
- `tools/blender/japan.py` + `lib.py` : génération des arbres et plantes dans Blender
  (`blender -b --python japan.py -- [noms]`). `tools/foliage_key.gd` : détourage des touffes peintes.

Les modèles (`.glb`, couleurs par sommet) sont dans `addons/bastide/kit/nature/models/`, les touffes
peintes dans `addons/bastide/kit/nature/foliage/`. Provenance : modèles générés par les scripts Blender
de l'auteur ; touffes peintes générées avec Gemini puis détourées (pas de licence écrite).
