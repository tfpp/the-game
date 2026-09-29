"""Blender source for one connected, vertex-deformed human avatar.
Run: blender --background --factory-startup --python this_file.py
"""
from pathlib import Path
from math import sin, cos, pi, atan2
import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def b(point):
    x,y,z=point
    return Vector((x,-z,y))

def g(point):
    return Vector((point.x,point.z,-point.y))

points=[]; edges=[]; radii=[]
def joint(point,radius,parent=None):
    index=len(points);points.append(b(point));radii.append(radius)
    if parent is not None: edges.append((parent,index))
    return index
hip=joint((0,-.17,0),(.16,.12))
waist=joint((0,.00,0),(.155,.10),hip)
chest=joint((0,.26,0),(.21,.115),waist)
upper=joint((0,.40,0),(.15,.085),chest)
neck=joint((0,.50,0),(.058,.054),upper)
head=joint((0,.62,.004),(.085,.080),neck)
headmid=joint((0,.75,.006),(.090,.085),head)
joint((0,.83,.007),(.050,.051),headmid)
for side in [-1,1]:
    shoulder=joint((side*.255,.35,0),(.078,.074),chest)
    arm=joint((side*.272,.20,0),(.073,.072),shoulder)
    elbow=joint((side*.288,.055,0),(.052,.053),arm)
    forearm=joint((side*.304,-.10,0),(.054,.052),elbow)
    wrist=joint((side*.316,-.23,0),(.032,.030),forearm)
    joint((side*.318,-.263,-.004),(.026,.023),wrist)
    pelvis=joint((side*.111,-.22,0),(.100,.098),hip)
    thigh=joint((side*.116,-.37,0),(.092,.099),pelvis)
    knee=joint((side*.120,-.53,.004),(.061,.060),thigh)
    calf=joint((side*.120,-.665,.009),(.063,.066),knee)
    ankle=joint((side*.120,-.80,0),(.040,.040),calf)
    heel=joint((side*.120,-.850,-.02),(.050,.061),ankle)
    joint((side*.120,-.860,-.130),(.048,.035),heel)
mesh=bpy.data.meshes.new('ConnectedHumanTopology')
mesh.from_pydata(points,edges,[]);mesh.update()
body=bpy.data.objects.new('Human',mesh)
bpy.context.collection.objects.link(body)
bpy.context.view_layer.objects.active=body;body.select_set(True)
skin=body.modifiers.new('Connected topology','SKIN')
skin.use_smooth_shade=True
for index,item in enumerate(mesh.skin_vertices[0].data):
    item.radius=radii[index];item.use_root=index==hip
sub=body.modifiers.new('Shape vertex flow','SUBSURF');sub.levels=2
bpy.ops.object.modifier_apply(modifier=skin.name)
bpy.ops.object.modifier_apply(modifier=sub.name)
decimate=body.modifiers.new('GoldSrc polygon budget','DECIMATE');decimate.ratio=.33
bpy.ops.object.modifier_apply(modifier=decimate.name)
body.data.validate(clean_customdata=True)
# Sculpt the connected head vertices: oval skull, jaw, chin and nose ridge.
max_y=max(g(v.co).y for v in body.data.vertices)
for vertex in body.data.vertices:
    p=g(vertex.co)
    if p.y>.555:
        t=max(0,min(1,(p.y-.555)/(max_y-.555)))
        angle=atan2(p.x,-(p.z-.005))
        rx=.092*(.47+.53*sin(pi*t)**.48)
        rz=.086*(.62+.38*sin(pi*t)**.55)
        y=.555+t*.285
        x=sin(angle)*rx
        z=.009-cos(angle)*rz
        front=max(0,cos(angle))
        nose=.032*max(0,1-abs(y-.683)/.042)*max(0,1-abs(x)/.027)*front**10
        z-=nose
        vertex.co=b((x,y,z))
    if p.y<-.88:
        vertex.co=b((p.x,-.89,p.z))
