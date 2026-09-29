"""Reproducible, faceted dealer with a painted, face-projected 128px atlas."""
import base64
import json
import math
from pathlib import Path
import struct
import uuid
import zlib

ROOT = Path(__file__).resolve().parent
N = 128
DENSITY = 1.0
NS = uuid.UUID('aa05de87-711a-423e-8210-6de63b2c476a')
def uid(name): return str(uuid.uuid5(NS, name))
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def norm(a):
    length=math.sqrt(dot(a,a))
    return [x/length for x in a]
model={'meta':{'format_version':'5.0','model_format':'free','box_uv':False},'name':'Casino Dealer','model_identifier':'casino_dealer','resolution':{'width':N,'height':N},'elements':[],'groups':[],'outliner':[],'textures':[],'animations':[],'ai_used':True,'ai_agents':'codex-mcp-client'}
groups={}
records=[]
def group(name,origin,parent=None):
    g={'uuid':uid(name),'name':name,'origin':origin,'rotation':[0,0,0],'export':True,'visibility':True}
    model['groups'].append(g)
    node={'uuid':g['uuid'],'isOpen':True,'children':[]}
    groups[name]=node
    (groups[parent]['children'] if parent else model['outliner']).append(node)

def mesh(name,verts,faces,material,parent):
    m={'uuid':uid(name),'name':name,'type':'mesh','origin':[0,0,0],'rotation':[0,0,0],'vertices':{str(i):p for i,p in enumerate(verts)},'faces':{},'visibility':True,'export':True}
    for i,indices in enumerate(faces):
        keys=[str(k) for k in indices]
        ps=[verts[k] for k in indices]
        u=norm(sub(ps[1],ps[0])); normal=norm(cross(sub(ps[1],ps[0]),sub(ps[2],ps[0]))); v=cross(normal,u)
        if abs(normal[1]) < .9:
            u=norm(cross([0,1,0],normal)); v=cross(normal,u)
        density = 5.0 if material == 'face' and normal[2] < -.8 else (2.0 if parent == 'head' else DENSITY)
        coords=[[dot(sub(p,ps[0]),u)*density,dot(sub(p,ps[0]),v)*density] for p in ps]
        low=[min(p[j] for p in coords) for j in range(2)]
        coords=[[p[j]-low[j] for j in range(2)] for p in coords]
        w=math.ceil(max(p[0] for p in coords))+3; h=math.ceil(max(p[1] for p in coords))+3
        face={'vertices':keys,'uv':{},'texture':0}; m['faces'][str(i)]=face
        records.append({'face':face,'keys':keys,'coords':coords,'w':w,'h':h,'base':ps[0],'low':low,'u':u,'v':v,'normal':normal,'material':material,'name':name,'density':density})
    model['elements'].append(m); groups[parent]['children'].append(m['uuid'])

def rings(name,levels,material,parent):
    # Clockwise in XZ viewed from above; ring face winding is outward.
    shape=[(-.65,-1),(.65,-1),(1,-.65),(1,.65),(.65,1),(-.65,1),(-1,.65),(-1,-.65)]
    verts=[]
    for y,cx,cz,rx,rz in levels:
        verts.extend([[cx+x*rx,y,cz+z*rz] for x,z in shape])
    faces=[]
    for j in range(len(levels)-1):
        for i in range(8): faces.append([j*8+i,(j+1)*8+i,(j+1)*8+(i+1)%8,j*8+(i+1)%8])
    # Triangulated caps avoid concave/ngon importer differences.
    for i in range(1,7): faces.append([0,i,(i+1)])
    last=(len(levels)-1)*8
    for i in range(1,7): faces.append([last,last+i+1,last+i])
    mesh(name,verts,faces,material,parent)

def slab(name,points,depth,material,parent):
    n=len(points); verts=points+[[x,y,z+depth] for x,y,z in points]
    faces=[]
    # points clockwise as viewed from front (-Z)
    for i in range(1,n-1): faces.extend([[0,i,i+1],[n,n+i+1,n+i]])
    for i in range(n): faces.append([i,n+i,n+(i+1)%n,(i+1)%n])
    mesh(name,verts,faces,material,parent)

group('rig_root',[0,0,0]); group('pelvis',[0,17,0],'rig_root'); group('spine',[0,18,0],'pelvis'); group('head',[0,28,0],'spine')
rings('trouser_seat',[(15.5,0,0,3.75,1.85),(18,0,0,3.65,1.8)],'pants','pelvis')
rings('waistcoat',[(17.2,0,0,3.8,2),(19,0,0,3.4,1.8),(23.5,0,0,4.15,2.05),(26.6,0,0,4.8,1.9),(27.4,0,0,2,1.6)],'vest','spine')
rings('neck',[(26.8,0,0,1.35,1.2),(28.1,0,0,1.398148148,1.224074074),
              (28.45,0,.3,1.05,.9),(29.15,0,.4,1.0,.8)],'skin','head')
