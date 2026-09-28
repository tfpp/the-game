"""Write the authored salon scene. Run with Python after build_salon.py.
All positions are deterministic; decorative patrons have no network/gameplay state.
"""
from pathlib import Path
import math
ROOT=Path(__file__).resolve().parents[1]
resources=[]
nodes=[]
shapes=[]

def v(values):
    return 'Vector3('+', '.join(str(round(x,6)) for x in values)+')'

def ext(kind,path,key):
    resources.append(f'[ext_resource type="{kind}" path="res://features/casino_hub/{path}" id="{key}"]')

ext('Script','model_materials.gd','finishes')
for name in ['card_table','dealer','guest','seated','lady','bar','architecture','sconce']:
    ext('PackedScene',f'models/salon_{name}.glb',name)
for name in ['carpet','wood','painting','brass','ceiling']:
    ext('Material',f'materials/{name}.tres',name)
ext('PackedScene','models/ceramic_planter.tscn','plant')


def model(name,resource,position,angle=0,scale=None):
    text=f'[node name="{name}" parent="." instance=ExtResource("{resource}")]\nposition = {v(position)}\nrotation = {v((0,angle,0))}'
    if scale:
        text+='\nscale = '+v(scale)
    nodes.append(text)


def collision(name,position,size,rotation=0):
    key='shape'+str(len(shapes))
    shapes.append(f'[sub_resource type="BoxShape3D" id="{key}"]\nsize = {v(size)}')
    nodes.append(f'[node name="{name}" type="StaticBody3D" parent="."]\nposition = {v(position)}\nrotation = {v((rotation,0,0))}')
    nodes.append(f'[node name="Shape" type="CollisionShape3D" parent="{name}" groups=["radar_geometry"]]\nshape = SubResource("{key}")')


def box(name,position,size,material,solid=False):
    key='mesh'+str(len(shapes))
    shapes.append(f'[sub_resource type="BoxMesh" id="{key}"]\nsize = {v(size)}\nmaterial = ExtResource("{material}")')
    nodes.append(f'[node name="{name}" type="MeshInstance3D" parent="."]\nposition = {v(position)}\nmesh = SubResource("{key}")')
    if solid:
        collision(name+'Body',position,size)


model('Architecture','architecture',(0,0,0))
box('CofferedCeiling',(0,5.8,0),(28.8,.16,24),'ceiling',True)
for z in [-10,-5,0,5,10]:
    box('CeilingBeam'+str(z),(0,5.66,z),(28.8,.12,.16),'wood')
box('GalleryFloor',(0,3.1,-10),(28.8,.2,4),'carpet',True)
collision('GalleryRail',(1,3.7,-8),(26.4,1,.13))
# The underside stays above the north promenade and ramp.
angle=math.atan2(4.7,12)
collision('StairRamp',(-12.8,.7426,-2),(1.8,.20,math.hypot(12,4.7)),angle)
for x in [-13.76,-11.84]:
    collision('StairRail'+str(x),(x,1.35,-2),(.08,1.2,math.hypot(12,4.7)),angle)
for side in [-1,1]:
    collision('SideWall'+str(side),(side*14.4,2.1,0),(.18,7.2,24))
for i,x in enumerate([-10,-3.8,3.8,10]):
    collision('Column'+str(i),(x,2.1,-8.1),(.55,7.2,.55))
for i,z in enumerate([-3,4]):
    collision('SalonColumn'+str(i),(-8.8,2.1,z),(.72,7.2,.72))
    model('ColumnSconce'+str(i),'sconce',(-8.8,1.4,z+.38))
