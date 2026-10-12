#!/usr/bin/env python3
"""Generate a custom pointer acceleration curve for GNOME 51 and libinput.

The curve is libinput 1.32's default touchpad curve with the gain raised in a
middle speed range. It prints the gsettings commands that apply it.

    ./accel-curve.py                 # 35% boost, full between 40 and 200 mm/s
    ./accel-curve.py --boost 50
    ./accel-curve.py --boost 20 --from 60 --to 150
    ./accel-curve.py --speed 0.35    # match a different pointer speed setting

The boost fades in over the 30 mm/s below --from and fades out over the
95 mm/s above --to, so speeds below 10 mm/s are never changed.
"""

import argparse

STEP = 0.15      # input speed interval between points, device units per ms
NPOINTS = 64     # libinput's maximum
MAGIC_SLOWDOWN = 0.2968
FADE_IN = 30     # mm/s below --from over which the boost ramps up
FADE_OUT = 95    # mm/s above --to over which the boost ramps down


def default_factor(v_mm_s, speed_factor):
    """libinput's adaptive touchpad acceleration factor at v mm/s."""
    threshold = 130.0
    if v_mm_s < 7:
        f = min(0.9, 0.1 * v_mm_s + 0.3)
    elif v_mm_s < threshold:
        f = 0.9
    else:
        v = min(v_mm_s, 4 * threshold)
        f = 0.0025 * (v / threshold) * (v - threshold) + 0.9
    return f * speed_factor * MAGIC_SLOWDOWN


def smoothstep(a, b, x):
    x = min(1.0, max(0.0, (x - a) / (b - a)))
    return x * x * (3 - 2 * x)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--boost", type=float, default=35, help="gain increase in the middle range, percent (default 35)")
    p.add_argument("--from", dest="lo", type=float, default=40, help="speed at which the boost is fully in, mm/s (default 40)")
    p.add_argument("--to", dest="hi", type=float, default=200, help="speed at which the boost starts to fade, mm/s (default 200)")
    p.add_argument("--speed", type=float, default=0.2735, help="GNOME pointer speed setting the default curve is taken at, -1..1 (default 0.2735)")
    p.add_argument("--resolution", type=float, default=4762 / 148, help="touchpad units per mm (default: Zenbook A16, 32.2)")
    a = p.parse_args()

    res = a.resolution
    dpi = res * 25.4
    speed_factor = (a.speed + 1) ** 2.38 * 0.95 + 0.05

    def boost(v):
        return 1 + a.boost / 100 * smoothstep(a.lo - FADE_IN, a.lo, v) * (1 - smoothstep(a.hi, a.hi + FADE_OUT, v))

    pts = []
    for i in range(NPOINTS):
        s = i * STEP                                  # input speed, units/ms
        v = s * 1000 / res                            # mm/s
        gain = default_factor(v, speed_factor) * 1000 / dpi
        pts.append(round(s * gain * boost(v), 3))

    speeds = ", ".join(f"{x:.3f}".rstrip("0").rstrip(".") if x != int(x) else f"{x:.1f}" for x in pts)
    print("gsettings set org.gnome.desktop.peripherals.touchpad custom-accel-config \\")
    print(f"    \"{{'pointer-step': <{STEP}>, 'pointer-speeds': <[{speeds}]>}}\"")
    print("gsettings set org.gnome.desktop.peripherals.touchpad accel-profile custom")


if __name__ == "__main__":
    main()
