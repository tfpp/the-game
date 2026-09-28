"""Original low-poly salon furniture and adult patrons. Run with Blender in background.
Coordinates are metres, Godot Y up. Shared vertex colours keep each prop to two draws.
"""
import sys
import math
from pathlib import Path
import bpy
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent))
import build_models as b

for name, color in {
    'Felt': (.015, .19, .115), 'Suit': (.036, .045, .060),
    'Shirt': (.70, .64, .49), 'Skin': (.51, .29, .16),
    'Hair': (.035, .021, .014), 'Red': (.38, .025, .035),
    'White': (.84, .78, .62), 'Blue': (.018, .08, .29),
    'Wall': (.031, .029, .027), 'Ceiling': (.16, .12, .072),
    'Leather': (.055, .012, .017), 'Lapel': (.058, .071, .086),
    'Eye': (.46, .40, .32), 'Lip': (.23, .09, .067),
    'Bottle': (.035, .13, .052), 'Amber': (.42, .18, .025),
}.items():
    b.MATS[name] = b.material(name, color)


def mesh(name, vertices, faces, material):
    data = bpy.data.meshes.new(name)
    data.from_pydata([b.xyz(p) for p in vertices], [], [tuple(reversed(face)) for face in faces])
    data.update()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    b.finish(obj, name, material)
    return obj


def loft(name, rings, material, sides=8):
    vertices = [(cx + rx*math.cos(i*math.tau/sides), y,
                 cz + rz*math.sin(i*math.tau/sides))
                for y, cx, cz, rx, rz in rings for i in range(sides)]
    faces = [tuple(reversed(range(sides))), tuple((len(rings)-1)*sides+i for i in range(sides))]
    for j in range(len(rings)-1):
        for i in range(sides):
            a, n = j*sides+i, j*sides+(i+1)%sides
            faces.append((a,n,n+sides,a+sides))
    return mesh(name, vertices, faces, material)


def smooth(obj):
    # Smooth only the authored curved parts; hard trim and seams stay crisp.
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def surface(name, loops, material, caps=False, soft=False):
    """Connected edge loops, with outward normals in Godot's Y-up coordinates."""
    count = len(loops[0])
    verts = [point for loop in loops for point in loop]
    faces = []
    for row in range(len(loops)-1):
        for i in range(count):
            j=(i+1)%count
            faces.append((row*count+i,row*count+j,(row+1)*count+j,(row+1)*count+i))
    if caps:
        faces += [tuple(reversed(range(count))),tuple(range((len(loops)-1)*count,len(verts)))]
    obj=mesh(name,verts,faces,material)
    return smooth(obj) if soft else obj


def sweep(name, rings, material, sides=8, soft=True):
    """A shaped limb/wood member, with continuous cross-sections through each bend."""
    from mathutils import Vector
    loops=[]
    for i,(center,width,depth) in enumerate(rings):
        p=Vector(center)
        tangent=Vector(rings[min(i+1,len(rings)-1)][0])-Vector(rings[max(0,i-1)][0])
        tangent.normalize()
        across=Vector((1,0,0))
        if abs(tangent.dot(across))>.9:
            across=Vector((0,0,1))
        across=(across-tangent*across.dot(tangent)).normalized()
        other=across.cross(tangent).normalized()
        loops.append([tuple(p+across*width*math.cos(j*math.tau/sides)+other*depth*math.sin(j*math.tau/sides)) for j in range(sides)])
    return surface(name,loops,material,True,soft)


def oval_loops(name, profiles, material, sides=16, soft=True):
    return surface(name,[[(cx+rx*math.cos(i*math.tau/sides),y,cz+rz*math.sin(i*math.tau/sides)) for i in range(sides)] for y,cx,cz,rx,rz in profiles],material,True,soft)


