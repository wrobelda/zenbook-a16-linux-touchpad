import sys, statistics as st
rows=[]
for line in open(sys.argv[1]):
    t,r,v=line.rstrip("\n").split("|")
    P=lambda s,n: {int(a.split(":")[0]):tuple(float(x) if x not in("nil","") else None for x in a.split(":")[1:3]) for a in s.split()} if s else {}
    rows.append((float(t),P(r,2),P(v,3)))
# find 2-finger episodes (raw) and the frame where the count first drops below 2
ep=[]; start=None
for i,(t,r,v) in enumerate(rows):
    if len(r)>=2 and start is None: start=i
    if start is not None and len(r)<2:
        ep.append((start,i)); start=None
def motion(rows, i0, i1, key, slots):
    tot={s:0.0 for s in slots}; mx={s:0.0 for s in slots}
    for k in range(i0+1,i1+1):
        a=rows[k-1][key]; b=rows[k][key]
        for s in slots:
            if s in a and s in b and None not in a[s] and None not in b[s]:
                d=((b[s][0]-a[s][0])**2+(b[s][1]-a[s][1])**2)**.5/32
                tot[s]+=d; mx[s]=max(mx[s],d)
    return tot,mx
print("ep  start_s  dur_ms  lift_gap_ms | raw mm last100ms (per finger) | fwd mm last100ms | max fwd step mm last100 | median fwd step mm during scroll")
for n,(a,b) in enumerate(ep):
    t0,t1=rows[a][0],rows[b][0]
    if t1-t0<150: continue
    slots=sorted(rows[b-1][1].keys())
    # time between first finger lifting and the last finger lifting
    j=b
    while j<len(rows) and len(rows[j][1])>0: j+=1
    gap=rows[min(j,len(rows)-1)][0]-t1
    k=b
    while k>a and rows[k][0]>t1-100: k-=1
    rt,_=motion(rows,k,b,1,slots); vt,vm=motion(rows,k,b,2,slots)
    steps=[]
    for q in range(a+1,k):
        A=rows[q-1][2];B=rows[q][2]
        for s in slots:
            if s in A and s in B and None not in A[s] and None not in B[s]:
                d=((B[s][0]-A[s][0])**2+(B[s][1]-A[s][1])**2)**.5/32
                if d>0: steps.append(d)
    med=st.median(steps) if steps else 0
    f=lambda d:" ".join("%.2f"%d[s] for s in slots)
    print(f"{n:2d} {t0/1000:7.2f} {t1-t0:7.0f} {gap:8.1f}   | {f(rt):14s} | {f(vt):14s} | {f(vm):12s} | {med:.3f}")
