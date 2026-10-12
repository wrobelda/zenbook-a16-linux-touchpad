import sys
rows=[]
for line in open(sys.argv[1]):
    t,r,v=line.rstrip("\n").split("|")
    P=lambda s: {int(a.split(":")[0]):tuple(float(x) if x not in("nil","") else None for x in a.split(":")[1:3]) for a in s.split()} if s else {}
    rows.append((float(t),P(r)))
ep=[];start=None
for i,(t,r) in enumerate(rows):
    if len(r)>=2 and start is None: start=i
    if start is not None and len(r)<2: ep.append((start,i)); start=None
def avg_y(r): ys=[p[1] for p in r.values() if p[1] is not None]; return sum(ys)/len(ys) if ys else None
def vel(i0,i1):  # mean vertical velocity of the finger average, mm/s
    a,b=rows[i0],rows[i1]
    if set(a[1])!=set(b[1]) or b[0]==a[0]: return None
    return (avg_y(b[1])-avg_y(a[1]))/32/((b[0]-a[0])/1000)
print("ep  scroll_v(mm/s, 100..25ms before lift)  final_v(last 25ms)  ratio  same_dir")
n_spike=0; n=0
for k,(a,b) in enumerate(ep):
    if rows[b][0]-rows[a][0]<150: continue
    t1=rows[b-1][0]
    i25=b-1
    while i25>a and rows[i25][0]>t1-25: i25-=1
    i100=i25
    while i100>a and rows[i100][0]>t1-100: i100-=1
    v1=vel(i100,i25); v2=vel(i25,b-1)
    if v1 is None or v2 is None: continue
    n+=1
    ratio = abs(v2)/abs(v1) if abs(v1)>0.5 else float('inf') if abs(v2)>0.5 else 1
    same = (v1*v2>0)
    if ratio>1.5 and abs(v2)>5: n_spike+=1
    print(f"{k:2d}  {v1:8.1f}  {v2:8.1f}  {ratio:6.2f}  {same}")
print(f"{n_spike} of {n} lifts: last-25ms speed > 1.5x the scroll speed (and > 5 mm/s)")
