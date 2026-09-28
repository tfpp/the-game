"""Rebuild original casino meshes: Blender --background --python build_models.py.
Units and helper coordinates match Godot (Y up, front +Z). No third-party assets.
"""
import math
from pathlib import Path
import bpy
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1] / 'models'
OUT.mkdir(exist_ok=True)

def material(name, color, metal=0, rough=.5):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    return mat

MATS = {
    'Walnut': material('Walnut', (.15, .065, .025), 0, .34),
    'Brass': material('Brass', (.62, .39, .12), .8, .28),
    'Chrome': material('Chrome', (.62, .68, .7), .95, .22),
    'Enamel': material('Enamel', (.018, .075, .07), .25, .3),
    'Velvet': material('Velvet', (.28, .025, .045), 0, .78),
    'Ivory': material('Ivory', (.87, .77, .54), 0, .42),
    'Dark': material('Dark', (.009, .013, .014), .1, .45),
    'Leaf': material('Leaf', (.035, .14, .055), 0, .7),
    'Soil': material('Soil', (.025, .013, .006), 0, 1),
    'Glow': material('Glow', (1, .72, .34), 0, .3),
}
bsdf = MATS['Glow'].node_tree.nodes.get('Principled BSDF')
bsdf.inputs['Emission Color'].default_value = (1, .66, .24, 1)
bsdf.inputs['Emission Strength'].default_value = .7

def xyz(p):
    return (p[0], -p[2], p[1])

def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(MATS[mat])
    if bevel:
        mod = obj.modifiers.new('Soft manufactured edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    mod = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def box(name, p, size, mat, bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1, location=xyz(p))
    obj = bpy.context.object
    obj.dimensions = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, bevel)

def cylinder(name, p, radius, depth, mat, top=None, bevel=.008):
    bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=radius, radius2=radius if top is None else top, depth=depth, location=xyz(p))
    return finish(bpy.context.object, name, mat, bevel)

def ball(name, p, size, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=1, location=xyz(p))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat)

def ring(name, p, radius, tube, mat):
    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=tube, major_segments=36, minor_segments=8, location=xyz(p))
    return finish(bpy.context.object, name, mat)

def rod(name, a, b, radius, mat):
    va, vb = Vector(xyz(a)), Vector(xyz(b))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=(vb-va).length, location=(va+vb)/2)
    obj = bpy.context.object
    obj.rotation_euler = (vb-va).to_track_quat('Z','Y').to_euler()
    return finish(obj, name, mat)

def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def export(name):
    # Join by material: a reusable mesh per finish keeps all eight cabinets cheap.
    for mat_name in MATS:
        bpy.ops.object.select_all(action='DESELECT')
        objects = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.data.materials and o.data.materials[0] == MATS[mat_name]]
        if not objects:
            continue
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = mat_name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.scene.objects if o.type == 'MESH')
    bpy.ops.export_scene.gltf(filepath=str(OUT / (name + '.glb')), export_format='GLB', export_cameras=False, export_lights=False, export_animations=False)
    print('CASINO_MODEL', name, 'triangles', tris)