def chair(p=(0,0,0), angle=0):
    before=set(bpy.context.scene.objects)
    # Upholstery swells into a rounded crown instead of a rectangular slab.
    oval_loops('Sculpted seat',[(.46,0,0,.24,.245),(.49,0,0,.275,.265),(.55,0,.005,.265,.255),(.575,0,.01,.225,.215)],'Velvet',16)
    oval_loops('Seat apron',[(.405,0,-.01,.225,.22),(.435,0,0,.265,.25),(.48,0,0,.265,.25)],'Walnut',16,False)
    # Bowed back: cross-section follows the sitter, narrower waist and arched crest.
    loops=[]
    for y,width,zc,depth in [(.56,.20,-.20,.042),(.72,.245,-.235,.052),(1.02,.26,-.285,.055),(1.20,.23,-.30,.050),(1.255,.16,-.30,.028)]:
        loops.append([(width*math.cos(i*math.tau/12),y,zc+depth*math.sin(i*math.tau/12)+.10*math.cos(i*math.tau/12)**2) for i in range(12)])
    surface('Contoured upholstered back',loops,'Velvet',True,True)
    for side in [-1,1]:
        sweep('Bent walnut rear stile',[((side*.215,.04,-.27),.025,.025),((side*.20,.45,-.20),.028,.029),((side*.248,.78,-.19),.027,.028),((side*.27,1.04,-.205),.026,.028),((side*.20,1.265,-.265),.029,.026)],'Walnut',6)
        sweep('Tapered front leg',[((side*.24,.045,.24),.018,.023),((side*.205,.30,.18),.025,.025),((side*.22,.46,.18),.030,.030)],'Walnut',6)
        sweep('Brass leg shoe',[((side*.24,.015,.24),.021,.026),((side*.235,.10,.226),.022,.027)],'Brass',6)
    # One arched crest follows the padded back, rather than a chunky gold block.
    sweep('Carved chair crest',[((-.21,1.245,-.26),.025,.026),((-.12,1.30,-.30),.028,.027),((0,1.315,-.315),.030,.028),((.12,1.30,-.30),.028,.027),((.21,1.245,-.26),.025,.026)],'Walnut',6)
    transform_new(before,p,angle)


def transform_new(before, position, angle):
    from mathutils import Matrix, Vector
    transform = Matrix.Translation(Vector(b.xyz(position))) @ Matrix.Rotation(angle,4,'Z')
    for obj in set(bpy.context.scene.objects)-before:
        obj.matrix_world = transform @ obj.matrix_world


def table_outline(scale=1):
    # Curved player edge and a recessed dealer station are one continuous outline.
    points=[(math.cos(i*math.pi/32)*2.04,math.sin(i*math.pi/32)*1.18) for i in range(33)]
    points += [(-.80,0),(-.59,.135),(-.38,.19),(.38,.19),(.59,.135),(.80,0)]
    return [(x*scale,.45+(z-.45)*scale) for x,z in points]


def table_band(name, profiles, mat, caps=False, soft=False):
    return surface(name,[[(x,y,z) for x,z in table_outline(scale)] for y,scale in profiles],mat,caps,soft)


def card(x,z,angle,red):
    before=set(bpy.context.scene.objects)
    # Rounded card silhouette; printed markings stay on the card's own transform.
    points=[(-.064,-.098),(.064,-.098),(.070,-.091),(.070,.091),(.064,.098),(-.064,.098),(-.070,.091),(-.070,-.091)]
    surface('Card stock',[[(px,.947,pz) for px,pz in points],[(px,.952,pz) for px,pz in points]],'White',True)
    pip='Red' if red else 'Dark'
    for px,pz in [(-.045,-.069),(.045,.069),(0,0)]:
        # Flat diamond print avoids projecting tiny cubes off the paper.
        mesh('Printed card suit',[(px,.953,pz-.016),(px+.012,.953,pz),(px,.953,pz+.016),(px-.012,.953,pz)],[(0,1,2,3)],pip)
    transform_new(before,(x,0,z),angle)


def chip(x,y,z,mat):
    # One twelve-sided mesh, with coloured edge inserts assigned by face.
    obj=oval_loops('Casino chip',[(y-.010,x,z,.060,.060),(y-.007,x,z,.066,.066),(y+.007,x,z,.066,.066),(y+.010,x,z,.060,.060)],mat,12,False)
    # White inserts are surface polygons, never intersecting box attachments.
    for i in [0,3,6,9]:
        a,c=i*math.tau/12,(i+1)*math.tau/12
        mesh('Chip edge insert',[(x+math.cos(a)*.0663,y-.007,z+math.sin(a)*.0663),(x+math.cos(c)*.0663,y-.007,z+math.sin(c)*.0663),(x+math.cos(c)*.0663,y+.007,z+math.sin(c)*.0663),(x+math.cos(a)*.0663,y+.007,z+math.sin(a)*.0663)],[(0,1,2,3)],'White')


