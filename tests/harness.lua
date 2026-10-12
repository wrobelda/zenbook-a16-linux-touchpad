-- Minimal libinput plugin host: loads plugins in order, feeds frames, and
-- models what libinput sees (slots begun, positions, finger-count keys).
evdev = { ABS_MT_SLOT=0x2f, ABS_MT_TOUCH_MAJOR=0x30, ABS_MT_POSITION_X=0x35, ABS_MT_POSITION_Y=0x36,
  ABS_MT_TOOL_TYPE=0x37, ABS_MT_TRACKING_ID=0x39, ABS_X=0x100, ABS_Y=0x101, MSC_TIMESTAMP=0x205,
  BTN_LEFT=0x110, BTN_TOUCH=0x14a, BTN_TOOL_FINGER=0x145, BTN_TOOL_DOUBLETAP=0x14d,
  BTN_TOOL_TRIPLETAP=0x14e, BTN_TOOL_QUADTAP=0x14f, BTN_TOOL_QUINTTAP=0x148 }
H = {}
local handlers, cur = {}, nil
libinput = { register=function() end, log_info=function() end,
  log_error=function(_,m) error("plugin error: "..m) end, connect=function(_,n,f) handlers[cur]=f end }
function H.load(list)
  handlers = {}; H.fh = {}
  for _, p in ipairs(list) do cur=p; dofile(p) end
  local dev = { name=function() return "hid-over-i2c 2808:0219 Touchpad" end,
    udev_properties=function() return {ID_INPUT_TOUCHPAD="1"} end,
    usages=function() local u={} for k,v in pairs(evdev) do u[v]=true end return u end,
    absinfos=function() return {[evdev.ABS_MT_POSITION_X]={minimum=0,maximum=4762,resolution=32},
                                 [evdev.ABS_MT_POSITION_Y]={minimum=0,maximum=3099,resolution=32}} end }
  for _, p in ipairs(list) do dev.connect=function(_,n,f) if n=="evdev-frame" then H.fh[#H.fh+1]=f end end; handlers[p](dev) end
  H.dev = dev
  H.li = { slot=0, touches={}, keys={} }   -- libinput's view
end
function H.send(fr, t)
  for _, f in ipairs(H.fh) do local r = f(H.dev, fr, t or 0); if r then fr = r end end
  local li = H.li
  for _, e in ipairs(fr) do
    if e.usage==evdev.ABS_MT_SLOT then li.slot=e.value
    elseif e.usage==evdev.ABS_MT_TRACKING_ID then
      li.touches[li.slot] = (e.value ~= -1) and {tid=e.value} or nil
    elseif e.usage==evdev.ABS_MT_POSITION_X or e.usage==evdev.ABS_MT_POSITION_Y or e.usage==evdev.ABS_MT_TOOL_TYPE then
      local t = li.touches[li.slot]
      assert(t, ("event 0x%x for slot %d that libinput has not seen begin"):format(e.usage, li.slot))
      if e.usage==evdev.ABS_MT_POSITION_X then t.x=e.value elseif e.usage==evdev.ABS_MT_POSITION_Y then t.y=e.value else t.tool=e.value end
    elseif e.usage >= 0x145 and e.usage <= 0x14f then li.keys[e.usage]=e.value end
  end
  return fr
end
function H.count() local n=0 for _ in pairs(H.li.touches) do n=n+1 end return n end
function H.keycount()
  local k=H.li.keys; local m = {[0x145]=1,[0x14d]=2,[0x14e]=3,[0x14f]=4,[0x148]=5}
  local n=0; for code,c in pairs(m) do if k[code]==1 then assert(n==0,"two BTN_TOOL keys set"); n=c end end
  if n>0 then assert(k[0x14a]==1,"BTN_TOUCH not set with tool key") end
  return n
end
H.ok = true
function H.check(name, got, want) local p = got==want; H.ok = H.ok and p
  print(("%s %s: got %s want %s"):format(p and "PASS" or "FAIL", name, tostring(got), tostring(want))) end
function E(u,v) return {usage=evdev[u],value=v} end
-- kernel-style finger count keys for n touches
function K(n) return {E("BTN_TOUCH", n>0 and 1 or 0), E("BTN_TOOL_FINGER", n==1 and 1 or 0), E("BTN_TOOL_DOUBLETAP", n==2 and 1 or 0)} end
function cat(a,b) local r={} for _,e in ipairs(a) do r[#r+1]=e end for _,e in ipairs(b) do r[#r+1]=e end return r end
