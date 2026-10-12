dofile(os.getenv("T").."/harness2.lua")
local S = os.getenv("S")
SC = tonumber(os.getenv("SC") or "0.33")
local chain = { S.."/20-thumb-zone.lua", S.."/30-rest-deadzone.lua", S.."/35-lift-trim.lua", S.."/40-scroll-scale.lua" }
if os.getenv("ONLY35") then chain = { S.."/35-lift-trim.lua" } end
H.load(chain)
local ms = 1000
local function down2(t) -- two fingers land at once, 20 mm apart, in the middle
  H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",1),E("ABS_MT_POSITION_X",2000),E("ABS_MT_POSITION_Y",1500),
              E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",2),E("ABS_MT_POSITION_X",2640),E("ABS_MT_POSITION_Y",1500)}, K(2)), t)
end
local function move2(t, dy) -- both fingers move down by dy units, kernel order slot 0 then 1
  local _, y0 = H.pos(0)
  H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_Y",move2_y0+dy),E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_Y",move2_y1+dy)}, t)
  move2_y0, move2_y1 = move2_y0+dy, move2_y1+dy
end
-- 1. two-finger motion is delayed by 25 ms, then delivered
move2_y0, move2_y1 = 1500, 1500
down2(0)
local _, y = H.pos(0); H.check("fingers visible at once", y, 1500)
for i=1,5 do move2(i*4*ms, 8) end           -- 20 ms of motion, 40 units total
_, y = H.pos(0); H.check("motion not yet delivered at 20 ms", y, 1500)
H.tick(29*ms)                                 -- first frame (t=4ms) is due at 29 ms
_, y = H.pos(0); H.check("first frame delivered at 29 ms", y, 1500 + 8*SC // 1 + (8*SC % 1 >= 0.5 and 1 or 0))
H.tick(50*ms)
_, y = H.pos(0); local fy = y
H.check("all frames delivered by 50 ms", math.abs(y - (1500 + 40*SC)) <= 1, true)
-- 2. fingers keep moving and lift: the last 25 ms are discarded
for i=1,10 do move2(50*ms + i*4*ms, 8) end   -- 40 ms more motion, lift at 90 ms
H.tick(86*ms)                                 -- frames up to t=61ms delivered (due <= 86)
_, y = H.pos(0); local y_before_lift = y
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 90*ms)
H.check("both touches ended", H.count(), 0)
H.check("delivered motion stops ~25 ms before the lift (units)", y_before_lift - fy <= SC*8*4 + 1, true)
H.tick(200*ms)
H.check("nothing delivered after the lift", H.count(), 0)
-- 3. one finger lifts, the other continues: no jump
move2_y0, move2_y1 = 1500, 1500
down2(300*ms)
for i=1,10 do move2(300*ms + i*4*ms, 8) end  -- to t=340
H.tick(360*ms)                                -- delivered up to t=335
local _, y_seen = H.pos(1)
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1)}, K(1)), 341*ms)   -- slot 0 lifts
local _, y_after = H.pos(1)
H.check("remaining finger does not jump at the lift", y_after, y_seen)
H.send({E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_Y",move2_y1+10)}, 345*ms)     -- 1 finger: immediate, unscaled
local _, y_next = H.pos(1)
H.check("remaining finger continues relative (+10)", y_next, y_seen + 10)
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)), 350*ms)
-- 4. single finger is never delayed
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",7),E("ABS_MT_POSITION_X",2000),E("ABS_MT_POSITION_Y",1500)}, K(1)), 400*ms)
H.send({E("ABS_MT_POSITION_X",2050)}, 404*ms)
local x = H.pos(0); H.check("single finger immediate", x, 2050)
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)), 410*ms)
-- 5. a third finger landing flushes the held frames first, in order
move2_y0, move2_y1 = 1500, 1500
down2(500*ms)
for i=1,3 do move2(500*ms + i*4*ms, 8) end
H.delivered = 0
H.send(cat({E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",9),E("ABS_MT_POSITION_X",3300),E("ABS_MT_POSITION_Y",1500)}, K(3)), 513*ms)
H.check("third finger: held frames flushed before it (frames delivered)", H.delivered, 4)
_, y = H.pos(0); H.check("flushed motion visible", math.abs(y - (1500 + 24*SC)) <= 1, true)
H.check("three touches visible", H.count(), 3)
print(H.ok and "ALL PASS" or "SOME FAILED")
-- 6. fingers pause 150 ms, then lift: plugin 30 holds, plugin 35 discards; nothing odd
H.send(cat({E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 600*ms)
move2_y0, move2_y1 = 1500, 1500
down2(700*ms)
for i=1,5 do move2(700*ms + i*4*ms, 8) end
H.tick(900*ms)
local _, y_rest = H.pos(0)
H.send({E("ABS_MT_SLOT",0),E("ABS_MT_POSITION_Y",move2_y0+2),E("ABS_MT_SLOT",1),E("ABS_MT_POSITION_Y",move2_y1-2)}, 905*ms) -- roll-off wiggle
H.send(cat({E("ABS_MT_SLOT",0),E("ABS_MT_TRACKING_ID",-1),E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",-1)}, K(0)), 909*ms)
H.tick(1000*ms)
H.check("pause then lift: no motion after the pause reaches libinput", H.li.touches[0] == nil and y_rest ~= nil, true)
print(H.ok and "ALL PASS (with pause case)" or "SOME FAILED")