for i,z in enumerate([-6.2,-1.2,3.4]):
    model('CardTable'+str(i),'card_table',(-4.0,-1.5,z))
    collision('TableBody'+str(i),(-4.0,-1.03,z+.54),(4.12,.94,1.15))
    model('Dealer'+str(i),'dealer',(-4.0,-1.5,z-.45))
    # Patrons sit on the table's three built-in chairs, facing the dealer.
    for j in range(3):
        a=(j+1)*math.pi/4
        collision(f'ChairBody{i}_{j}',(-4.0+math.cos(a)*2.35,-.90,z+math.sin(a)*1.55),(.68,1.2,.68))
        model(f'Patron{i}_{j}','lady' if (i+j)%3==0 else 'seated',(-4.0+math.cos(a)*2.35,-1.5,z+math.sin(a)*1.55),math.pi/2+a)
model('Bar','bar',(-7.4,-1.5,-10.7))
collision('BarCounter',(-7.4,-1.01,-9.6),(7,.98,.4))
model('Bartender','dealer',(-6.5,-1.5,-10.3))
model('GuestAtBar','guest',(-8.2,-1.5,-8.25),math.pi)
model('GuestTalking','guest',(3.0,-1.5,1),-.6)
model('GuestGallery','guest',(2.5,3.2,-8.6),.4)
model('GuestGallery2','guest',(-4.8,3.2,-9.2),-.5)
for i,(x,z) in enumerate([(-10,7),(-11,-6),(4,-10),(12,10)]):
    model('Palm'+str(i),'plant',(x,-1.5,z),scale=(1.4,1.6,1.4))
for side in [-1,1]:
    for i,z in enumerate([-10,-5,0,5,10]):
        model(f'Sconce{side}_{i}','sconce',(side*13.93,1.45,z),-side*math.pi/2)
        # Painted canvas sits flush in a four-piece frame, only two image draws per wall.
        if i%2==1:
            key=f'canvas{side+1}_{i}'
            shapes.append(f'[sub_resource type="QuadMesh" id="{key}"]\nsize = Vector2(1.8, 2.0)\nmaterial = ExtResource("painting")')
            nodes.append(f'[node name="Painting{side}_{i}" type="MeshInstance3D" parent="."]\nposition = {v((side*14.27,1.4,z+2.3))}\nrotation = {v((0,-side*math.pi/2,0))}\nmesh = SubResource("{key}")')
            for dz in [-.98,.98]:
                box(f'FrameVertical{side}_{i}_{dz}',(side*14.2,1.4,z+2.3+dz),(.12,2.22,.10),'brass')
            for y in [.34,2.46]:
                box(f'FrameHorizontal{side}_{i}_{y}',(side*14.2,y,z+2.3),(.12,.10,2.06),'brass')
for i,x in enumerate([-7,7]):
    key='gallerypainting'+str(i)
    shapes.append(f'[sub_resource type="QuadMesh" id="{key}"]\nsize = Vector2(2.5, 1.65)\nmaterial = ExtResource("painting")')
    nodes.append(f'[node name="GalleryPainting{i}" type="MeshInstance3D" parent="."]\nposition = {v((x,4.55,-11.73))}\nmesh = SubResource("{key}")')
    for dx in [-1.3,1.3]:
        box(f'GalleryFrameSide{i}_{dx}',(x+dx,4.55,-11.68),(.10,1.85,.10),'brass')
    for y in [3.68,5.42]:
        box(f'GalleryFrameTop{i}_{y}',(x,y,-11.68),(2.7,.10,.10),'brass')
for i,(x,z) in enumerate([(-6,-5),(-6,.5),(-6,6),(-7,-10),(11,-6),(11,2)]):
    nodes.append(f'[node name="WarmPool{i}" type="OmniLight3D" parent="."]\nposition = {v((x,1.2,z))}\nlight_color = Color(1, 0.62, 0.28, 1)\nlight_energy = 0.8\nlight_specular = 0.0\nomni_range = 5.5\nshadow_enabled = false')
ROOT.joinpath('salon.tscn').write_text('[gd_scene load_steps='+str(len(resources)+len(shapes)+1)+' format=3]\n\n'+'\n\n'.join(resources+shapes)+'\n\n[node name="Salon" type="Node3D"]\nscript = ExtResource("finishes")\n\n'+'\n\n'.join(nodes)+'\n')
