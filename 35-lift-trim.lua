-- SPDX-License-Identifier: MIT
--
-- Discard the motion of the last DELAY_MS before fingers lift off the
-- touchpad during two-finger scrolling.
--
-- This touchpad reports neither pressure nor contact size, so libinput cannot
-- tell that a finger is lifting. The fingertips roll as they leave the
-- surface, and the touchpad reports that roll as motion, often faster than
-- the scroll itself. Applications compute the kinetic scroll velocity from
-- the last events before the scroll stops, so this motion turns into a fling
-- that is faster than the scroll.
--
-- While exactly two finger touches are down, the plugin holds back frames
-- that contain only motion and forwards them DELAY_MS later. When a finger
-- lifts, the plugin discards the motion that it still holds, so libinput does
-- not see the motion of the lift. Touches that stay down continue relative to
-- the last position that libinput saw, so libinput does not see a jump. Any
-- other frame, for example a new touch or a button press, first releases the
-- held frames in order. One-finger pointer motion and three- and four-finger
-- swipes are never delayed: GNOME Shell judges a swipe by its final travel and
-- speed, and short swipes lost both when their end was trimmed.
--
-- Install this file in /etc/libinput/plugins/. It must sort after
-- 30-rest-deadzone.lua and before 40-scroll-scale.lua.

libinput:register({1})

-- Only this touchpad is affected, so external touchpads keep the defaults.
DEVICE_NAME = "hid-over-i2c 2808:0219 Touchpad"

-- Two-finger motion that is younger than this when a finger lifts is
-- discarded. It is also the added latency of two-finger gestures.
DELAY_MS = 25

MT_TOOL_PALM = 2

local devices = {}

-- Events that may appear in a frame that only contains motion.
local MOTION_USAGES = {
    [evdev.ABS_MT_SLOT] = true,
    [evdev.ABS_MT_POSITION_X] = true,
    [evdev.ABS_MT_POSITION_Y] = true,
    [evdev.ABS_X] = true,
    [evdev.ABS_Y] = true,
}
if evdev.MSC_TIMESTAMP ~= nil then
    MOTION_USAGES[evdev.MSC_TIMESTAMP] = true
end

local function is_motion_only(frame)
    for _, e in ipairs(frame) do
        if not MOTION_USAGES[e.usage] then
            return false
        end
    end
    return true
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- Return a copy of the frame that starts with an explicit ABS_MT_SLOT, so
-- that it does not depend on the slot of a discarded frame, and with the
-- position of each touch shifted by that touch's offset. Also record the
-- shifted positions as the latest positions of each touch.
local function adjust(st, frame)
    local out = {}
    local slot = st.slot
    local has_slot = false
    for _, e in ipairs(frame) do
        if e.usage == evdev.ABS_MT_SLOT then
            slot = e.value
            has_slot = true
            table.insert(out, e)
        elseif e.usage == evdev.ABS_MT_POSITION_X or e.usage == evdev.ABS_MT_POSITION_Y then
            if not has_slot then
                table.insert(out, { usage = evdev.ABS_MT_SLOT, value = slot })
                has_slot = true
            end
            local axis = e.usage == evdev.ABS_MT_POSITION_X and "x" or "y"
            local v = clamp(e.value - (st.off[axis][slot] or 0), st.min[axis], st.max[axis])
            st.latest[axis][slot] = v
            table.insert(out, { usage = e.usage, value = v })
        else
            if e.usage == evdev.ABS_MT_TRACKING_ID then
                if not has_slot then
                    table.insert(out, { usage = evdev.ABS_MT_SLOT, value = slot })
                    has_slot = true
                end
                -- A new or ended touch starts without an offset.
                st.off.x[slot], st.off.y[slot] = nil, nil
                st.latest.x[slot], st.latest.y[slot] = nil, nil
                st.sent.x[slot], st.sent.y[slot] = nil, nil
            end
            table.insert(out, e)
        end
    end
    st.slot = slot
    return out
end