# Author palms and each digit as connected vertex loops. During authoring only,
# weld their wrist volumes into the body; export still contains one closed mesh.
digit_chains = {}
for side, suffix in [(-1, 'L'), (1, 'R')]:
    verts=[]; faces=[]
    def hv(x,y,z):
        verts.append(b((side*x,y,z)))
        return len(verts)-1
    rows=[(-.228,.030,.025),(-.268,.040,.022),(-.307,.038,.019)]
    layers=[]
    for depth_side in [-1,1]:
        layer=[]
        for y,width,depth in rows:
            layer.append([hv(.320+(i/4*2-1)*width,y,-.004+depth_side*depth) for i in range(5)])
        layers.append(layer)
    for layer in layers:
        for r in range(2):
            for c in range(4):
                faces.append([layer[r][c],layer[r][c+1],layer[r+1][c+1],layer[r+1][c]])
    # Wrist cap and outer palm wall. The inner lower wall becomes the thumb root.
    for c in range(4):
        faces.append([layers[0][0][c],layers[1][0][c],layers[1][0][c+1],layers[0][0][c+1]])
    for r in range(2):
        faces.append([layers[0][r][4],layers[0][r+1][4],layers[1][r+1][4],layers[1][r][4]])
    faces.append([layers[0][0][0],layers[0][1][0],layers[1][1][0],layers[1][0][0]])
    def extend_digit(name,ring,centers,half_width,half_depth):
        previous=ring
        for j,center in enumerate(centers[1:]):
            # A separate vertex loop at every phalanx preserves bend topology.
            taper=[.90,.76,.53][j]
            x,y,z=center
            current=[hv(x-half_width*taper,y,z-half_depth*taper),
                     hv(x+half_width*taper,y,z-half_depth*taper),
                     hv(x+half_width*taper,y,z+half_depth*taper),
                     hv(x-half_width*taper,y,z+half_depth*taper)]
            if name=='Thumb':
                # Thumb loops face across the palm instead of down its length.
                current=[hv(x,y-half_width*taper,z-half_depth*taper),
                         hv(x,y+half_width*taper,z-half_depth*taper),
                         hv(x,y+half_width*taper,z+half_depth*taper),
                         hv(x,y-half_width*taper,z+half_depth*taper)]
            for k in range(4): faces.append([previous[k],previous[(k+1)%4],current[(k+1)%4],current[k]])
            previous=current
        faces.append(previous)
        digit_chains[name+suffix]=[Vector((side*x,y,z)) for x,y,z in centers]
    for c,(name,length) in enumerate(zip(['Index','Middle','Ring','Little'],[.075,.085,.078,.061])):
        x=.320+(c+.5-2)*.019
        centers=[(x,-.307-length*j/3,-.004-.004*j/3) for j in range(4)]
        ring=[layers[0][2][c],layers[0][2][c+1],layers[1][2][c+1],layers[1][2][c]]
        extend_digit(name,ring,centers,.008,.019)
    thumb_ring=[layers[0][2][0],layers[0][1][0],layers[1][1][0],layers[1][2][0]]
    centers=[(.281-.052*j/3,-.2875-.030*j/3,-.004-.009*j/3) for j in range(4)]
    extend_digit('Thumb',thumb_ring,centers,.0195,.0205)
    hand_mesh=bpy.data.meshes.new('HandVertexLoops'+suffix)
    hand_mesh.from_pydata(verts,[],faces);hand_mesh.update()
    bm=bmesh.new();bm.from_mesh(hand_mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(hand_mesh);bm.free()
    hand=bpy.data.objects.new('HandAuthoring'+suffix,hand_mesh)
    bpy.context.collection.objects.link(hand)
    bpy.context.view_layer.objects.active=hand
    bevel=hand.modifiers.new('Sculpt finger edge loops','BEVEL')
    bevel.width=.0015;bevel.segments=1
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    weld=body.modifiers.new('Weld hand topology'+suffix,'BOOLEAN')
    weld.operation='UNION';weld.solver='EXACT';weld.object=hand
    bpy.context.view_layer.objects.active=body
    bpy.ops.object.modifier_apply(modifier=weld.name)
    bpy.data.objects.remove(hand,do_unlink=True)
body.data.validate(clean_customdata=True)
for poly in body.data.polygons: poly.use_smooth=True
body.data.update()
# A single continuous mesh, with stable UVs and per-face palette/visibility tags.
uv=body.data.uv_layers.new(name='PaintUV')
mask_uv=body.data.uv_layers.new(name='RestCoordinates')
colors=body.data.color_attributes.new(name='AvatarTags',type='FLOAT_COLOR',domain='CORNER')
for poly in body.data.polygons:
    center=sum((g(body.data.vertices[i].co) for i in poly.vertices),Vector())/len(poly.vertices)
    arm=(abs(center.x)>.233 or (center.y<-.23 and abs(center.x)>.21)) and center.y>-.43
    scalp=center.y>.78 or (center.y>.655 and center.z>.040)
    face=center.y>.555 and center.z<.015 and not scalp
    gear=(abs(center.x)<.20 and .015<center.y<.39 and center.z<-.075)
    role=7 if face else 3 if scalp else 5 if gear else 1 if center.y>-.16 and center.y<.455 else 2 if center.y<-.16 and center.y>-.79 and not arm else 6 if center.y<-.79 else 0
    if arm: role=1 if center.y>.045 else 0
    side=0.0 if arm and center.x<0 else 1.0 if arm else .5
    head_tag=1.0 if center.y>.52 else 0.0
    for loop in poly.loop_indices:
        p=g(body.data.vertices[body.data.loops[loop].vertex_index].co)
        if role==7:
            coords=((p.x+.10)/.20,(p.y-.555)/.285)
        elif role==3:
            coords=((atan2(p.x,-p.z)+pi)/(2*pi),(p.y-.60)/.24)
        else:
            local_x=p.x
            if arm: local_x-=.302 if p.x>0 else -.302
            elif role in [2,6]: local_x-=.120 if p.x>0 else -.120
            u=(atan2(local_x,-p.z)+pi)/(2*pi)
            v=(p.y+.17)/.62 if role in [1,5] and not arm else (.36-p.y)/.59 if arm else (-p.y-.17)/.64 if role==2 else (-p.y-.80)/.10 if role==6 else (p.y+.89)/1.73
            coords=(u,v)
        uv.data[loop].uv=coords
        mask_uv.data[loop].uv=(p.x,p.y)
        colors.data[loop].color=(role/10,side,head_tag,.5+p.z)
# Shape keys operate on the same vertex indices; no body-part assemblies.
body.shape_key_add(name='Basis')
feminine=body.shape_key_add(name='Feminine')
long=body.shape_key_add(name='LongHair')
swept=body.shape_key_add(name='SweptHair')
crop=body.shape_key_add(name='CroppedHair')
tactical=body.shape_key_add(name='Tactical')
for index,vertex in enumerate(body.data.vertices):
    p=g(vertex.co)
    q=p.copy()
    if p.y<.48 and p.y>-.17:
        q.x*=.91 if p.y>.06 else 1.04
    elif -.46<p.y<-.17: q.x*=1.08
    elif abs(p.x)>.235 and p.y<.40: q.x*=.93
    feminine.data[index].co=b(q)
    q=p.copy()
    if p.y>.62 and p.z>.04:
        amount=max(0,min(1,(p.z-.04)/.038))*max(0,1-abs(p.y-.69)/.16)
        q.y-=.26*amount;q.z+=.027*amount
    long.data[index].co=b(q)
    q=p.copy()
    if p.y>.78:
        q.x-=.018*(p.y-.78)/.06;q.y+=.007*(p.x/.092)
    swept.data[index].co=b(q)
    q=p.copy()
    if p.y>.775: q.y-=.006
    crop.data[index].co=b(q)
    q=p.copy()
    if -.18<p.y<.40 and abs(p.x)<.225:
        q.x*=1.08;q.z*=1.19
        if p.z<-.065 and .02<p.y<.22:
            q.z-=.018*(.5+.5*cos(p.x*45))
    if -.86<p.y<-.66 and abs(p.x)>.055:
        legx=.12 if p.x>0 else -.12
        q.x=legx+(q.x-legx)*1.22;q.z*=1.18
    tactical.data[index].co=b(q)
# Actual armature and blended vertex weights.
bpy.ops.object.armature_add(enter_editmode=True)
rig=bpy.context.object;rig.name='HumanRig'
rig.data.edit_bones.remove(rig.data.edit_bones[0])
bones={}
def bone(name,start,end,parent=None):
    item=rig.data.edit_bones.new(name);item.head=b(start);item.tail=b(end)
    if parent:item.parent=bones[parent]
    bones[name]=item
bone('Hips',(0,-.17,0),(0,.00,0))
bone('Spine',(0,.00,0),(0,.45,0),'Hips')
bone('Head',(0,.50,0),(0,.83,.005),'Spine')
for side,suffix in [(-1,'L'),(1,'R')]:
    bone('UpperArm'+suffix,(side*.255,.35,0),(side*.288,.055,0),'Spine')
    bone('Forearm'+suffix,(side*.288,.055,0),(side*.316,-.23,0),'UpperArm'+suffix)
    bone('Hand'+suffix,(side*.316,-.23,0),(side*.320,-.307,-.004),'Forearm'+suffix)
    for digit in ['Thumb','Index','Middle','Ring','Little']:
        chain=digit_chains[digit+suffix]
        for segment in range(3):
            name=digit+str(segment+1)+suffix
            parent='Hand'+suffix if segment==0 else digit+str(segment)+suffix
            bone(name,chain[segment],chain[segment+1],parent)
    bone('Thigh'+suffix,(side*.111,-.17,0),(side*.120,-.53,.004),'Hips')
    bone('Calf'+suffix,(side*.120,-.53,.004),(side*.120,-.80,0),'Thigh'+suffix)
    bone('Foot'+suffix,(side*.120,-.80,0),(side*.120,-.86,-.13),'Calf'+suffix)
bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True);rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
# Assign each digit to its own phalanx chain instead of letting close neighboring
# fingers share heat weights. Palm vertices retain wrist/hand articulation.
def segment_distance(point,start,end):
    direction=end-start
    t=max(0,min(1,(point-start).dot(direction)/direction.length_squared))
    return (point-(start+direction*t)).length, t
