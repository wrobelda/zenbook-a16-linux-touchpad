-- SPDX-License-Identifier: MIT
--
-- Hide touches that start in a zone in the top left corner of the touchpad
-- from libinput. While typing, the left thumb rests below the space bar, on
-- the top edge of the touchpad left of its center, and would otherwise turn
-- one-finger pointer motion into two-finger scrolling. libinput's own thumb
-- detection does not help here, because it assumes that the thumb is the
-- lowest touch. The rest of the top edge is ordinary touchpad, so scrolls,
-- swipes and pinches may start there.
--
-- Touches that start in a strip along the left or right edge are hidden as
-- well, because the palms rest there while typing. libinput's own edge palm
-- zones are at most 8 mm wide.
--
-- The plugin hides such a touch instead of marking it as MT_TOOL_PALM,
-- because libinput 1.32 still uses palm touches for its multi-finger thumb
-- detection: a finger that lands more than 25 mm below a resting palm is
-- classified as a thumb, and libinput then ignores that finger's taps.
--
-- A touch in an edge strip is hidden only while at most one other finger is
-- down. A resting palm never comes with two more fingers, so when three or
-- more finger touches are down, the hidden touch is shown as a new touch and
-- a three-finger swipe that reaches into a strip still has three fingers. A
-- touch in the thumb zone stays hidden regardless, because the left thumb
-- rests there while the right hand scrolls with two fingers.
--
-- A hidden touch sends no events to libinput, and the finger count in
-- BTN_TOUCH and BTN_TOOL_* counts only the visible touches. A physical click
-- still produces a button event. If a hidden touch moves more than ESCAPE_MM
-- out of every strip that it started in, towards the center of the touchpad,
-- libinput sees it as a new touch from that position on, so a finger that
-- starts in a strip can still move the pointer. Touches that the touchpad
-- firmware reports as MT_TOOL_PALM are forwarded unchanged.
--
-- Install this file in /etc/libinput/plugins/. It must sort before
-- 30-rest-deadzone.lua and 40-scroll-scale.lua.

libinput:register({1})

-- Only this touchpad is affected, so external touchpads keep the defaults.
DEVICE_NAME = "hid-over-i2c 2808:0219 Touchpad"

-- Size of the thumb zone in the top left corner, measured from the top and
-- left edges. The resting left thumb was recorded 31 mm from the left edge and
-- 6 mm from the top; the width leaves a margin around that and keeps the rest
-- of the top edge free for gestures.
ZONE_MM = 25
ZONE_WIDTH_MM = 45
-- Width of the palm strips, measured from the left and right edges.
LEFT_ZONE_MM = 15
RIGHT_ZONE_MM = 15
-- Distance past a strip that a hidden touch must reach to become visible.
ESCAPE_MM = 5

MT_TOOL_FINGER = 0
MT_TOOL_PALM = 2

local devices = {}

-- Multitouch usages that belong to the current slot.
local MT_USAGES = {}
for _, name in ipairs({ "ABS_MT_TOUCH_MAJOR", "ABS_MT_TOUCH_MINOR", "ABS_MT_WIDTH_MAJOR",
                        "ABS_MT_WIDTH_MINOR", "ABS_MT_ORIENTATION", "ABS_MT_POSITION_X",
                        "ABS_MT_POSITION_Y", "ABS_MT_TOOL_TYPE", "ABS_MT_BLOB_ID",
                        "ABS_MT_TRACKING_ID", "ABS_MT_PRESSURE", "ABS_MT_DISTANCE",
                        "ABS_MT_TOOL_X", "ABS_MT_TOOL_Y" }) do
    if evdev[name] ~= nil then
        MT_USAGES[evdev[name]] = true
    end
end

-- Finger count keys, recomputed from the visible touches. The index is the
-- number of touches that the key stands for.
local TOOL_KEYS = { "BTN_TOOL_FINGER", "BTN_TOOL_DOUBLETAP", "BTN_TOOL_TRIPLETAP",
                    "BTN_TOOL_QUADTAP", "BTN_TOOL_QUINTTAP" }
local COUNT_USAGES = { [evdev.BTN_TOUCH] = true }
for _, name in ipairs(TOOL_KEYS) do
    COUNT_USAGES[evdev[name]] = true
end

local function new_segment(slot)
    return { slot = slot, began = false, ended = false, firmware_tool = nil, events = {} }
end

local function emit_slot(st, slot, out)
    if st.lslot ~= slot then
        table.insert(out, { usage = evdev.ABS_MT_SLOT, value = slot })
        st.lslot = slot
    end
end

