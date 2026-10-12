# Plugin tests

The tests run the plugins in a mock of libinput's Lua plugin host and check
what libinput would receive. They need `lua` (5.4 or later) and `python3`.

Run them from this directory, with `S` pointing at the plugin directory and
`T` at this directory:

    export T=$PWD S=$PWD/..
    lua test20.lua       # plugins 20, 30, 40: palm zones, slow motion, scaling
    lua testlead.lua     # plugin 40: unscaled lead at the start of a gesture
    lua testreveal.lua   # plugin 20: three-finger reveal and zone layout
    lua test35.lua       # plugins 20, 30, 35, 40: lift trimming (timer-aware host)
    P=20-thumb-zone.lua lua crash2.lua   # no event without a numeric value

`test35.lua` expects plugin 40 with `LEAD_MM = 0`; copy the plugins to a
scratch directory, set that value there, and point `S` at it.

`trace2.lua` replays a `libinput record` file through a plugin chain and
writes, per frame, the kernel's touches and the touches libinput would see:

    OUT=trace.txt lua trace2.lua recording.yml ../20-thumb-zone.lua ../30-rest-deadzone.lua ../35-lift-trim.lua ../40-scroll-scale.lua

`lifts.py` and `rolloff.py` summarize finger motion before each lift from such
a trace.
