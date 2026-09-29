"""Paint the original tintable avatar textures. Requires Pillow."""
from pathlib import Path
from math import cos, sin, pi
import random
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
TEXTURES = ROOT / "textures"
TEXTURES.mkdir(exist_ok=True)

# Painted, tintable low resolution textures, with restrained grain and soft shading.
def painted(name, fn, detail=None):
    size=128
    rng=random.Random(14)
    image=Image.new('RGB',(size,size))
    for y in range(size):
        for x in range(size):
            value=fn(x/127,y/127)+rng.uniform(-5,5)
            image.putpixel((x,y),tuple(max(0,min(255,int(v))) for v in ((value,)*3)))
    if detail:
        detail(image)
    image.save(TEXTURES/(name+'.png'))

painted('skin', lambda u,v: 226 + 12*cos((u-.5)*2*pi) - 10*abs(v-.5))
painted('fabric',lambda u,v: 214 + 18*cos(u*6*pi)*sin(v*4*pi) - 20*abs(sin(v*9*pi))*abs(u-.5),lambda im: ImageDraw.Draw(im).line([(1,0),(1,127),(126,127),(126,0)],fill=(137,137,137),width=1))
painted('trousers',lambda u,v: 208 + 19*cos(u*4*pi) - 23*abs(sin(v*5*pi))*(.4+abs(u-.5)),lambda im: ImageDraw.Draw(im).line([(64,0),(64,127)],fill=(167,167,167),width=1))
painted('hair',lambda u,v: 171 + 40*cos(u*32*pi)+16*cos(u*11*pi+v*2))
painted('gear',lambda u,v: 188 - 30*abs(sin(v*5*pi)) + 9*cos(u*12*pi),lambda im: ImageDraw.Draw(im).rectangle((12,20,115,108),outline=(110,110,110),width=2))
painted('leather',lambda u,v: 180+14*cos(u*3*pi)-27*sin(v*3*pi)**2)
# Face artwork is painted into the UV mesh. No pixel eyes or detached block nose.
def face_detail(im):
    layer=Image.new('RGBA',im.size,(0,0,0,0));d=ImageDraw.Draw(layer)
    for x in [34,94]:
        d.ellipse((x-14,44,x+14,59),fill=(82,82,82,115))
        d.line([(x-12,45),(x,42),(x+10,45)],fill=(61,61,61,205),width=3)
        d.ellipse((x-10,49,x+10,54),fill=(182,182,182,235))
        d.line([(x-10,49),(x+10,49)],fill=(67,67,67,215),width=1)
    d.line([(62,63),(59,79),(63,82),(70,80)],fill=(124,124,124,115),width=2)
    d.ellipse((57,78,62,81),fill=(95,95,95,165));d.ellipse((67,78,71,81),fill=(95,95,95,165))
    d.line([(50,98),(61,97),(69,97),(78,98)],fill=(98,98,98,210),width=2)
    d.line([(54,101),(72,101)],fill=(186,186,186,220),width=2)
    d.ellipse((49,110,79,116),fill=(136,136,136,60))
    layer=layer.filter(ImageFilter.GaussianBlur(.65))
    im.paste(layer,(0,0),layer)
painted('face',lambda u,v: 228 + 10*cos((u-.5)*pi) - 12*abs(u-.5) - 15*max(0,v-.65),face_detail)
print('Painted seven original 128px avatar textures')