rings('collar_band',[(27,0,0,1.65,1.4),(28.1,0,0,1.48,1.3)],'shirt','spine')
# Collar points and bow tie sit just above the shirt bib.
slab('collar_left',[[-1.6,27.9,-1.5],[-.15,27.35,-1.9],[-.85,26.35,-2.08]],.22,'shirt','spine')
slab('collar_right',[[.15,27.35,-1.9],[1.6,27.9,-1.5],[.85,26.35,-2.08]],.22,'shirt','spine')
slab('bow_left',[[-1.3,27.5,-2.15],[-.25,27.2,-2.25],[-.25,26.7,-2.25],[-1.3,26.5,-2.15]],.4,'red','spine')
slab('bow_right',[[.25,27.2,-2.25],[1.3,27.5,-2.15],[1.3,26.5,-2.15],[.25,26.7,-2.25]],.4,'red','spine')
rings('bow_knot',[(26.65,0,-2.12,.37,.28),(27.3,0,-2.12,.37,.28)],'red','spine')
# Facial cross-sections vary independently across X and Z. The center muzzle/chin
# project forward, cheeks flare forward laterally, and eye sockets recede.
face_sections=[
    # y, half-width, center Z, cheek Z, side-front Z, back Z
    # Side reference: chin behind forehead, shallow cheek hollow, compact muzzle.
    (28.45,1.05,-1.26,-.93,-.4,.9),
    (28.68,1.3,-1.42,-1.12,-.6,1.1),
    (29.08,1.37,-1.39,-1.1,-.62,1.27),
    (29.38,1.43,-1.47,-1.05,-.65,1.32),
    (29.6,1.47,-1.46,-1.04,-.65,1.37),
    (30.03,1.55,-1.43,-1.13,-.74,1.42),
    (30.56,1.72,-1.43,-1.5,-.82,1.55),
    (31.1,1.77,-1.5,-1.32,-.8,1.6),
    (31.4,1.81,-1.57,-1.49,-.87,1.62),
    (32.3,1.85,-1.57,-1.51,-.95,1.63),
    (32.85,1.75,-1.33,-1.32,-.85,1.7),
    (33.4,1.3,-.7,-.7,-.5,1.4),
]
face_vertices=[]
for y,w,center,cheek,side,back in face_sections:
    face_vertices.extend([[-w*.65,y,cheek],[-w*.28,y,center],
                          [w*.28,y,center],[w*.65,y,cheek],
                          [w,y,side],[w,y,back*.65],[w*.65,y,back],
                          [-w*.65,y,back],[-w,y,back*.65],[-w,y,side]])
face_faces=[]
for j in range(len(face_sections)-1):
    for i in range(10):
        a=j*10+i; b=(j+1)*10+i; c=(j+1)*10+(i+1)%10; d=j*10+(i+1)%10
        face_faces.extend([[a,b,c],[a,c,d]])
face_vertices.extend([[0,28.45,0],[0,33.4,0]])
for i in range(10):
    face_faces.extend([[120,i,(i+1)%10],[121,110+(i+1)%10,110+i]])
mesh('face',face_vertices,face_faces,'face','head')
# Short straight bridge and compact tip measured against the side silhouette.
mesh('nose',[[-.19,31.29,-1.49],[.19,31.29,-1.49],[-.24,30.12,-1.93],
             [.24,30.12,-1.93],[-.33,29.98,-1.79],[.33,29.98,-1.79],
             [-.32,29.98,-1.27],[.32,29.98,-1.27]],
     [[0,1,3,2],[2,3,5,4],[4,5,7,6],[0,2,4,6],[1,7,5,3],[0,6,7,1]],'face','head')
for sign,side in [(-1,'right'),(1,'left')]:
    rings('ear_'+side,[(29.95,sign*1.73,.27,.22,.32),
                       (30.95,sign*1.86,.27,.24,.38),
                       (31.25,sign*1.85,.28,.2,.32)],'face','head')
    # Dark stylized eye/brow bars, seated nearly flush in the eye plane.
    points=[[sign*.37,30.98,-1.57],[sign*1.48,31.03,-1.43],
            [sign*1.48,31.4,-1.49],[sign*.37,31.39,-1.61]]
    if sign == -1: points.reverse()
    points.reverse()
    slab('brow_'+side,points,.16,'brow','head')
# Low swept-back crown, not the previous tall isolated crest.
rings('hair_cap',[(32.3,0,.08,1.88,1.75),(33.15,0,.07,1.94,1.75),
                  (33.72,-.1,.2,1.45,1.4)],'hair','head')