def table():
    b.clear()
    # Separate undercut apron, timber deck, recessed baize and a rolled leather rail.
    table_band('Curved walnut apron',[(.68,.90),(.73,.97),(.855,.985)],'Walnut',False)
    table_band('Table deck',[(.855,.99),(.895,1.015),(.920,1.01)],'Walnut',True)
    table_band('Fine brass reveal',[(.886,1.017),(.899,1.017)],'Brass')
    table_band('Padded leather rail',[(.916,.995),(.945,1.023),(.992,1.010),(1.013,.979),(1.008,.944),(.978,.913),(.944,.91)],'Leather',False,True)
    table_band('Rail inner piping',[(.950,.909),(.955,.907)],'Brass')
    table_band('Inset emerald baize',[(.931,.908),(.942,.908)],'Felt',True)
    # Two shaped pedestal bases leave believable knee room beneath the apron.
    for x in [-1.1,1.1]:
        oval_loops('Pedestal foot',[(.025,x,.48,.42,.30),(.07,x,.48,.48,.32),(.115,x,.48,.36,.24)],'Walnut',12)
        oval_loops('Turned pedestal',[(.10,x,.48,.17,.14),(.18,x,.48,.14,.12),(.42,x,.48,.11,.10),(.64,x,.48,.16,.13),(.84,x,.48,.27,.20)],'Walnut',12)
        oval_loops('Pedestal brass collar',[(.15,x,.48,.145,.125),(.17,x,.48,.145,.125)],'Brass',12,False)
    # Continuous printed arc, raised only a millimetre above the fabric.
    arc=[]
    for scale in [1,1.015]:
        arc.append([(math.cos(i*math.pi/24)*1.40*scale,.944,math.sin(i*math.pi/24)*.78*scale+.10) for i in range(25)])
    mesh('Printed betting arc',arc[0]+arc[1],[(i,i+1,i+26,i+25) for i in range(24)],'Brass')
    for j in range(5):
        a=(j+.5)*math.pi/5
        x,z=math.cos(a)*1.18,math.sin(a)*.62+.10
        for k in range(2):
            card(x+k*.095,z+k*.035,-.16+k*.25,j%2==0)
        for k in range(3):
            chip(x,.957+k*.021,z+.20,'Red' if j%2 else 'Blue')
    # Recessed tray, chip rows and a compact card shoe at the dealer station.
    b.box('Chip tray recess',(0,.945,.30),(1.12,.018,.18),'Dark')
    for i in range(9):
        chip(-.47+i*.116,.957,.30,['Red','White','Blue'][i%3])
    for j in range(3):
        a=(j+1)*math.pi/4
        chair((math.cos(a)*2.35,0,math.sin(a)*1.55),math.pi/2+a)
    b.export('salon_card_table')


def face_patch(name,points,material):
    # mesh() reverses its authoring winding; front patches must face +Z.
    a,c,d=points[:3]
    normal_z=(c[0]-a[0])*(d[1]-a[1])-(c[1]-a[1])*(d[0]-a[0])
    if normal_z > 0:
        points=list(reversed(points))
    return mesh(name,points,[tuple(range(len(points)))],material)


