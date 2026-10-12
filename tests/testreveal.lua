dofile(os.getenv("T").."/harness2.lua")
local S = os.getenv("S")
H.load({S.."/20-thumb-zone.lua", S.."/30-rest-deadzone.lua", S.."/35-lift-trim.lua", S.."/40-scroll-scale.lua"})
local ms = 1000
-- 1. right-half strip touch + index finger: hidden (two touches)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",1),E("ABS_MT_POSITION_X",3400),E("ABS_MT_POSITION_Y",200)}, K(1)), 0)
H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",2),E("ABS_MT_POSITION_X",3000),E("ABS_MT_POSITION_Y",2000)}, K(2)), 10*ms)
H.check("right-half top touch + index: both visible (no strip there)", H.count(), 2)
H.check("right-half top touch + index: finger-count keys 2", H.keycount(), 2)
-- 2. a third finger lands: the hidden thumb is revealed, libinput sees 3
H.send(cat({E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",3),E("ABS_MT_POSITION_X",2000),E("ABS_MT_POSITION_Y",1500)}, K(3)), 20*ms)
H.check("third finger: libinput sees 3 touches", H.count(), 3)
H.check("third finger: finger-count keys 3", H.keycount(), 3)
H.check("top-right touch at its position", H.li.touches[0] and H.li.touches[0].y, 200)
H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_Y",300),E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_Y",2100),E("ABS_MT_SLOT",2),E("ABS_MT_POSITION_Y",1600)}, 30*ms)
H.check("three-finger swipe motion not delayed (plugin 35 exempt)", H.li.touches[2].y, 1600)
H.check("three-finger swipe motion not scaled (SWIPE_SCALE 1.0)", H.li.touches[1].y, 2100)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 100*ms)
H.check("all lifted", H.count(), 0)
-- 3. three fingers landing together, top one in the strip: all three visible at once
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",4),E("ABS_MT_POSITION_X",3300),E("ABS_MT_POSITION_Y",750),
            E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",5),E("ABS_MT_POSITION_X",2700),E("ABS_MT_POSITION_Y",1000),
            E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",6),E("ABS_MT_POSITION_X",2100),E("ABS_MT_POSITION_Y",1170)}, K(3)), 200*ms)
H.check("three land together with top one in strip: 3 visible", H.count(), 3)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 300*ms)
-- 4. thumb in strip alone: still hidden; after the others lift, a new 2-finger pair keeps thumb hidden
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",7),E("ABS_MT_POSITION_X",1000),E("ABS_MT_POSITION_Y",200)}, K(1)), 400*ms)
H.check("thumb alone hidden", H.count(), 0)
print(H.ok and "ALL PASS" or "SOME FAILED")
-- 5. left thumb resting in the LEFT half of the top strip + right-hand two-finger scroll: thumb stays hidden
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)), 500*ms)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",8),E("ABS_MT_POSITION_X",1000),E("ABS_MT_POSITION_Y",200)}, K(1)), 600*ms)
H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",9),E("ABS_MT_POSITION_X",3000),E("ABS_MT_POSITION_Y",1800),
            E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",10),E("ABS_MT_POSITION_X",3500),E("ABS_MT_POSITION_Y",1800)}, K(3)), 610*ms)
H.check("left thumb + two right fingers: libinput sees 2 touches", H.count(), 2)
H.check("left thumb + two right fingers: finger-count keys 2", H.keycount(), 2)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 700*ms)
-- 6. right-half strip touch + two fingers: revealed (right-hand swipe)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",11),E("ABS_MT_POSITION_X",3400),E("ABS_MT_POSITION_Y",750),
            E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",12),E("ABS_MT_POSITION_X",2900),E("ABS_MT_POSITION_Y",950),
            E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",13),E("ABS_MT_POSITION_X",2300),E("ABS_MT_POSITION_Y",1050)}, K(3)), 800*ms)
H.check("right-half strip finger + two fingers: 3 visible", H.count(), 3)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 900*ms)
print(H.ok and "ALL PASS (with left/right split)" or "SOME FAILED")
-- 7. zone width: thumb at 31 mm (x=1000) hidden; a touch at 50 mm (x=1600) on the top edge is visible
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",20),E("ABS_MT_POSITION_X",1600),E("ABS_MT_POSITION_Y",200)}, K(1)), 1000*ms)
H.check("top edge at 50 mm from left: visible", H.count(), 1)
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)), 1010*ms)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",21),E("ABS_MT_POSITION_X",1400),E("ABS_MT_POSITION_Y",200)}, K(1)), 1020*ms)
H.check("top edge at 44 mm from left: hidden (inside zone)", H.count(), 0)
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)), 1030*ms)
print(H.ok and "ALL PASS (with zone width)" or "SOME FAILED")