rings('hair_back',[(29.9,0,1.39,1.34,.36),(31.7,0,1.36,1.75,.45),
                   (33.15,0,1.3,1.8,.43)],'hair','head')
for sign,side in [(-1,'right'),(1,'left')]:
    rings('temple_'+side,[(31.02,sign*1.66,-.22,.2,.65),
                         (31.55,sign*1.72,-.12,.2,.96),
                         (32.6,sign*1.7,.04,.2,1.25)],'hair','head')
slab('swept_forelock',[[-.45,32.4,-1.68],[-.55,33.4,-1.79],
                       [-.2,34.0,-1.1],[.72,33.96,-1.01],
                       [1.1,32.42,-1.65]],1.25,'hair','head')
for s,side in [(-1,'right'),(1,'left')]:
    group('upper_arm_'+side,[s*4.5,26.15,0],'spine')
    group('forearm_'+side,[s*6.05,21,0],'upper_arm_'+side)
    group('hand_'+side,[s*7.35,16,0],'forearm_'+side)
    group('thigh_'+side,[s*2,17,0],'pelvis')
    group('shin_'+side,[s*2.45,9,0],'thigh_'+side)
    group('foot_'+side,[s*2.65,2,0],'shin_'+side)
    rings('sleeve_upper_'+side,[(20.8,s*6.1,0,.95,1.1),(23.5,s*5.5,0,1.2,1.4),(26.4,s*4.7,0,1.2,1.5)],'shirt','upper_arm_'+side)
    rings('sleeve_lower_'+side,[(16.2,s*7.35,0,.8,.9),(18.5,s*6.8,0,1,1.05),(21.2,s*6.05,0,1,1.1)],'shirt','forearm_'+side)
    rings('cuff_'+side,[(15.65,s*7.48,0,.86,.96),(16.6,s*7.23,0,.88,.98)],'cuff','forearm_'+side)
    rings('palm_'+side,[(13.65,s*7.75,-.05,.77,.57),(14.55,s*7.7,-.1,.88,.6),(15.85,s*7.45,0,.65,.65)],'skin','hand_'+side)
    rings('fingers_'+side,[(12.55,s*7.55,-.3,.45,.4),(13.2,s*7.95,-.28,.6,.45),(14.15,s*7.95,-.12,.62,.5)],'skin','hand_'+side)
    rings('thumb_'+side,[(13.7,s*6.7,-.55,.28,.3),(14.55,s*6.65,-.6,.35,.4),(15.1,s*7.1,-.25,.4,.4)],'skin','hand_'+side)
    rings('trouser_thigh_'+side,[(8.8,s*2.45,0,1.48,1.5),(13,s*2.2,0,1.65,1.75),(17,s*1.95,0,1.8,1.8)],'pants','thigh_'+side)
    rings('trouser_shin_'+side,[(2,s*2.8,0,1.52,1.42),(6,s*2.6,0,1.4,1.42),(9.25,s*2.45,0,1.5,1.5)],'pants','shin_'+side)
    rings('shoe_sole_'+side,[(0,s*2.8,-.65,1.58,2.3),(.5,s*2.8,-.65,1.62,2.35)],'sole','foot_'+side)
    rings('shoe_upper_'+side,[(.5,s*2.8,-.65,1.58,2.3),(1.3,s*2.8,-.65,1.48,2.2),(2.4,s*2.8,0,1.15,1.35)],'shoe','foot_'+side)

PALETTE={'skin':(181,119,67),'face':(186,127,77),'shirt':(222,213,196),'cuff':(235,227,210),'vest':(31,29,28),'pants':(29,28,28),'hair':(30,27,25),'red':(133,20,24),'shoe':(31,28,28),'sole':(20,19,19),'brow':(53,36,24)}
def paint(rec,p,px,py):
    x,y,z=p; mat=rec['material']; c=PALETTE[mat]
    # Low contrast patches retain the reference's coarse, hand-painted character.
    seed=(int(math.floor(x*1.7))*73856093 ^ int(math.floor(y*1.5))*19349663 ^ int(math.floor(z*1.8))*83492791)&0xffffffff
    noise=(seed%11)-5
    if mat=='vest':
        if z < -1.25:
            if y>21.15 and abs(x)<(y-21.15)*.32: c=PALETTE['shirt']
            if abs(x)<.16 and 21.5<y<26: c=(197,187,171)
            if abs(x)<.19 and any(abs(y-b)<.22 for b in [22.4,24.4,25.8]): c=(70,64,58)
            if abs(x-.25)<.15 and any(abs(y-b)<.17 for b in [18.5,20]): c=(12,12,13)
            if 1.65<x<3.15 and 23.4<y<24.25:
                c=(192,137,49)
                if y>24.02 or x<1.8: c=(235,187,76)
                if 2.15<x<2.65 and 23.66<y<23.98: c=(251,221,137)
            if .6<abs(x)<2.95 and 19.7<y<19.93: c=(12,12,13)
        if z>1.2 and 18.75<y<19.95:
            c=(21,20,20)
            if abs(x)<.65:
                c=(185,128,41) if abs(x)>.34 or y<19.03 or y>19.65 else (14,14,14)
        if abs(x)>3.72 and y<22.6: c=(67,20,22)
    if mat=='face':
        ax=abs(x)
        # Warm ochre skin, broad low-contrast planes, no pink or brown lip block.
        c=(188,128,76)
        noise//=2
        if z < -1.1:
            if 29.75<y<30.55 and ax>.9: c=(180,119,69)
            if 29.29<y<29.51 and ax<.5: c=(176,113,65)
            if 29.35<y<29.45 and ax<.46: c=(150,96,54)
            if 29.13<y<29.28 and ax<.42: c=(197,135,79)
            if y<28.67: c=(165,107,60)
            if rec['name']=='nose' and z<-1.65 and y<30.1: c=(149,94,50)
    if mat=='brow': noise=0
    if mat=='hair':
        noise//=2
        if int((x+y*.4)*3)%6==0: noise+=5
    if mat=='pants':
        if abs((abs(x)-2.5))<.25: noise+=5
    if mat=='shoe' and z<-1.4 and y>.8: noise+=9
    return tuple(max(0,min(255,k+noise)) for k in c)

