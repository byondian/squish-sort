from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math
S=3; N=1024*S
PLUM=(59,42,74,255)
def P(v): return int(v*S)
# background: mint to sky, soft glow
bg=Image.new('RGBA',(N,N))
px=bg.load()
top=(190,240,225); bot=(120,196,255)
grad=Image.new('RGB',(1,256))
for y in range(256):
    t=y/255; grad.putpixel((0,y),tuple(int(top[i]+(bot[i]-top[i])*t) for i in range(3)))
bg=grad.resize((N,N)).convert('RGBA').rotate(-25,resample=Image.BICUBIC,expand=False)
bg=grad.resize((N,N)).convert('RGBA')
glow=Image.new('L',(N,N),0); ImageDraw.Draw(glow).ellipse([P(60),P(20),P(620),P(520)],fill=150)
glow=glow.filter(ImageFilter.GaussianBlur(P(120)))
bg=Image.composite(Image.new('RGBA',(N,N),(255,255,255,255)),bg,glow)
ov=Image.new('RGBA',(N,N),(0,0,0,0)); od=ImageDraw.Draw(ov)
for (x,y,r) in [(120,170,26),(640,90,22),(930,860,34),(110,880,44)]:
    od.ellipse([P(x-r),P(y-r),P(x+r),P(y+r)],fill=(255,255,255,95))
bg=Image.alpha_composite(bg,ov)
# body mask: dome + two round ears
mask=Image.new('L',(N,N),0); m=ImageDraw.Draw(mask)
m.ellipse([P(180),P(380),P(844),P(900)],fill=255)
for cx in (318,706): m.ellipse([P(cx-95),P(285),P(cx+95),P(475)],fill=255)
# grow for outline
grow=Image.new('L',(N,N),0); gm=ImageDraw.Draw(grow); T=15
gm.ellipse([P(180-T),P(380-T),P(844+T),P(900+T)],fill=255)
for cx in (318,706): gm.ellipse([P(cx-95-T),P(285-T),P(cx+95+T),P(475+T)],fill=255)
bg.paste(Image.new('RGBA',(N,N),PLUM),(0,0),grow)
# goo: rainbow bands, wavy
goo=Image.new('RGBA',(N,N))
g=ImageDraw.Draw(goo)
bands=[(255,126,182),(255,170,120),(255,216,107),(127,224,196),(124,200,255),(201,167,245)]
y0=270; h=(910-y0)/len(bands)
for i,c in enumerate(bands):
    pts=[]
    for x in range(0,1025,8):
        pts.append((P(x),P(y0+i*h+14*math.sin(x/70+i))))
    pts+= [(P(1024),P(1024)),(0,P(1024))]
    g.polygon(pts,fill=c+(255,))
bg.paste(goo,(0,0),mask)
d=ImageDraw.Draw(bg,'RGBA')
# shine + shade inside body
sh=Image.new('L',(N,N),0); ImageDraw.Draw(sh).ellipse([P(270),P(450),P(500),P(590)],fill=120)
sh=ImageChops.multiply(sh.filter(ImageFilter.GaussianBlur(P(30))),mask)
bg.paste(Image.new('RGBA',(N,N),(255,255,255,255)),(0,0),sh)
sd=Image.new('L',(N,N),0); ImageDraw.Draw(sd).rectangle([0,P(800),N,N],fill=40)
sd=ImageChops.multiply(sd.filter(ImageFilter.GaussianBlur(P(40))),mask)
bg.paste(Image.new('RGBA',(N,N),(59,42,74,255)),(0,0),sd)
# face
for cx in (402,622):
    d.ellipse([P(cx-42),P(620),P(cx+42),P(704)],fill=PLUM)
    d.ellipse([P(cx-22),P(634),P(cx+4),P(660)],fill=(255,255,255,255))
for cx in (330,694):
    d.ellipse([P(cx-48),P(712),P(cx+48),P(766)],fill=(255,120,150,170))
d.arc([P(462),P(676),P(562),P(756)],20,160,fill=PLUM,width=P(22))
for (x,y) in [(472,729),(552,729)]: d.ellipse([P(x-11),P(y-11),P(x+11),P(y+11)],fill=PLUM)
# sparkles
def star(cx,cy,r,fill):
    pts=[]
    for k in range(8):
        a=k*math.pi/4-math.pi/2; rr=r if k%2==0 else r*0.36
        pts.append((P(cx+rr*math.cos(a)),P(cy+rr*math.sin(a))))
    d.polygon(pts,fill=fill); d.line(pts+[pts[0]],fill=PLUM,width=P(16),joint='curve')
    for p in pts: d.ellipse([p[0]-P(8),p[1]-P(8),p[0]+P(8),p[1]+P(8)],fill=PLUM)
# wand
d.line([(P(800),P(300)),(P(895),P(205))],fill=PLUM,width=P(40))
d.line([(P(800),P(300)),(P(895),P(205))],fill=(255,255,255,255),width=P(14))
for e in [(800,300),]: d.ellipse([P(e[0]-20),P(e[1]-20),P(e[0]+20),P(e[1]+20)],fill=PLUM)
star(900,190,84,(255,216,107,255))
star(170,330,52,(255,255,255,255))
star(560,170,40,(255,255,255,255))
out=bg.convert('RGB').resize((1024,1024),Image.LANCZOS)
out.save('icon-workshop-1024.png')