-- Record the positions that libinput sees when a frame is forwarded. Every
-- forwarded frame starts with an explicit slot.
local function note_sent(st, frame)
    local slot
    for _, e in ipairs(frame) do
        if e.usage == evdev.ABS_MT_SLOT then
            slot = e.value
        elseif e.usage == evdev.ABS_MT_POSITION_X then
            st.sent.x[slot] = e.value
        elseif e.usage == evdev.ABS_MT_POSITION_Y then
            st.sent.y[slot] = e.value
        end
    end
end

local function forward(st, device, frame, prepend)
    if prepend then
        device:prepend_frame(frame)
    else
        device:append_frame(frame)
    end
    note_sent(st, frame)
end

-- Discard the held frames. Touches that stay down continue from the position
-- that libinput last saw.
local function discard(st)
    if #st.queue == 0 then
        return
    end
    for _, axis in ipairs({ "x", "y" }) do
        for slot, v in pairs(st.latest[axis]) do
            local sent = st.sent[axis][slot]
            if sent ~= nil then
                st.off[axis][slot] = (st.off[axis][slot] or 0) + (v - sent)
                st.latest[axis][slot] = sent
            end
        end
    end
    st.queue = {}
end

local function arm_timer()
    local next_due = nil
    for _, st in pairs(devices) do
        local q = st.queue[1]
        if q ~= nil and (next_due == nil or q.due < next_due) then
            next_due = q.due
        end
    end
    if next_due ~= nil then
        libinput:timer_set_absolute(next_due)
    else
        libinput:timer_cancel()
    end
end

-- Count the finger touches that are down at the end of the frame.
local function count_fingers(st, frame)
    local slot = st.count_slot
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
    st.count_slot = slot
    local n = 0
    for s in pairs(st.active) do
        if st.tool[s] ~= MT_TOOL_PALM then
            n = n + 1
        end
    end
    return n
end

local function frame(device, frame, time)
    local st = devices[device]
    local fingers_before = st.nfingers
    st.nfingers = count_fingers(st, frame)

    if fingers_before == 2 and is_motion_only(frame) then
        table.insert(st.queue, { due = time + DELAY_MS * 1000, events = adjust(st, frame) })
        if #st.queue == 1 then
            arm_timer()
        end
        return {}
    end

    local lifted = false
    if fingers_before == 2 then
        for _, e in ipairs(frame) do
            if e.usage == evdev.ABS_MT_TRACKING_ID and e.value == -1 then
                lifted = true
            end
        end
    end

    if lifted then
        discard(st)
    else
        for _, q in ipairs(st.queue) do
            forward(st, device, q.events, true)
        end
        st.queue = {}
    end
    arm_timer()

    local out = adjust(st, frame)
    note_sent(st, out)
    return out
end

libinput:connect("timer-expired", function(now)
    for device, st in pairs(devices) do
        while st.queue[1] ~= nil and st.queue[1].due <= now do
            local q = table.remove(st.queue, 1)
            forward(st, device, q.events, false)
        end
    end
    arm_timer()
end)

libinput:connect("new-evdev-device", function(device)
    if device:name() ~= DEVICE_NAME or not device:udev_properties().ID_INPUT_TOUCHPAD then
        return
    end

    local abs = device:absinfos()
    local ax, ay = abs[evdev.ABS_MT_POSITION_X], abs[evdev.ABS_MT_POSITION_Y]
    if ax == nil or ay == nil then
        libinput:log_error("lift-trim: " .. DEVICE_NAME .. " has no MT position axes, not enabled")
        return
    end

    devices[device] = {
        slot = 0,
        count_slot = 0,
        nfingers = 0,
        active = {},
        tool = {},
        queue = {},
        min = { x = ax.minimum, y = ay.minimum },
        max = { x = ax.maximum, y = ay.maximum },
        off = { x = {}, y = {} },
        latest = { x = {}, y = {} },
        sent = { x = {}, y = {} },
    }
    libinput:log_info("lift-trim: enabled on " .. DEVICE_NAME)

    device:connect("evdev-frame", frame)
    device:connect("device-removed", function(dev)
        devices[dev] = nil
        arm_timer()
    end)
end)
