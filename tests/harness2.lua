-- Plugin host with prepend/append frames and the plugin timer, modelled on
-- libinput: injected frames go to the next plugin in call order.
dofile(os.getenv("T").."/harness.lua")
H.now = 0
local timer = { deadline = nil, cb = nil, owner = nil }
local cur_index = nil
local before, after
libinput.now = function() return H.now end
libinput.timer_set_absolute = function(_, t) timer.deadline = t; timer.owner = cur_index end
libinput.timer_set_relative = function(_, d) timer.deadline = H.now + d; timer.owner = cur_index end
libinput.timer_cancel = function() timer.deadline = nil end
local base_connect = libinput.connect
libinput.connect = function(self, n, f) if n == "timer-expired" then timer.cb = f else base_connect(self, n, f) end end
local base_load = H.load
function H.load(list)
  base_load(list)
  H.dev.prepend_frame = function(_, fr) table.insert(before, fr) end
  H.dev.append_frame = function(_, fr) table.insert(after, fr) end
  -- find the timer owner: the plugin that registered the timer callback is unknown
  -- until it arms the timer, so record the index on arm (cur_index).
end
local function deliver(fr)  -- libinput's view
  local li = H.li
  for _, e in ipairs(fr) do
    assert(e.usage ~= nil and type(e.value) == "number", "event with nil usage/value")
    if e.usage==evdev.ABS_MT_SLOT then li.slot=e.value
    elseif e.usage==evdev.ABS_MT_TRACKING_ID then li.touches[li.slot] = (e.value ~= -1) and {tid=e.value} or nil
    elseif e.usage==evdev.ABS_MT_POSITION_X or e.usage==evdev.ABS_MT_POSITION_Y or e.usage==evdev.ABS_MT_TOOL_TYPE then
      local t = li.touches[li.slot]; assert(t, ("event 0x%x for slot %d not begun"):format(e.usage, li.slot))
      if e.usage==evdev.ABS_MT_POSITION_X then t.x=e.value elseif e.usage==evdev.ABS_MT_POSITION_Y then t.y=e.value else t.tool=e.value end
    elseif e.usage >= 0x145 and e.usage <= 0x14f then li.keys[e.usage]=e.value end
  end
  H.delivered = (H.delivered or 0) + 1
end
local function process(fr, i)
  if i > #H.fh then deliver(fr); return end
  local sb, sa = before, after
  before, after = {}, {}
  local prev = cur_index; cur_index = i
  local r = H.fh[i](H.dev, fr, H.now)
  cur_index = prev
  local b, a = before, after
  before, after = sb, sa
  for _, f in ipairs(b) do process(f, i+1) end
  if r == nil then process(fr, i+1) elseif #r > 0 then process(r, i+1) end
  for _, f in ipairs(a) do process(f, i+1) end
end
function H.send(fr, t)
  H.now = t or H.now
  H.fire()                       -- a timer due before this frame fires first
  process(fr, 1)
  return fr
end
function H.fire()
  while timer.deadline and timer.deadline <= H.now and timer.cb do
    local dl = timer.deadline; timer.deadline = nil
    before, after = {}, {}
    local prev = cur_index; cur_index = timer.owner
    timer.cb(H.now)
    cur_index = prev
    local inj = {}
    for _, f in ipairs(before) do inj[#inj+1] = f end
    for _, f in ipairs(after) do inj[#inj+1] = f end
    for _, f in ipairs(inj) do process(f, timer.owner + 1) end
  end
end
function H.tick(t) H.now = t; H.fire() end
function H.pos(slot) local tch = H.li.touches[slot]; return tch and tch.x, tch and tch.y end
