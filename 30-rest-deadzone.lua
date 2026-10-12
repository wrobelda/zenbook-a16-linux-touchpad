-- SPDX-License-Identifier: MIT
--
-- Hold the position of touches that have come to rest during a two-finger
-- scroll, so that the small motion of fingers rolling off the touchpad does
-- not reach libinput.
--
-- This touchpad reports neither pressure nor contact size, so libinput cannot
-- tell that a finger is lifting and turns the roll-off motion into scrolling.
-- Applications compute the kinetic scroll velocity from the last events
-- before the scroll stops, and the roll-off motion then causes a short scroll
-- in a random direction.
--
-- While two or more finger touches are down, a touch is at rest when it stays within
-- REST_MM for REST_MS. While a touch is at rest, the plugin does not forward
-- its position. When the touch moves more than RELEASE_MM away from the rest
-- point, or when it becomes the only touch, the plugin forwards the motion
-- again, relative to the last forwarded position so that libinput does not
-- see a jump. Single-finger pointer motion is never held, so slow and precise
-- pointer movement is not affected.
--
-- Install this file in /etc/libinput/plugins/. It must sort after
-- 20-thumb-zone.lua, because it reads the palm tool type set by that plugin.

libinput:register({1})

-- Only this touchpad is affected, so external touchpads keep the defaults.
DEVICE_NAME = "hid-over-i2c 2808:0219 Touchpad"

REST_MM = 0.2
REST_MS = 100
RELEASE_MM = 0.6

MT_TOOL_PALM = 2

local devices = {}

local function new_segment()
    return { began = false, x = nil, y = nil }
end

-- Update the state of one slot at the end of that slot's events in a frame
-- and append the position events that libinput must see.
local function finish_segment(st, slot, seg, time, out)
    local t = st.touches[slot]

    if seg.began then
        t = {}
        st.touches[slot] = t
        t.x = seg.x or st.last_x[slot]
        t.y = seg.y or st.last_y[slot]
        t.off_x, t.off_y = 0, 0
        t.anchor_x, t.anchor_y, t.anchor_time = t.x, t.y, time
        t.resting = false
    end
    if seg.x ~= nil then st.last_x[slot] = seg.x end
    if seg.y ~= nil then st.last_y[slot] = seg.y end

    if t == nil or t.x == nil or t.y == nil or (seg.x == nil and seg.y == nil) then
        -- No active touch or no motion: forward unchanged values.
        if seg.x ~= nil then table.insert(out, { usage = evdev.ABS_MT_POSITION_X, value = seg.x }) end
        if seg.y ~= nil then table.insert(out, { usage = evdev.ABS_MT_POSITION_Y, value = seg.y }) end
        return
    end

    local x = seg.x or st.last_x[slot]
    local y = seg.y or st.last_y[slot]

    if st.nactive < 2 then
        -- A single finger moves the pointer: forward everything, and restart
        -- the rest timer so that a second finger does not inherit it.
        if t.resting then
            t.resting = false
            t.off_x = x - t.x
            t.off_y = y - t.y
        end
        t.anchor_x, t.anchor_y, t.anchor_time = x, y, time
    elseif not t.resting and time - t.anchor_time >= REST_MS * 1000 then
        -- The time check comes before the distance check, so that the first
        -- motion after a still period is measured against RELEASE_MM and not
        -- against REST_MM.
        -- The rest point is the last position that libinput saw.
        t.resting = true
        t.anchor_x, t.anchor_y = t.x + t.off_x, t.y + t.off_y
    end

    if t.resting then
        if math.abs(x - t.anchor_x) <= st.release_x and math.abs(y - t.anchor_y) <= st.release_y then
            return
        end
        -- Continue from the last forwarded position instead of jumping.
        t.resting = false
        t.off_x = x - t.x
        t.off_y = y - t.y
        t.anchor_x, t.anchor_y, t.anchor_time = x, y, time
    elseif st.nactive >= 2 and (math.abs(x - t.anchor_x) > st.rest_x or math.abs(y - t.anchor_y) > st.rest_y) then
        t.anchor_x, t.anchor_y, t.anchor_time = x, y, time
    end

    t.x, t.y = x - t.off_x, y - t.off_y
    table.insert(out, { usage = evdev.ABS_MT_POSITION_X, value = t.x })
    table.insert(out, { usage = evdev.ABS_MT_POSITION_Y, value = t.y })
end

local function frame(device, frame, time)
    local st = devices[device]
    local out = {}
    local seg = new_segment()

    -- Count the finger touches that are down at the end of this frame, so
    -- that every slot in the frame sees the same count. Palm touches do not
    -- count, so that a resting palm or thumb does not hold slow pointer
    -- motion.
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
    local nactive = 0
    for s in pairs(st.active) do
        if st.tool[s] ~= MT_TOOL_PALM then
            nactive = nactive + 1
        end
    end
    if nactive >= 2 and st.nactive < 2 then
        -- A gesture starts: a finger that was resting alone before the second
        -- finger landed must not be held at once, so its rest timer restarts.
        for slot, t in pairs(st.touches) do
            if not t.resting then
                t.anchor_x, t.anchor_y, t.anchor_time = st.last_x[slot], st.last_y[slot], time
            end
        end
    end
    st.nactive = nactive

    -- The kernel omits ABS_MT_SLOT when the slot does not change, so st.slot
    -- carries the current slot over from the previous frame.
    for _, e in ipairs(frame) do
        if e.usage == evdev.ABS_MT_SLOT then
            finish_segment(st, st.slot, seg, time, out)
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
    finish_segment(st, st.slot, seg, time, out)

    return out
end

libinput:connect("new-evdev-device", function(device)
    if device:name() ~= DEVICE_NAME or not device:udev_properties().ID_INPUT_TOUCHPAD then
        return
    end

    local abs = device:absinfos()
    local ax, ay = abs[evdev.ABS_MT_POSITION_X], abs[evdev.ABS_MT_POSITION_Y]
    if ax == nil or ay == nil or ax.resolution == 0 or ay.resolution == 0 then
        libinput:log_error("rest-deadzone: " .. DEVICE_NAME .. " has no resolution, not enabled")
        return
    end

    devices[device] = {
        slot = 0,
        rest_x = REST_MM * ax.resolution,
        rest_y = REST_MM * ay.resolution,
        release_x = RELEASE_MM * ax.resolution,
        release_y = RELEASE_MM * ay.resolution,
        touches = {},
        active = {},
        tool = {},
        nactive = 0,
        last_x = {},
        last_y = {},
    }
    libinput:log_info("rest-deadzone: enabled on " .. DEVICE_NAME)

    device:connect("evdev-frame", frame)
    device:connect("device-removed", function(dev)
        devices[dev] = nil
    end)
end)