-- Decide whether the touch in one slot is hidden, at the end of that slot's
-- events in a frame, and append the events that libinput must see.
local function finish_segment(st, seg, out)
    local slot = seg.slot
    local x, y = st.x[slot], st.y[slot]

    if seg.firmware_tool ~= nil then
        st.firmware_tool[slot] = seg.firmware_tool
    end

    if seg.ended then
        if st.shown[slot] then
            emit_slot(st, slot, out)
            table.insert(out, { usage = evdev.ABS_MT_TRACKING_ID, value = -1 })
        end
        st.shown[slot] = false
        st.palm[slot] = false
        st.tid[slot] = nil
        return
    end

    if seg.began then
        local top = y ~= nil and y <= st.zone_bottom and x ~= nil and x < st.zone_right
        local left = x ~= nil and x <= st.left_zone_right
        local right = x ~= nil and x >= st.right_zone_left
        -- The top strip is where the left thumb rests while the right hand
        -- scrolls, so a touch that starts there stays hidden even with three
        -- touches down.
        st.palm[slot] = (top or left or right) and { top = top, left = left, right = right, resting = top } or false
    elseif st.palm[slot] then
        -- The touch stays hidden while it is inside the escape margin of any
        -- strip that it started in.
        local p = st.palm[slot]
        local in_top = p.top and (y == nil or y <= st.escape_line)
        local in_left = p.left and (x == nil or x <= st.left_escape_line)
        local in_right = p.right and (x == nil or x >= st.right_escape_line)
        if not in_top and not in_left and not in_right then
            st.palm[slot] = false
        end
    end

    if st.palm[slot] then
        -- The kernel replaced a visible touch with a new touch in this slot.
        if st.shown[slot] then
            emit_slot(st, slot, out)
            table.insert(out, { usage = evdev.ABS_MT_TRACKING_ID, value = -1 })
            st.shown[slot] = false
        end
        return
    end
    if st.tid[slot] == nil then
        return
    end

    local want = st.firmware_tool[slot] or MT_TOOL_FINGER
    emit_slot(st, slot, out)
    if not st.shown[slot] or seg.began then
        -- A new touch, or a hidden touch that escaped: libinput sees the
        -- complete state of a new touch.
        table.insert(out, { usage = evdev.ABS_MT_TRACKING_ID, value = st.tid[slot] })
        -- The kernel omits a coordinate that did not change since the last
        -- touch in this slot. If the plugin has not seen that coordinate
        -- since it started, it never dropped an event for it either, so
        -- libinput still has the correct value. An event without a value
        -- aborts the compositor.
        if x ~= nil then
            table.insert(out, { usage = evdev.ABS_MT_POSITION_X, value = x })
        end
        if y ~= nil then
            table.insert(out, { usage = evdev.ABS_MT_POSITION_Y, value = y })
        end
        for _, e in ipairs(seg.events) do
            if e.usage ~= evdev.ABS_MT_POSITION_X and e.usage ~= evdev.ABS_MT_POSITION_Y then
                table.insert(out, e)
            end
        end
        -- libinput does not reset the tool type when a new touch starts in a
        -- slot, so every new touch gets an explicit value.
        table.insert(out, { usage = evdev.ABS_MT_TOOL_TYPE, value = want })
        st.sent[slot] = want
        st.shown[slot] = true
        return
    end

    for _, e in ipairs(seg.events) do
        table.insert(out, e)
    end
    if want ~= st.sent[slot] then
        table.insert(out, { usage = evdev.ABS_MT_TOOL_TYPE, value = want })
        st.sent[slot] = want
    end
end

-- Append the finger count keys that match the visible touches, where they
-- differ from the values that libinput last saw.
-- Show the hidden touches when three or more finger touches are down. A
-- resting thumb or palm is accompanied by at most one finger, so with three
-- touches the one in a strip is a finger of a multi-finger gesture, for
-- example the top finger of a three-finger swipe. libinput sees it as a new
-- touch at its current position.
local function reveal_for_gesture(st, out)
    local n = 0
    for slot in pairs(st.tid) do
        if st.firmware_tool[slot] ~= MT_TOOL_PALM then
            n = n + 1
        end
    end
    if n < 3 then
        return
    end
    for slot in pairs(st.tid) do
        if st.palm[slot] and not st.palm[slot].resting and not st.shown[slot] then
            st.palm[slot] = false
            local want = st.firmware_tool[slot] or MT_TOOL_FINGER
            emit_slot(st, slot, out)
            table.insert(out, { usage = evdev.ABS_MT_TRACKING_ID, value = st.tid[slot] })
            if st.x[slot] ~= nil then
                table.insert(out, { usage = evdev.ABS_MT_POSITION_X, value = st.x[slot] })
            end
            if st.y[slot] ~= nil then
                table.insert(out, { usage = evdev.ABS_MT_POSITION_Y, value = st.y[slot] })
            end
            table.insert(out, { usage = evdev.ABS_MT_TOOL_TYPE, value = want })
            st.sent[slot] = want
            st.shown[slot] = true
        end
    end