def cabinet():
    clear()
    box('Weighted plinth', (0,.10,0), (2.18,.20,1.22), 'Dark', .07)
    box('Plinth reveal', (0,.23,0), (2.13,.07,1.16), 'Brass')
    box('Cabinet chassis', (0,1.52,-.18), (1.98,2.48,.82), 'Enamel', .10)
    for x in [-1.01,1.01]:
        box('Walnut cheek', (x,1.52,-.03), (.14,2.46,1.05), 'Walnut', .06)
        box('Edge inlay', (x,1.53,.49), (.035,2.28,.045), 'Brass', .015)
    box('Lower walnut door', (0,.70,.40), (1.88,.84,.16), 'Walnut', .05)
    box('Kick panel', (0,.32,.49), (1.89,.14,.08), 'Brass')
    for x in [-.87,.87]:
        box('Reel frame upright', (x,1.73,.57), (.10,.94,.14), 'Chrome', .025)
    for y in [1.30,2.16]:
        box('Reel frame crossbar', (0,y,.57), (1.84,.09,.14), 'Chrome', .025)
    for x in [-.29,.29]:
        box('Reel separator', (x,1.73,.61), (.055,.8,.08), 'Chrome', .015)
    box('Reel recess', (0,1.73,.29), (1.72,.82,.08), 'Dark')
    box('Crown chrome frame', (0,2.46,.38), (1.94,.50,.36), 'Chrome', .08)
    box('Backlit crown', (0,2.46,.569), (1.72,.32,.018), 'Ivory', .035)
    box('Crown cap', (0,2.74,.02), (2.10,.10,1.08), 'Brass', .045)
    for x in [-.84,.84]:
        for y in [2.35,2.46,2.57]:
            ball('Marquee lamp', (x,y,.594), (.027,.027,.018), 'Glow')
    box('Control deck', (0,1.16,.48), (1.97,.16,.39), 'Enamel', .055)
    box('Control lip', (0,1.09,.68), (1.92,.055,.05), 'Brass')
    box('Credit display bezel', (-.18,.925,.504), (1.40,.26,.065), 'Brass', .025)
    box('Credit display glass', (-.18,.925,.541), (1.29,.18,.016), 'Dark', .012)
    box('Coin acceptor', (.78,.79,.49), (.16,.35,.07), 'Chrome', .03)
    box('Coin slit', (.78,.83,.531), (.025,.16,.012), 'Dark', .008)
    cylinder('Door lock', (.78,.63,.54), .035,.04,'Chrome').rotation_euler.x=math.pi/2
    box('Tray back', (0,.46,.55), (1.2,.25,.08), 'Dark')
    box('Payout tray', (0,.32,.70), (1.24,.07,.33), 'Chrome', .025)
    box('Tray front rim', (0,.40,.86), (1.24,.14,.055), 'Chrome')
    for x in [-.60,.60]:
        box('Tray side', (x,.40,.70), (.045,.14,.34), 'Chrome')
    for x in [-.72,-.38]:
        cylinder('Button surround', (x,1.257,.55), .105,.035,'Chrome')
        cylinder('Bakelite button', (x,1.278,.55), .081,.025,'Velvet')
    cylinder('Spin surround', (.63,1.256,.55), .14,.03,'Chrome')
    cylinder('Spin button', (.63,1.277,.55), .112,.03,'Glow')
    # Machined case screws, with dark slots cut visually into the heads.
    for x in [-.91,.91]:
        for y in [.55,1.25,2.2]:
            screw = cylinder('Fastener', (x,y,.604), .016,.009,'Chrome',bevel=.002)
            screw.rotation_euler.x=math.pi/2
            box('Screw slot',(x,y,.611),(.020,.004,.002),'Dark',.001)
    export('slot_cabinet')

def stool():
    clear()
    cylinder('Foot', (0,.05,0),.4,.1,'Dark')
    cylinder('Pedestal base', (0,.105,0),.38,.06,'Chrome',top=.31)
    cylinder('Pedestal', (0,.4,0),.08,.57,'Chrome')
    ring('Footrest',(0,.30,0),.28,.025,'Brass')
    cylinder('Seat pan',(0,.72,0),.39,.12,'Brass')
    cylinder('Padded seat',(0,.805,0),.40,.15,'Velvet',bevel=.045)
    ring('Upholstery piping',(0,.845,0),.382,.012,'Brass')
    for x in [-.30,.30]:
        rod('Back support',(x,.70,-.21),(x,1.22,-.32),.025,'Chrome')
    box('Curved padded back',(0,1.15,-.34),(.71,.34,.13),'Velvet',.065)
    export('casino_stool')