def head(shoulder,forward,woman):
    # Cheek, jaw, temple and brow loops. The nose is part of the face surface.
    profiles=[(.085,.054,.062,.024),(.118,.080,.073,.015),(.170,.098,.087,.004),(.217,.105,.090,0),(.260,.101,.083,-.004),(.306,.094,.079,-.012),(.344,.068,.056,-.018),(.356,.023,.020,-.020)]
    loops=[]
    for y,rx,rz,zc in profiles:
        row=[]
        for i in range(16):
            a=i*math.tau/16
            front=max(0,math.sin(a))
            nose=(.041 if .165<y<.22 else .012 if .115<y<.265 else 0)*front**18
            row.append((rx*math.cos(a),shoulder+y,forward+zc+rz*math.sin(a)+nose))
        loops.append(row)
    surface('Sculpted face',loops,'Skin',True,True)
    # Fit printed facial details to the actual low-poly face, including the nose.
    # A fixed Z plane buries the eyes and mouth as the cheek profile changes.
    from mathutils.bvhtree import BVHTree
    vertices=[point for row in loops for point in row]
    faces=[(row*16+i,row*16+(i+1)%16,(row+1)*16+(i+1)%16,(row+1)*16+i)
           for row in range(len(loops)-1) for i in range(16)]
    face_tree=BVHTree.FromPolygons(vertices,faces)
    def detail(name,points,material,offset=.003):
        fitted=[]
        for x,y in points:
            hit,_,_,_=face_tree.ray_cast((x,shoulder+y,forward+1),(0,0,-1))
            assert hit is not None, f'{name} misses the face'
            fitted.append((x,shoulder+y,hit.z+offset))
        face_patch(name,fitted,material)
    for side in [-1,1]:
        # Folded ears are little closed volumes with a darker concha.
        oval_loops('Ear',[(shoulder+.167,side*.103,forward-.004,.015,.021),(shoulder+.195,side*.113,forward-.005,.023,.019),(shoulder+.238,side*.106,forward-.009,.014,.015)],'Skin',8)
        x=side*.043
        # Small inset eyes and tapered eyebrows, fitted to the brow rather than cubes.
        detail('Eye white',[(x-.016,.239),(x+.015,.240),(x+.013,.248),(x-.013,.248)],'Eye')
        detail('Iris',[(x-.005,.239),(x+.006,.239),(x+.006,.247),(x-.005,.247)],'Hair',.005)
        detail('Eyebrow',[(x-.020,.257),(x+.018,.259),(x+.013,.265),(x-.015,.264)],'Hair')
    detail('Mouth',[(-.023,.142),(.023,.142),(.017,.147),(-.013,.148)],'Lip',.004)
    loops=[]
    for level in range(3):
        row=[]
        for i in range(16):
            a=i*math.tau/16
            front=max(0,math.sin(a))
            if level==0:
                y=.12+.16*front if woman else .22+.07*front
                rx,rz=.116,.116
            elif level==1:
                y=.342+.006*math.cos(a)
                rx,rz=.099,.098
            else:
                y=.378+.005*math.cos(a)
                rx,rz=.040,.040
            row.append((rx*math.cos(a),shoulder+y,forward-.010+rz*math.sin(a)))
        loops.append(row)
    surface('Shaped swept hair',loops,'Hair',True,True)