end

local function emit_counts(st, out)
    local n = 0
    for _, shown in pairs(st.shown) do
        if shown then
            n = n + 1
        end
    end

    local want = { [evdev.BTN_TOUCH] = n > 0 and 1 or 0 }
    for i, name in ipairs(TOOL_KEYS) do
        local hit = (n == i) or (i == #TOOL_KEYS and n > i)
        want[evdev[name]] = hit and 1 or 0
    end
    for usage, value in pairs(want) do
        if st.keys[usage] and st.key_state[usage] ~= value then
            table.insert(out, { usage = usage, value = value })
            st.key_state[usage] = value
        end
    end
end

local function frame(device, frame, timestamp)
    local st = devices[device]
    local out = {}
    local seg = nil

    -- The kernel omits ABS_MT_SLOT when the slot does not change, so st.slot
    -- carries the current slot over from the previous frame. The kernel sends
    -- all multitouch events of a frame before the other events.
    for _, e in ipairs(frame) do
        if e.usage == evdev.ABS_MT_SLOT then
            if seg ~= nil then
                finish_segment(st, seg, out)
            end
            st.slot = e.value
            seg = new_segment(e.value)
        elseif MT_USAGES[e.usage] then
            if seg == nil then
                seg = new_segment(st.slot)
            end
            if e.usage == evdev.ABS_MT_TRACKING_ID then
                if e.value == -1 then
                    seg.ended = true
                else
                    seg.began = true
                    seg.ended = false
                    st.tid[st.slot] = e.value
                end
            elseif e.usage == evdev.ABS_MT_TOOL_TYPE then
                seg.firmware_tool = e.value
            else
                if e.usage == evdev.ABS_MT_POSITION_X then
                    st.x[st.slot] = e.value
                elseif e.usage == evdev.ABS_MT_POSITION_Y then
                    st.y[st.slot] = e.value
                end
                table.insert(seg.events, e)
            end
        else
            if seg ~= nil then
                finish_segment(st, seg, out)
                seg = nil
            end
            if not COUNT_USAGES[e.usage] then
                table.insert(out, e)
            end
        end
    end
    if seg ~= nil then
        finish_segment(st, seg, out)
    end
    reveal_for_gesture(st, out)
    emit_counts(st, out)

    return out
end

libinput:connect("new-evdev-device", function(device)
    if device:name() ~= DEVICE_NAME or not device:udev_properties().ID_INPUT_TOUCHPAD then
        return
    end

    local abs = device:absinfos()
    local ax, ay = abs[evdev.ABS_MT_POSITION_X], abs[evdev.ABS_MT_POSITION_Y]
    if ax == nil or ay == nil or ax.resolution == 0 or ay.resolution == 0 then
        libinput:log_error("thumb-zone: " .. DEVICE_NAME .. " has no resolution, not enabled")
        return
    end

    local keys = {}
    local usages = device:usages()
    for usage in pairs(COUNT_USAGES) do
        keys[usage] = usages[usage] ~= nil or nil
    end

    local zone_bottom = ay.minimum + ZONE_MM * ay.resolution
    local left_zone_right = ax.minimum + LEFT_ZONE_MM * ax.resolution
    local right_zone_left = ax.maximum - RIGHT_ZONE_MM * ax.resolution
    devices[device] = {
        slot = 0,
        lslot = nil,
        zone_bottom = zone_bottom,
        escape_line = zone_bottom + ESCAPE_MM * ay.resolution,
        left_zone_right = left_zone_right,
        left_escape_line = left_zone_right + ESCAPE_MM * ax.resolution,
        right_zone_left = right_zone_left,
        zone_right = ax.minimum + ZONE_WIDTH_MM * ax.resolution,
        right_escape_line = right_zone_left - ESCAPE_MM * ax.resolution,
        x = {},
        y = {},
        tid = {},
        palm = {},
        shown = {},
        sent = {},
        firmware_tool = {},
        keys = keys,
        key_state = {},
    }
    libinput:log_info("thumb-zone: enabled on " .. DEVICE_NAME)

    device:connect("evdev-frame", frame)
    device:connect("device-removed", function(dev)
        devices[dev] = nil
    end)
end)