def bench():
    clear()
    for x in [-.37,.37]:
        for z in [-1.65,1.65]:
            cylinder('Tapered leg',(x,.21,z),.045,.42,'Brass',top=.06)
    box('Seat frame',(0,.40,0),(1.0,.13,4),'Walnut',.045)
    for z in [-1.48,-.49,.49,1.48]:
        box('Seat cushion',(.025,.545,z),(.93,.22,.94),'Velvet',.08)
        box('Back cushion',(-.41,1.03,z),(.18,.77,.94),'Velvet',.07)
        ball('Tuft button',(-.31,1.04,z),(.018,.024,.024),'Brass')
    box('Walnut back',(-.50,.98,0),(.12,1.05,4.02),'Walnut',.04)
    for z in [-1.98,1.98]:
        box('Armrest',(0,.81,z),(1.02,.09,.10),'Walnut',.035)
        rod('Arm support',(.37,.44,z),(.37,.79,z),.023,'Brass')
    export('lounge_bench')

def planter():
    clear()
    cylinder('Glazed pot',(0,.34,0),.36,.68,'Enamel',top=.48,bevel=.025)
    ring('Lip',(0,.67,0),.475,.025,'Brass')
    cylinder('Soil',(0,.64,0),.443,.02,'Soil',bevel=0)
    cylinder('Pot foot',(0,.035,0),.31,.07,'Brass')
    for i in range(13):
        angle=i*2.39996
        height=1.35+(i%4)*.19
        reach=.45+(i%3)*.10
        end=(math.cos(angle)*reach,height,math.sin(angle)*reach)
        rod('Stem',(0,.65,0),end,.012,'Leaf')
        # A folded, curved lanceolate leaf, double sided geometry, visible veins.
        verts=[]
        for row in range(9):
            t=row/8
            r=reach*t
            y=.83+(height-.83)*math.sin(t*math.pi/2)-.18*t*t
            width=.13*math.sin(math.pi*t)
            for side in [-1,0,1]:
                verts.append(xyz((math.cos(angle)*r-math.sin(angle)*width*side, y+(.045*math.sin(math.pi*t) if side==0 else 0),math.sin(angle)*r+math.cos(angle)*width*side)))
        faces=[]
        for row in range(8):
            for col in range(2):
                a=row*3+col
                faces.extend([(a,a+1,a+4,a+3),(a+3,a+4,a+1,a)])
        mesh=bpy.data.meshes.new('Folded leaf');mesh.from_pydata(verts,[],faces);mesh.update()
        obj=bpy.data.objects.new('Leaf',mesh);bpy.context.collection.objects.link(obj)
        finish(obj,'Leaf','Leaf')
    export('ceramic_planter')

def chandelier():
    clear()
    cylinder('Ceiling rose',(0,2.0,0),.28,.1,'Brass')
    cylinder('Suspension',(0,1.0,0),.038,1.9,'Brass')
    ball('Hub',(0,.15,0),(.20,.15,.20),'Brass')
    ring('Outer ring',(0,.13,0),1.16,.035,'Brass')
    ring('Inner ring',(0,.12,0),.55,.025,'Brass')
    for i in range(8):
        a=i*math.tau/8
        x,z=math.cos(a)*1.16,math.sin(a)*1.16
        rod('Radial arm',(0,.13,0),(x,.13,z),.025,'Brass')
        cylinder('Lamp cup',(x,.25,z),.11,.2,'Brass',top=.14)
        cylinder('Opal diffuser',(x,.48,z),.115,.36,'Ivory',top=.15,bevel=.025)
        ring('Shade rim',(x,.66,z),.148,.014,'Brass')
        ball('Lit core',(x,.47,z),(.08,.16,.08),'Glow')
        for j in [-1,0,1]:
            offset=j*.055
            ball('Crystal drop',(x+offset,-.12-abs(j)*.04,z),(.02,.10,.02),'Chrome')
    export('brass_chandelier')

for build in [cabinet,stool,bench,planter,chandelier]:
    build()