def person(name, dealer=False, seated=False, woman=False):
    b.clear()
    hip=.61 if seated else .96
    shoulder=hip+.46
    forward=.055 if seated else 0
    suit='Red' if woman else 'Suit'
    torso='Dark' if dealer else suit
    # Fitted waist, chest, sloping shoulders and neck opening form one mesh.
    oval_loops('Tailored torso',[(hip-.08,0,0,.18,.115),(hip+.06,0,.008,.19,.122),(hip+.19,0,forward*.45,.157,.115),(hip+.32,0,forward*.8,.21,.13),(shoulder-.025,0,forward,.232,.118),(shoulder+.024,0,forward,.145,.090)],torso,12)
    if woman:
        oval_loops('Draped skirt',[(hip-.28,0,.19 if seated else 0,.245,.22),(hip-.12,0,.07,.215,.155),(hip+.075,0,.008,.177,.12)],'Red',12)
    oval_loops('Neck',[(shoulder+.012,0,forward,.064,.06),(shoulder+.105,0,forward+.008,.056,.055)],'Skin',10)
    head(shoulder,forward,woman)
    if not woman:
        # Shirt, folded collar and lapels follow the chest and lie flush on the coat.
        face_patch('Shirt front',[(-.070,shoulder+.005,forward+0.146),(.070,shoulder+.005,forward+0.146),(.054,hip+.25,forward+0.146),(-.054,hip+.25,forward+0.146)],'Shirt')
        for side in [-1,1]:
            face_patch('Folded shirt collar',[(side*.068,shoulder+.020,forward+0.152),(side*.008,shoulder-.025,forward+0.152),(side*.075,shoulder-.078,forward+0.152),(side*.096,shoulder-.016,forward+0.152)],'White')
            face_patch('Notched lapel',[(side*.10,shoulder-.01,forward+0.157),(side*.18,shoulder-.10,forward+0.157),(side*.075,hip+.24,forward+0.157),(side*.04,shoulder-.075,forward+0.157)],'Lapel' if not dealer else 'Dark')
        if dealer:
            for side in [-1,1]:
                face_patch('Bow tie',[(0,shoulder-.048,forward+0.164),(side*.059,shoulder-.027,forward+0.164),(side*.053,shoulder-.077,forward+0.164)],'Red')
        else:
            face_patch('Silk tie',[(-.017,shoulder-.043,forward+0.163),(.017,shoulder-.043,forward+0.163),(.022,hip+.27,forward+0.163),(0,hip+.23,forward+0.163),(-.022,hip+.27,forward+0.163)],'Dark')
    for side in [-1,1]:
        sleeve='Skin' if woman else ('Shirt' if dealer else suit)
        elbow=(side*.295,shoulder-.245,.18 if seated else .12 if dealer else -.015)
        wrist=(side*.30,.977,.63) if seated else ((side*.32,.998,.43) if dealer else (side*.255,hip-.10,.075))
        sweep('Anatomical sleeve',[((side*.195,shoulder-.012,forward),.085,.085),((side*.259,shoulder-.095,forward+.01),.075,.073),(elbow,.062,.061),(((elbow[0]+wrist[0])*.5,(elbow[1]+wrist[1])*.5,(elbow[2]+wrist[2])*.5),.057,.050),(wrist,.042,.035)],sleeve,8)
        finger=(wrist[0]-side*.012,wrist[1]-.022,wrist[2]+.13)
        sweep('Modelled palm and fingers',[(wrist,.040,.025),((wrist[0],wrist[1]-.005,wrist[2]+.065),.045,.024),(finger,.034,.014)],'Skin',8)
        sweep('Thumb',[((wrist[0]-side*.032,wrist[1]-.004,wrist[2]+.04),.018,.015),((wrist[0]-side*.06,wrist[1]-.016,wrist[2]+.086),.013,.011)],'Skin',6)
        knee=(side*.12,.37,.38) if seated else (side*.115,.49,.025)
        ankle=(side*.12,.105,.39) if seated else (side*.12,.105,.045)
        sweep('Shaped leg',[((side*.105,hip-.03,.045),.102,.095),((side*.12,(hip+knee[1])*.5,.21 if seated else .012),.094,.086),(knee,.078,.070),((side*.12,.24,ankle[2]),.064,.060),(ankle,.048,.05)],'Skin' if woman else suit,8)
        oval_loops('Sculpted leather shoe',[(.027,ankle[0],ankle[2]+.055,.075,.155),(.065,ankle[0],ankle[2]+.057,.078,.155),(.110,ankle[0],ankle[2]+.013,.061,.091),(.135,ankle[0],ankle[2]-.005,.045,.05)],'Dark',12)
    b.export(name)


def bar():
    b.clear()
    b.box('Back wall',(0,1.8,-.6),(7,3.6,.2),'Wall')
    for x in [-3.4,3.4]:
        b.box('Bar pilaster',(x,1.8,-.45),(.22,3.6,.34),'Walnut')
    for y in [.72,1.45,2.18,2.91]:
        b.box('Bottle shelf',(0,y,-.24),(6.6,.08,.48),'Walnut')
        b.box('Shelf amber strip',(0,y+.05,-.47),(6.4,.03,.02),'Glow')
        for i in range(17):
            x=-3+i*.37
            height=.27+(i%3)*.07
            b.cylinder('Bottle',(x,y+height/2+.05,-.22),.063,height,'Bottle' if i%3 else 'Amber')
            b.cylinder('Neck',(x,y+height+.09,-.22),.025,.10,'Bottle')
            b.box('Bottle label',(x,y+.19,-.153),(.07,.09,.008),'Ivory')
    b.box('Bar front',(0,.49,1.1),(7,.98,.40),'Walnut')
    b.box('Counter top',(0,1.06,1.0),(7.3,.14,.85),'Walnut')
    b.box('Counter brass edge',(0,1.075,1.43),(7.3,.065,.045),'Brass')
    b.rod('Foot rail',(-3.4,.18,1.55),(3.4,.18,1.55),.035,'Brass')
    for x in [-3,-1.5,0,1.5,3]:
        b.box('Panel reveal',(x,.49,1.32),(.035,.80,.03),'Brass')
        b.cylinder('Counter glass',(x,1.19,1.0),.055,.16,'Ivory')
    b.export('salon_bar')


