# Zenbook A16 touchpad on Linux

The A16 touchpad reports only finger positions, with no pressure and no contact
size. libinput therefore cannot tell a resting thumb from a finger, and it
cannot tell that a finger is lifting.

The plugins in this repository intend to fill those gaps, effectively
making the touchpad behave as close to its Windows calibration as possible.

The default sizes fit the author, who is right handed:

- The left thumb rests on the top edge of the touchpad while typing.
- The palms rest along the left and right edges.
- For a left-handed user, move the thumb zone to the top right corner.
- Each size is a variable at the top of its plugin file.

Tested on the UX3607OA (`hid-over-i2c 2808:0219 Touchpad`) with GNOME on
Wayland: libinput 1.32, mutter 51, Fedora 45.

## Plugins

- `20-thumb-zone.lua` hides touches that start in three zones, so a resting
  thumb or palm never reaches libinput.
  - Why: the resting thumb turned pointer motion into two-finger scrolling,
    and libinput's own thumb detection mistook the index finger for a thumb
    and dropped its taps.
  - A hidden touch that moves 5 mm out of its zone towards the center becomes
    visible again.
  - When three fingers are down, a hidden touch in an edge strip becomes
    visible. A resting palm never comes with two more fingers, but a
    three-finger swipe does.
  - Zones, with the defaults:

    ```
         0    15        45 mm                              133   148 mm
         +-----+---------+---------------------------------+-----+ 0
         |     |  thumb  |                                 |     |
         |  p  |  zone   |                                 |  p  | 25 mm
         |  a  +---------+                                 |  a  |
         |  l  |                                           |  l  |
         |  m  |                  free                     |  m  |
         |     |                                           |     |
         +-----+-------------------------------------------+-----+ 97 mm
    ```

    | Variable        | Default | Meaning                                         |
    | --------------- | ------- | ----------------------------------------------- |
    | `THUMB_ZONE_HEIGHT_MM`       | 25      | height of the thumb zone, from the top edge     |
    | `LEFT_THUMB_ZONE_MM` | 45      | width of the thumb zone, from the left edge     |
    | `LEFT_PALM_MM`  | 15      | width of the palm strip, from the left edge     |
    | `RIGHT_PALM_MM` | 15      | width of the palm strip, from the right edge    |
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

GNOME 51 can hand libinput a custom pointer acceleration curve. The curve
below is libinput's default touchpad curve, sampled for this touchpad at the
0.27 speed setting, with one change:

- Below 14 mm/s it is unchanged, so slow, precise movement stays the same.
- Between about 25 and 230 mm/s the gain is up to 35% higher, where the
  default felt sluggish.
- Fast flicks return to the default.
- The curve applies only to pointer motion. Scrolling runs at 1:1 under the
  custom profile, and plugin 40 compensates for that.

```sh
gsettings set org.gnome.desktop.peripherals.touchpad custom-accel-config \
    "{'pointer-step': <0.15>, 'pointer-speeds': <[0.0, 0.073, 0.171, 0.26, 0.365, 0.488, 0.627, 0.774, 0.915, 1.036, 1.151, 1.266, 1.381, 1.496, 1.611, 1.726, 1.842, 1.957, 2.072, 2.187, 2.302, 2.417, 2.532, 2.647, 2.762, 2.877, 2.993, 3.108, 3.227, 3.388, 3.555, 3.728, 3.908, 4.096, 4.291, 4.494, 4.706, 4.925, 5.154, 5.392, 5.64, 5.897, 6.165, 6.443, 6.717, 6.978, 7.224, 7.457, 7.677, 7.884, 8.079, 8.263, 8.439, 8.608, 8.774, 8.939, 9.109, 9.286, 9.478, 9.689, 9.928, 10.202, 10.519, 10.891]>}"
gsettings set org.gnome.desktop.peripherals.touchpad accel-profile custom
```

- `accel-profile default` switches back.
- To generate your own middle-section boost, run `./accel-curve.py --boost 20`.
  See `--help` for the range, the speed setting and the touchpad resolution.

No desktop offers a graphical editor for this curve yet. GNOME 51 has only the
`gsettings` key. KDE has a curve editor in review for Plasma 6.9
([plasma-desktop!3569](https://invent.kde.org/plasma/plasma-desktop/-/merge_requests/3569),
depending on [kwin!6937](https://invent.kde.org/plasma/kwin/-/merge_requests/6937)).

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
