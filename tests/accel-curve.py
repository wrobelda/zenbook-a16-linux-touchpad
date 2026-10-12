res = 4762/148                     # touchpad units per mm (x axis)
dpi = res*25.4
sf = (0.27350427350427342+1)**2.38*0.95+0.05
def F(v):                           # libinput 1.32 touchpad adaptive factor, v in mm/s
    t = 130.0
    if v < 7: f = min(0.9, 0.1*v+0.3)
    elif v < t: f = 0.9
    else:
        v = min(v, 4*t); f = 0.0025*(v/t)*(v-t)+0.9
    return f*sf*0.2968
def smooth(a,b,x):
    x = min(1,max(0,(x-a)/(b-a))); return x*x*(3-2*x)
def boost(v):                       # +15% in the middle, 1.0 at the ends
    return 1 + 0.15*smooth(10,40,v)*(1-smooth(200,295,v))
step = 0.15
pts=[]
for i in range(64):
    s = i*step                      # units/ms
    v = s*1000/res                  # mm/s
    g = F(v)*1000/dpi               # default gain in custom-filter units
    pts.append(round(s*g*boost(v),3))
print("sf=%.3f"%sf)
for i in (1,2,3,5,10,20,30,40,50,63):
    s=i*step; v=s*1000/res; print("%5.0f mm/s  default gain %.2f  new gain %.2f"%(v,F(v)*1000/dpi,pts[i]/s))
print(pts)
