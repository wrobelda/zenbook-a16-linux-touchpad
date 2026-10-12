-- right thumb zone enabled (45 mm): mirror of the left one, never revealed
dofile(os.getenv("T").."/harness2.lua")
local S = os.getenv("S")
H.load({S.."/20-thumb-zone.lua"})
local ms = 1000
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",1),E("ABS_MT_POSITION_X",4000),E("ABS_MT_POSITION_Y",200)}, K(1)), 0)
H.check("right thumb (125 mm, 6 mm) hidden", H.count(), 0)
H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",2),E("ABS_MT_POSITION_X",2000),E("ABS_MT_POSITION_Y",1800),
            E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",3),E("ABS_MT_POSITION_X",1400),E("ABS_MT_POSITION_Y",1800)}, K(3)), 10*ms)
H.check("right thumb + two fingers: thumb stays hidden (2 visible)", H.count(), 2)
H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1)}, K(1)), 20*ms)
H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_Y",1000)}, 30*ms)
H.check("right thumb moved 5 mm below the zone: visible", H.count(), 1)
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)), 40*ms)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",4),E("ABS_MT_POSITION_X",3200),E("ABS_MT_POSITION_Y",200)}, K(1)), 50*ms)
H.check("top edge at 100 mm (outside both zones): visible", H.count(), 1)
print(H.ok and "ALL PASS" or "SOME FAILED")