for vertex in body.data.vertices:
    point=g(vertex.co)
    if not (.22<abs(point.x)<.40 and -.43<point.y<-.244): continue
    suffix='R' if point.x>0 else 'L'
    for group in body.vertex_groups: group.remove([vertex.index])
    if point.y>-.300 and abs(point.x)>.285:
        assignments={'Hand'+suffix:1.0}
    else:
        candidates=[]
        for digit in ['Thumb','Index','Middle','Ring','Little']:
            chain=digit_chains[digit+suffix]
            for segment in range(3):
                distance,t=segment_distance(point,chain[segment],chain[segment+1])
                candidates.append((distance,digit,segment,t))
        _,digit,segment,t=min(candidates)
        name=digit+str(segment+1)+suffix
        assignments={name:1.0}
        if t<.25:
            adjacent='Hand'+suffix if segment==0 else digit+str(segment)+suffix
            blend=(.25-t)*2
            assignments={name:1-blend,adjacent:blend}
        elif t>.75 and segment<2:
            blend=(t-.75)*2
            assignments={name:1-blend,digit+str(segment+2)+suffix:blend}
    for name,weight in assignments.items():
        body.vertex_groups[name].add([vertex.index],weight,'REPLACE')
# Normalize the heat weights explicitly, limiting each vertex to four influences.
for vertex in body.data.vertices:
    weights=sorted([(item.group,max(0.0,min(1.0,item.weight))) for item in vertex.groups],key=lambda pair:pair[1],reverse=True)[:4]
    total=sum(weight for _,weight in weights)
    for group in body.vertex_groups: group.remove([vertex.index])
    if total>0:
        for group,weight in weights: body.vertex_groups[group].add([vertex.index],weight/total,'REPLACE')
