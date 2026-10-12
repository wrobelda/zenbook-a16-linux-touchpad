dofile(os.getenv("T").."/harness.lua")
local S = os.getenv("S")
dofile(os.getenv("T").."/nilwrap.lua"); H.load({S.."/"..os.getenv("P")})
local function nilcheck(fr) for i,e in ipairs(fr) do if e.usage == nil or type(e.value) ~= "number" then return ("event %d usage=%s value=%s"):format(i, tostring(e.usage), tostring(e.value)) end end return "ok" end
-- fresh plugin state; new touch in slot 1 where the kernel omits POSITION_Y (same as the previous touch in that slot)
print("new touch, Y omitted:", nilcheck(H.send(cat({E("ABS_MT_SLOT",1),E("ABS_MT_TRACKING_ID",5),E("ABS_MT_POSITION_X",2000)}, K(1)))))
H.send(cat({E("ABS_MT_TRACKING_ID",-1)}, K(0)))
-- palm in top strip with X omitted, then escapes
print("palm, X omitted:", nilcheck(H.send(cat({E("ABS_MT_SLOT",2),E("ABS_MT_TRACKING_ID",6),E("ABS_MT_POSITION_Y",100)}, K(1)))))
print("palm escapes:", nilcheck(H.send({E("ABS_MT_POSITION_Y",2000)})))
