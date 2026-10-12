# Zenbook A16 touchpad on Linux

libinput plugins and a pointer acceleration curve for the touchpad of the
ASUS Zenbook A16 (UX3607OA, `hid-over-i2c 2808:0219 Touchpad`) under GNOME on
Wayland. Tested with libinput 1.32, mutter 51 and Fedora 45.

The touchpad reports only finger positions, with no pressure and no contact
size. libinput therefore cannot tell a resting thumb from a finger, and it
cannot tell that a finger is lifting. The plugins below fill those gaps. They
change the touch events before libinput sees them.

The default sizes fit the author, who is right handed. The left thumb rests
on the top edge of the touchpad while typing, and the right palm rests along
the right edge. For a left-handed user, mirror the zones: move the thumb zone
to the top right corner and the palm strip to the left edge. Each size is a
variable at the top of its plugin file.

## Plugins

`20-thumb-zone.lua` hides touches that start in two zones, so a resting thumb
or palm never reaches libinput. Without it, the thumb turned pointer motion
into two-finger scrolling. libinput's own thumb detection also mistook the
index finger for a thumb and dropped its taps. If a hidden touch moves 5 mm
out of its zone towards the center, it becomes visible again. If three
fingers are down, a touch in the right strip becomes visible too. A resting
palm never comes with two more fingers, but a three-finger swipe does.

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

`30-rest-deadzone.lua` removes the phantom scroll that appeared after a
two-finger scroll ended. When a finger comes to rest before the lift, the
fingertip rolls off the surface, and the touchpad reports that roll as motion.
The plugin holds a finger that stays within `REST_MM` (0.2 mm) for `REST_MS`
(100 ms). It releases the finger after `RELEASE_MM` (0.6 mm) of travel.

`35-lift-trim.lua` removes the same roll-off for fingers that lift while they
still move. It delays two-finger motion by `DELAY_MS` (25 ms). When a finger
lifts, it discards the delayed motion, so libinput never sees the last 25 ms.
The cost is 25 ms of scroll latency. Chromium browsers still fling after a
fast lift. That fling comes from Chromium's own kinetic scrolling, and it is
proportional to the finger speed at the lift.

`40-scroll-scale.lua` slows down two-finger scrolling. With the custom
acceleration curve below, libinput scrolls at 1:1 of the finger motion. That
is three times the speed of the default profile, and GNOME has no scroll
speed setting. The plugin forwards `SCALE` (0.33) of the motion while two
fingers are down, which matches the default profile. The first `LEAD_MM`
(1.7 mm) of each gesture pass unscaled. libinput decides from the motion it
sees whether two fingers scroll or pinch, and scaled motion made scrolls
start late. `SWIPE_SCALE` (1.0) does the same for three and four fingers. It
is off by default, because GNOME Shell completes a workspace switch only
after enough travel.

## Acceleration curve

GNOME 51 can hand libinput a custom pointer acceleration curve. The curve in
`tests/accel-curve.py` copies libinput's default touchpad curve at the speed
setting it was generated for. Below 14 mm/s it is unchanged, so slow, precise
movement stays the same. Between about 25 and 230 mm/s it raises the gain by
up to 15%, where the default felt sluggish. Fast flicks return to the
default. The script prints the curve. Apply it with:

```sh
gsettings set org.gnome.desktop.peripherals.touchpad custom-accel-config \
    "{'pointer-step': <0.15>, 'pointer-speeds': <[...points from the script...]>}"
gsettings set org.gnome.desktop.peripherals.touchpad accel-profile custom
```

`accel-profile default` switches back. The curve applies only to pointer
motion. Scrolling runs at 1:1 under the custom profile, and plugin 40
compensates for that.

## Install

```sh
sudo cp *.lua /etc/libinput/plugins/
```

Log out and back in, because GNOME loads libinput plugins only at session
start. To try a change without logging out, run
`sudo libinput debug-events --enable-plugins --device /dev/input/eventN`
with the touchpad's event node. To use the plugins with another touchpad,
change `DEVICE_NAME` at the top of each file.

The plugins were tuned from `libinput record` captures of real use. The mock
tests in `tests/` replay such captures through the plugins and check the
events that reach libinput. See `tests/README.md`.
