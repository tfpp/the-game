# Original human avatar assets

The human is one connected, weighted mesh with one surface, 1,465 source vertices
and 2,926 triangles. A 45-bone skeleton deforms the vertices for locomotion and
item grips. Each hand has a palm, thumb and four separate fingers, with three
weighted phalanges per digit (30 finger bones total). Open, relaxed and gripping
poses deform those vertices; palms orient to item grip markers. Five blend shapes sculpt the same topology for feminine proportions,
long, swept or cropped hair, and tactical clothing. There are no separate human
body-part meshes. The GLB importer may duplicate vertices at UV seams.

The editable source is `source/human.blend`; select the Human mesh in Blender to
edit vertices, weights or shape keys. Runtime uses `models/human.glb`.
`source/.gdignore` keeps Blender authoring files out of Godot imports and exports.

Regenerate the original mesh and textures from the checked-in authoring scripts:

```sh
blender --background --python game/assets/player_models/source/build_skinned_human.py
python3 game/assets/player_models/source/paint_textures.py
```

The texture script requires Pillow. Seven tintable 128×128 painted textures use
nearest filtering with mipmaps. UV2 carries rest positions so shirt and trouser
boundaries remain stable while vertices animate. Vertex colors identify face,
hair and limb regions. A single shader applies skin, clothing, hair and eye colors.

Casual uses inventory clothing. Tactical reshapes the chest and boots and paints
vest and gear detail over olive fatigues; equipped clothing colors still apply.
Mesh resources are shared between avatars, with per-instance shape weights and
material parameters. All artwork is original, inspired by late-1990s PC shooters;
no Counter-Strike model, texture or other external game asset is included.

First-person hands reuse the same mesh and skeleton, masking out non-arm surfaces.
They share skin and clothing tints with the world model. Finger geometry remains
connected to the palms and wrists, including across exported UV seams. Run
`tests/features/player_models/hand_probe.tscn` for an open/curled hand close-up;
pass `-- --first-person-hands` to inspect the same hands holding a shotgun.
