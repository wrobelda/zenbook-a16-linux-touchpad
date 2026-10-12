-- SPDX-License-Identifier: MIT
--
-- Scale down finger motion while two or more fingers are on the touchpad, so
-- that two-finger scrolling and multi-finger swipes are slower while
-- one-finger pointer motion keeps its speed.
--
-- GNOME applies a custom pointer acceleration profile only to pointer motion.
-- libinput then scrolls at 1:1 of the finger motion, which is faster than the
-- adaptive profile, and mutter has no setting for the touchpad scroll speed.
-- GNOME Shell measures three- and four-finger swipes from the unaccelerated
-- motion and switches one workspace per 400 units (about 10 mm), with no
-- setting either.
--
-- While exactly two finger touches are down, the plugin forwards SCALE of the
-- motion of each touch; with three or more it forwards SWIPE_SCALE. Scaling
-- starts after the touch has moved the lead distance since the gesture
-- started. The lead is forwarded unscaled, because libinput decides what the
-- gesture is from the motion it sees, and scaling it would make the gesture
-- start late. At other times the plugin forwards the motion unchanged,
-- relative to the last forwarded position, so that libinput does not see a
-- jump when a finger is added or lifted. Touches that an earlier plugin marks
-- as MT_TOOL_PALM (see 20-thumb-zone.lua) do not count as fingers, so a
-- resting thumb does not slow down the pointer. Two-finger pinch and rotate
-- gestures are scaled like scrolling.
--
-- Install this file in /etc/libinput/plugins/. It must sort after
-- 20-thumb-zone.lua, because it reads the palm tool type set by that plugin.

libinput:register({1})

-- Only this touchpad is affected, so external touchpads keep the defaults.
DEVICE_NAME = "hid-over-i2c 2808:0219 Touchpad"

-- Fraction of the finger motion that libinput sees during two-finger scrolling.
-- The adaptive profile scrolls at 0.9 * 0.2968 of the finger motion, normalized
-- to 1000 dpi; on this 813 dpi touchpad that is 0.33 of the device units, while
-- the custom profile scrolls at 1.0. A value of 0.33 therefore gives the same
-- scroll distance, and the same kinetic scroll speed in applications, as the
-- adaptive profile.
SCALE = 0.33

-- Fraction of the finger motion that libinput sees during three- and
-- four-finger swipes.
-- 1.0 leaves swipes unchanged: GNOME Shell completes a workspace switch only
-- after enough travel, and scaled swipes often ended before reaching it.
SWIPE_SCALE = 1.0

-- Distance that each finger moves unscaled at the start of a two-finger
-- gesture. libinput starts a scroll once both fingers have moved 1.5 mm (or
-- one finger 1 mm after 150 ms); the margin covers its 0.25 mm hysteresis.
-- libinput needs 0.5 mm more for each finger beyond two.
LEAD_MM = 1.7
LEAD_PER_EXTRA_FINGER_MM = 0.5

MT_TOOL_PALM = 2

local devices = {}

local function new_segment()
    return { began = false, x = nil, y = nil }
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Move the forwarded position of one axis by the scaled raw delta and return
-- the integer value that libinput must see.
local function move_axis(t, axis, raw, k, lo, hi)
    local raw_key, out_key = "raw_" .. axis, "out_" .. axis
    if t[raw_key] == nil then
        t[raw_key], t[out_key] = raw, raw
    else
        t[out_key] = clamp(t[out_key] + (raw - t[raw_key]) * k, lo, hi)
        t[raw_key] = raw
    end
    return math.floor(t[out_key] + 0.5)
end