def architecture():
    b.clear()
    # Gallery back and side panelling leave both existing central ramps open.
    for side in [-1,1]:
        x=side*14.4
        b.box('Dark wall field',(x,2.1,0),(.18,7.2,23.8),'Wall')
        b.box('Walnut dado',(x-side*.12,-.65,0),(.12,1.7,23.8),'Walnut')
        for y in [.23,3.15,5.65]:
            b.box('Wall string course',(x-side*.16,y,0),(.14,.085,24),'Brass')
        for z in [-10,-5,0,5,10]:
            b.box('Walnut pilaster',(x-side*.25,2.1,z),(.42,7.2,.52),'Walnut')
            for y in [-1.25,.26,3.20,5.6]:
                b.box('Capital moulding',(x-side*.25,y,z),(.52,.14,.64),'Brass')
    for z in [-3,4]:
        b.box('Salon column',(-8.8,2.1,z),(.72,7.2,.72),'Walnut')
        for y in [-1.25,.25,3.2,5.6]:
            b.box('Salon column capital',(-8.8,y,z),(.86,.13,.86),'Brass')
    b.box('Gallery back',(0,4.7,-11.85),(28.8,3.3,.2),'Wall')
    b.box('Gallery front fascia',(0,2.92,-8.1),(28.8,.38,.24),'Walnut')
    b.box('Gallery gold reveal',(0,3.05,-7.96),(28.8,.07,.05),'Brass')
    for x in [-10,-3.8,3.8,10]:
        b.box('Gallery supporting column',(x,2.1,-8.1),(.55,7.2,.55),'Walnut')
        for y in [-1.2,2.8,5.6]:
            b.box('Column capital',(x,y,-8.1),(.68,.17,.68),'Brass')
    for x in [-10.5,-7,-3.5,0,3.5,7,10.5,14]:
        b.rod('Gallery baluster',(x,3.2,-8),(x,4.17,-8),.045,'Brass')
    b.box('Gallery handrail',(.5,4.2,-8),(27.8,.12,.12),'Walnut')
    for x in [i*.42-11.1 for i in range(60)]:
        b.rod('Gallery spindle',(x,3.2,-8),(x,4.13,-8),.023,'Walnut')
    # Stair tread faces over a smooth walking collision ramp.
    for i in range(24):
        y=-1.5+(i+1)*4.7/24
        z=4-(i+.5)*12/24
        b.box('Stair tread',(-12.8,y-.06,z),(1.8,.12,.50),'Walnut')
        b.box('Stair brass nosing',(-12.8,y+.002,z+.24),(1.8,.022,.028),'Brass')
    for x in [-13.76,-11.84]:
        b.rod('Stair handrail',(x,-.52,4),(x,4.18,-8),.045,'Walnut')
        for i in range(13):
            y=-1.5+i*4.7/12
            b.rod('Stair spindle',(x,y,4-i),(x,y+.98,4-i),.025,'Brass')
    b.export('salon_architecture')


def sconce():
    b.clear()
    b.box('Backplate',(0,0,0),(.24,.60,.04),'Brass')
    for x in [-.12,.12]:
        b.rod('Lamp arm',(0,-.18,.04),(x,-.09,.21),.022,'Brass')
        b.cylinder('Amber shade',(x,.06,.21),.07,.29,'Glow',top=.095)
        b.cylinder('Shade crown',(x,.225,.21),.098,.04,'Brass')
    b.export('salon_sconce')

if __name__ == '__main__':
    table()
    person('salon_dealer',dealer=True)
    person('salon_guest')
    person('salon_seated',seated=True)
    person('salon_lady',woman=True,seated=True)
    bar()
    architecture()
    sconce()