# Preserve every approved body element, UV coordinate and body-atlas byte.
body_base=json.loads((ROOT/'body_base.json').read_text())
body_names={e['name'] for e in body_base['elements'] if e['name'] != 'neck'}
records=[r for r in records if r['name'] not in body_names]
by_name={e['name']:e for e in body_base['elements'] if e['name'] != 'neck'}
model['elements']=[by_name.get(e['name'],e) for e in model['elements']]
for e in model['elements']:
    if e['name'] not in body_names:
        for f in e['faces'].values(): f['texture']=1
# Shelf-pack the independent head atlas, with one-pixel gutters.

# Horizontal end caps use flat palette texels, a deliberate uniform-color exception.
cap_records=[r for r in records if abs(r['normal'][1])>.95]
records=[r for r in records if abs(r['normal'][1])<=.95]
records.sort(key=lambda r:(r['h'],r['w']),reverse=True)
shelves=[[N,0,4]]
for r in records:
    for shelf in shelves:
        if shelf[2]>=r['h'] and shelf[0]+r['w']<=N:
            r['x'],r['y']=shelf[0],shelf[1]; shelf[0]+=r['w']; break
    else:
        y=sum(s[2] for s in shelves)
        if y+r['h']>N: raise RuntimeError('Atlas full; reduce density or simplify geometry')
        r['x'],r['y']=0,y; shelves.append([r['w'],y,r['h']])
pixels=[[(44,37,36) for _ in range(N)] for _ in range(N)]
for i,(mat,c) in enumerate(PALETTE.items()):
    for yy in range(4):
        for xx in range(4): pixels[yy][i*4+xx]=c
for r in cap_records:
    slot=list(PALETTE).index(r['material'])*4
    r['face']['uv']={k:[slot+1.5,1.5] for k in r['keys']}
for r in records:
    for key,uv in zip(r['keys'],r['coords']): r['face']['uv'][key]=[round(r['x']+1+uv[0],5),round(r['y']+1+uv[1],5)]
    for yy in range(r['h']):
        for xx in range(r['w']):
            a=(max(1,min(r['w']-2,xx))-.5+r['low'][0])/r['density']
            b=(max(1,min(r['h']-2,yy))-.5+r['low'][1])/r['density']
            p=[r['base'][j]+r['u'][j]*a+r['v'][j]*b for j in range(3)]
            pixels[r['y']+yy][r['x']+xx]=paint(r,p,xx,yy)
def chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
raw=b''.join(b'\0'+bytes(c for p in row for c in p) for row in pixels)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',N,N,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
(ROOT/'dealer-head.png').write_bytes(png)
model['textures']=[body_base['texture'],{'uuid':uid('head-atlas'),'name':'dealer-head.png','id':'0','path':'','folder':'','namespace':'','source':'data:image/png;base64,'+base64.b64encode(png).decode(),'mode':'bitmap','saved':False,'width':N,'height':N,'uv_width':N,'uv_height':N,'render_mode':'default','render_sides':'front','visible':True,'internal':True}]
(ROOT/'dealer.bbmodel').write_text(json.dumps(model,indent=2)+'\n')
triangles=sum(len(f['vertices'])-2 for m in model['elements'] for f in m['faces'].values())
print(f"{len(model['elements'])} meshes, {len(model['groups'])} joint groups, {triangles} triangles, atlas {N}x{N}, occupied height {sum(s[2] for s in shelves)}")