local function finish_segment(st, slot, seg, out)
    if seg.began then
        st.touches[slot] = {}
    end
    local t = st.touches[slot]

    if t == nil then
        if seg.x ~= nil then table.insert(out, { usage = evdev.ABS_MT_POSITION_X, value = seg.x }) end
        if seg.y ~= nil then table.insert(out, { usage = evdev.ABS_MT_POSITION_Y, value = seg.y }) end
        return
    end

    local k = 1.0
    if st.nfingers >= 2 and st.tool[slot] ~= MT_TOOL_PALM then
        -- libinput recognizes a gesture only after each finger has moved
        -- 1.5 mm (plus 0.5 mm per extra finger) from where it was when the
        -- gesture started, measured after the plugins. Forward that lead
        -- unscaled, so that the gesture starts after the same real finger
        -- travel as without this plugin.
        local x = seg.x or t.raw_x
        local y = seg.y or t.raw_y
        if t.lead_x0 == nil then
            t.lead_x0, t.lead_y0 = x, y
        end
        if not t.lead_done and x ~= nil and y ~= nil then
            local dx = (x - t.lead_x0) / st.res_x
            local dy = (y - t.lead_y0) / st.res_y
            local lead = LEAD_MM + LEAD_PER_EXTRA_FINGER_MM * (st.nfingers - 2)
            t.lead_done = math.sqrt(dx * dx + dy * dy) >= lead
        end
        if t.lead_done then
            k = st.nfingers == 2 and SCALE or SWIPE_SCALE
        end
    end
    if seg.x ~= nil then
        local v = move_axis(t, "x", seg.x, k, st.min_x, st.max_x)
        table.insert(out, { usage = evdev.ABS_MT_POSITION_X, value = v })
    end
    if seg.y ~= nil then
        local v = move_axis(t, "y", seg.y, k, st.min_y, st.max_y)
        table.insert(out, { usage = evdev.ABS_MT_POSITION_Y, value = v })
    end
end

local function frame(device, frame, time)
    local st = devices[device]
    local out = {}
    local seg = new_segment()

    -- Count the finger touches that are down at the end of this frame, so
    -- that every slot in the frame uses the same count.
    local slot = st.slot
    for _, e in ipairs(frame) do
        if e.usage == evdev.ABS_MT_SLOT then
            slot = e.value
        elseif e.usage == evdev.ABS_MT_TRACKING_ID then
            st.active[slot] = e.value ~= -1 or nil
            st.tool[slot] = nil
        elseif e.usage == evdev.ABS_MT_TOOL_TYPE then
            st.tool[slot] = e.value
        end
    end
    local nfingers = 0
    for s in pairs(st.active) do
        if st.tool[s] ~= MT_TOOL_PALM then
            nfingers = nfingers + 1
        end
    end
    if nfingers >= 2 and nfingers ~= st.nfingers then
        -- A gesture starts, or libinput restarts its detection because the
        -- finger count changed: measure the lead from here.
        for _, t in pairs(st.touches) do
            t.lead_x0, t.lead_y0, t.lead_done = t.raw_x, t.raw_y, false
        end
    end
    st.nfingers = nfingers

    -- The kernel omits ABS_MT_SLOT when the slot does not change, so st.slot
    -- carries the current slot over from the previous frame.
    for _, e in ipairs(frame) do
        if e.usage == evdev.ABS_MT_SLOT then
            finish_segment(st, st.slot, seg, out)
            st.slot = e.value
            seg = new_segment()
            table.insert(out, e)
        elseif e.usage == evdev.ABS_MT_POSITION_X then
            seg.x = e.value
        elseif e.usage == evdev.ABS_MT_POSITION_Y then
            seg.y = e.value
        else
            if e.usage == evdev.ABS_MT_TRACKING_ID then
                if e.value ~= -1 then
                    seg.began = true
                else
                    st.touches[st.slot] = nil
                end
            end
            table.insert(out, e)
        end
    end
    finish_segment(st, st.slot, seg, out)

    return out
end

libinput:connect("new-evdev-device", function(device)
    if device:name() ~= DEVICE_NAME or not device:udev_properties().ID_INPUT_TOUCHPAD then
        return
    end

    local abs = device:absinfos()
    local ax, ay = abs[evdev.ABS_MT_POSITION_X], abs[evdev.ABS_MT_POSITION_Y]
    if ax == nil or ay == nil or ax.resolution == 0 or ay.resolution == 0 then
        libinput:log_error("scroll-scale: " .. DEVICE_NAME .. " has no resolution, not enabled")
        return
    end

    devices[device] = {
        slot = 0,
        min_x = ax.minimum,
        max_x = ax.maximum,
        min_y = ay.minimum,
        max_y = ay.maximum,
        res_x = ax.resolution,
        res_y = ay.resolution,
        touches = {},
        active = {},
        tool = {},
        nfingers = 0,
    }
    libinput:log_info("scroll-scale: enabled on " .. DEVICE_NAME)

    device:connect("evdev-frame", frame)
    device:connect("device-removed", function(dev)
        devices[dev] = nil
    end)
end)
