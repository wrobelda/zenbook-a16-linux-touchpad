dofile(os.getenv("T").."/harness.lua")
local S = os.getenv("S")
H.load({S.."/20-thumb-zone.lua", S.."/30-rest-deadzone.lua", S.."/40-scroll-scale.lua"})
local ms = 1000
-- two fingers land together; each frame moves both by 16 units (0.5 mm)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",1),E("ABS_MT_POSITION_X",2000),E("ABS_MT_POSITION_Y",1500),
            E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",2),E("ABS_MT_POSITION_X",2640),E("ABS_MT_POSITION_Y",1500)}, K(2)), 0)
local y0, y1 = 1500, 1500
local function step(t) y0, y1 = y0+16, y1+16
  H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_Y",y0),E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_Y",y1)}, t) end
step(4*ms); step(8*ms); step(12*ms)                    -- 1.5 mm: still inside the lead
H.check("first 1.5 mm forwarded unscaled", H.li.touches[0].y, 1548)
step(16*ms)                                            -- 2.0 mm: lead done, this step scaled
H.check("step past the lead is scaled (48 + 16*0.33)", H.li.touches[0].y, 1553)
step(20*ms)
H.check("further steps scaled (1553.28+5.28 rounds up)", H.li.touches[0].y, 1559)
H.check("second finger same treatment", H.li.touches[1].y, 1559)
-- lift one finger, land again: a new gesture gets a new lead
H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1)}, K(1)), 30*ms)
H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",3),E("ABS_MT_POSITION_X",2640),E("ABS_MT_POSITION_Y",y1)}, K(2)), 200*ms)
local before = H.li.touches[0].y
step(204*ms)
H.check("new gesture: lead restarts for the finger that stayed", H.li.touches[0].y, before + 16)
-- a single big first move (3 mm) is scaled entirely, as before
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 300*ms)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",4),E("ABS_MT_POSITION_X",2000),E("ABS_MT_POSITION_Y",1500),
            E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",5),E("ABS_MT_POSITION_X",2500),E("ABS_MT_POSITION_Y",1500)}, K(2)), 400*ms)
H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_Y",1600),E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_Y",1600)}, 410*ms)
H.check("single 3 mm move is scaled", H.li.touches[0].y, 1533)
print(H.ok and "ALL PASS" or "SOME FAILED")
-- three fingers: lead 2.2 mm (70.4 units) unscaled, then SWIPE_SCALE 0.5
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 500*ms)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",6),E("ABS_MT_POSITION_X",1500),E("ABS_MT_POSITION_Y",1500),
            E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",7),E("ABS_MT_POSITION_X",2100),E("ABS_MT_POSITION_Y",1500),
            E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",8),E("ABS_MT_POSITION_X",2700),E("ABS_MT_POSITION_Y",1500)}, K(3)), 600*ms)
local x = {1500, 2100, 2700}
local function step3(t) for i=1,3 do x[i]=x[i]+16 end
  H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_X",x[1]),E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_X",x[2]),E("ABS_MT_SLOT",2),E("ABS_MT_POSITION_X",x[3])}, t) end
for i=1,4 do step3(600*ms + i*4*ms) end           -- 64 units = 2.0 mm: inside the 2.2 mm lead
H.check("three fingers: first 2.0 mm unscaled", H.li.touches[0].x, 1564)
step3(620*ms)                                        -- 80 units = 2.5 mm: lead done, step scaled 0.5
H.check("three fingers: unscaled past the lead (SWIPE_SCALE 1.0)", H.li.touches[0].x, 1580)
step3(624*ms)
H.check("three fingers: further steps unscaled", H.li.touches[2].x, 2796)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 700*ms)
print(H.ok and "ALL PASS (with three fingers)" or "SOME FAILED")
