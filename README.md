# Zenbook A16 touchpad on Linux

The A16 touchpad reports only finger positions, with no pressure and no contact
size. libinput therefore cannot tell a resting thumb from a finger, and it
cannot tell that a finger is lifting. The plugins below fill those gaps. They
change the touch events before libinput sees them.

The default sizes fit the author, who is right handed:

- The left thumb rests on the top edge of the touchpad while typing.
- The right palm rests along the right edge.
- For a left-handed user, mirror the zones: move the thumb zone to the top
  right corner and the palm strip to the left edge.
- Each size is a variable at the top of its plugin file.

Tested on the UX3607OA (`hid-over-i2c 2808:0219 Touchpad`) with GNOME on
Wayland: libinput 1.32, mutter 51, Fedora 45.

## Plugins

- `20-thumb-zone.lua` hides touches that start in two zones, so a resting
  thumb or palm never reaches libinput.
  - Why: the resting thumb turned pointer motion into two-finger scrolling,
    and libinput's own thumb detection mistook the index finger for a thumb
    and dropped its taps.
  - A hidden touch that moves 5 mm out of its zone towards the center becomes
    visible again.
  - When three fingers are down, a hidden touch in the right strip becomes
    visible. A resting palm never comes with two more fingers, but a
    three-finger swipe does.
  - Zones, with the defaults:

    ```
           0        45 mm                                  133   148 mm
           +---------+-------------------------------------+-----+ 0
           | thumb   |                                     |     |
           | zone    |                                     |  p  | 25 mm
           +---------+                                     |  a  |
           |                                               |  l  |
           |                    free                       |  m  |
           |                                               |     |
           +-----------------------------------------------+-----+ 97 mm
    ```

    | Variable        | Default | Meaning                                         |
    | --------------- | ------- | ----------------------------------------------- |
    | `ZONE_MM`       | 25      | height of the thumb zone, from the top edge     |
    | `ZONE_WIDTH_MM` | 45      | width of the thumb zone, from the left edge     |
    | `RIGHT_ZONE_MM` | 15      | width of the palm strip, from the right edge    |
    | `ESCAPE_MM`     | 5       | travel out of a zone that makes a touch visible |

- `30-rest-deadzone.lua` removes the phantom scroll after a two-finger scroll
  that ends with a pause.
  - Why: when a finger comes to rest before the lift, the fingertip rolls off
    the surface, and the touchpad reports that roll as motion.
  - A finger that stays within `REST_MM` (0.2 mm) for `REST_MS` (100 ms) is
    held still.
  - The finger is released after `RELEASE_MM` (0.6 mm) of travel.

- `35-lift-trim.lua` removes the same roll-off for fingers that lift while
  they still move.
  - Two-finger motion is delayed by `DELAY_MS` (25 ms).
  - When a finger lifts, the delayed motion is discarded, so libinput never
    sees the last 25 ms.
  - Cost: 25 ms of scroll latency.
  - Chromium browsers still fling after a fast lift. That fling is Chromium's
    own kinetic scrolling, proportional to the finger speed at the lift.

- `40-scroll-scale.lua` slows down two-finger scrolling.
  - Why: with the custom acceleration curve below, libinput scrolls at 1:1 of
    the finger motion, three times the speed of the default profile, and
    GNOME has no scroll speed setting.
  - While two fingers are down, `SCALE` (0.33) of the motion is forwarded,
    which matches the default profile.
  - The first `LEAD_MM` (1.7 mm) of each gesture pass unscaled. libinput
    decides from that motion whether two fingers scroll or pinch, and scaled
    motion made scrolls start late.
  - `SWIPE_SCALE` (1.0) does the same for three and four fingers. It is off
    by default, because GNOME Shell completes a workspace switch only after
    enough travel.

## Acceleration curve

GNOME 51 can hand libinput a custom pointer acceleration curve.
`tests/accel-curve.py` generates one:

- It copies libinput's default touchpad curve at the speed setting it was
  generated for.
- Below 14 mm/s it is unchanged, so slow, precise movement stays the same.
- Between about 25 and 230 mm/s it raises the gain by up to 15%, where the
  default felt sluggish.
- Fast flicks return to the default.
- The curve applies only to pointer motion. Scrolling runs at 1:1 under the
  custom profile, and plugin 40 compensates for that.

The script prints the curve. Apply it with:

```sh
gsettings set org.gnome.desktop.peripherals.touchpad custom-accel-config \
    "{'pointer-step': <0.15>, 'pointer-speeds': <[...points from the script...]>}"
gsettings set org.gnome.desktop.peripherals.touchpad accel-profile custom
```

`accel-profile default` switches back.

## Install

```sh
sudo cp *.lua /etc/libinput/plugins/
```

Log out and back in, because GNOME loads libinput plugins only at session
start.

## Testing

- To try a change without logging out, run
  `sudo libinput debug-events --enable-plugins --device /dev/input/eventN`
  with the touchpad's event node.
- To use the plugins with another touchpad, change `DEVICE_NAME` at the top
  of each file.
- The plugins were tuned from `libinput record` captures of real use. The
  mock tests in `tests/` replay such captures through the plugins and check
  the events that reach libinput. See `tests/README.md`.
