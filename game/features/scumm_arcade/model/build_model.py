"""Build the arcade's static mesh with Blender (no game/runtime dependency).
Run: blender --background --python model/build_model.py
"""
import math
from pathlib import Path
import bpy

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metal=0, rough=.4, glow=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metal
    p.inputs['Roughness'].default_value = rough
    p.inputs['Emission Color'].default_value = (*color, 1)
    p.inputs['Emission Strength'].default_value = glow
    return m

navy = material('Midnight enamel', (.035, .075, .105), glow=.12)
teal = material('Petrol blue side panels', (.055, .25, .29), glow=.15)
brass = material('Satin brass', (.72, .47, .22), .35, .28, .12)
black = material('Graphite rubber', (.012, .016, .020), 0, .65)
steel = material('Coin door steel', (.045, .06, .07), .65)
red = material('Coral buttons', (.65, .075, .035), .12, .25)
cream = material('Ivory buttons', (.8, .67, .40), .1, .3)
glow = material('Warm marquee light', (.7, .40, .13), .1, .4, .5)

def finish(o, name, mat, bevel=0):
    o.name = name
    o.data.materials.append(mat)
    if bevel:
        mod = o.modifiers.new('Soft manufactured edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        o.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return o

def box(name, pos, size, mat, bevel=.015, angle=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
    o = bpy.context.object
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.rotation_euler.x = angle
    return finish(o, name, mat, bevel)

def cylinder(name, pos, radius, depth, mat, axis='y'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=radius, depth=depth, location=pos)
    o = bpy.context.object
    if axis == 'y': o.rotation_euler.x = math.pi / 2
    if axis == 'x': o.rotation_euler.y = math.pi / 2
    for poly in o.data.polygons: poly.use_smooth = True
    return finish(o, name, mat, .004)

def prism(name, x, width, profile, mat, bevel=.015):
    n = len(profile)
    vertices = [(x + dx, y, z) for dx in [-width / 2, width / 2] for z, y in profile]
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return finish(o, name, mat, bevel)

profile = [(-.49,.10),(.43,.10),(.45,.85),(.88,1.12),(.88,1.27),
           (.49,1.33),(.28,2.07),(.54,2.22),(.54,2.62),(-.49,2.62)]
box('Recessed plinth', (0,.07,0), (1.43,.14,1.02), black, .035)
prism('Cabinet shell', 0, 1.40, profile, navy, .026)
for side in [-1,1]:
    prism('Brass edge band', side*.716, .036, profile, brass, .016)
    prism('Enamel side cheek', side*.744, .035, profile, teal, .02)
    # Nautical compass medallion with inset diamonds and radial points.
    cylinder('Compass rim', (side*.769,1.62,-.035), .285,.012,brass,'x')
    cylinder('Compass face', (side*.779,1.62,-.035), .257,.012,navy,'x')
    for i in range(8):
        a = i*math.pi/4
        r = .22 if i%2 == 0 else .15
        pts = [(-.035,1.62),(-.035+math.sin(a-.23)*.075,1.62+math.cos(a-.23)*.075),
               (-.035+math.sin(a)*r,1.62+math.cos(a)*r),
               (-.035+math.sin(a+.23)*.075,1.62+math.cos(a+.23)*.075)]
        prism('Compass point', side*.789,.008,pts,cream if i%2 == 0 else brass,.001)
    cylinder('Compass hub',(side*.795,1.62,-.035),.027,.012,brass,'x')
    for y in [.45,.53,.61]:
        box('Side ventilation', (side*.766,y,-.20),(.01,.024,.32),black,.008)
# Upper illuminated sign is inset into brass frame.
box('Marquee surround',(0,2.40,.546),(1.37,.34,.075),brass,.025)
box('Marquee glass',(0,2.40,.588),(1.29,.267,.018),navy,.016)
for x in [-.616,.616]:
    box('Marquee light strip',(x,2.40,.601),(.013,.22,.009),glow,.004)
# Screen plane uses same angle and center as the dynamic Godot QuadMesh.
a = math.radians(-16)
box('CRT bezel',(0,1.756,.426),(1.34,.98,.10),black,.048,a)
box('Inner brass screen lip',(0,1.756,.478),(1.235,.918,.009),brass,.012,a)
# The quad overlays the lip's interior while leaving a narrow border visible.
box('Control deck brass edge',(0,1.264,.67),(1.40,.075,.50),brass,.027)
box('Control deck enamel',(0,1.307,.67),(1.35,.04,.47),navy,.021)
for x in [-.60,.60]:
    for z in [.48,.84]: cylinder('Deck screw',(x,1.332,z),.012,.006,steel)
for x,z,mat in [(.20,.78,cream),(.40,.72,red)]:
    cylinder('Button bezel',(x,1.337,z),.075,.022,black)
    cylinder('Pushbutton',(x,1.358,z),.059,.034,mat)
# Speaker grille above the coin door.
for x in [-.43,.43]:
    for i in range(5): box('Speaker slot',(x,.98+i*.031,.671+i*.049),(.22,.012,.012),black,.005)
box('Coin door frame',(0,.47,.462),(.50,.58,.04),black,.022)
box('Coin door',(0,.47,.487),(.44,.52,.024),steel,.014)
box('Coin slot surround',(-.09,.60,.506),(.14,.17,.021),brass,.01)
box('Coin slot',(-.09,.625,.519),(.075,.016,.008),black,.002)
box('Coin return',(-.09,.55,.519),(.07,.036,.018),black,.006)
cylinder('Coin door lock',(.14,.47,.507),.026,.016,brass,'z')
box('Kick plate',(0,.18,.45),(1.28,.13,.03),steel,.014)
# Bake bevels and batch disconnected pieces by material: eight draws per cabinet.
for mat in list(bpy.data.materials):
    objects = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.active_material == mat]
    if not objects:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.join()
    bpy.context.object.name = mat.name
# Model coordinates already use Godot/glTF Y-up, so no axis conversion on export.
out = Path(__file__).resolve().parent / 'cabinet.glb'
bpy.ops.export_scene.gltf(filepath=str(out), export_format='GLB', export_yup=False, export_apply=True)
print(f'Wrote {out}')