# Vertex tags remain authored colors; the runtime single material reads them.
material=bpy.data.materials.new('HumanSurface');material.use_nodes=True
material.diffuse_color=(.6,.55,.48,1)
vertex_node=material.node_tree.nodes.new('ShaderNodeVertexColor')
vertex_node.layer_name='AvatarTags'
principled=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
material.node_tree.links.new(vertex_node.outputs['Color'],principled.inputs['Base Color'])
body.data.materials.append(material)
body.data.validate(verbose=True)
body.data.update()
assert not body.data.validate(), 'Export mesh must validate without repairs'
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'source'/'human.blend'))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'models'/'human.glb'),export_format='GLB',use_selection=True,export_skins=True,export_morph=True,export_morph_normal=True,export_animations=False,export_texcoords=True,export_normals=True,export_all_vertex_colors=True)
# Topology and budget evidence from the source, before export UV seam duplicates.
parents=list(range(len(body.data.vertices)))
def find(a):
    while parents[a]!=a:
        parents[a]=parents[parents[a]];a=parents[a]
    return a
for edge in body.data.edges:
    a,c=map(find,edge.vertices);parents[c]=a
components=len({find(i) for i in range(len(parents))})
body.data.calc_loop_triangles()
print('HUMAN_SOURCE components=%d vertices=%d triangles=%d bones=%d shapes=%d' % (components,len(body.data.vertices),len(body.data.loop_triangles),len(rig.data.bones),len(body.data.shape_keys.key_blocks)))
assert components==1,'Human must be a single connected surface'
