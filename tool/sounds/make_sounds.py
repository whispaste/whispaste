#!/usr/bin/env python3
"""Synthesizes the WhisPaste sound sets (pure stdlib, no samples).

Each set: logo (onboarding / first start), start, stop, success, error, paste;
Bernstein also has the onboarding music bed (intro, -24 LUFS, maintainer
choice "Bernstein-Auftakt").
Idea: breath ("whisper") -> clear tone -> soft settle ("paste").

Every file is normalized to its loudness target after synthesis: the logo to
-20 LUFS, the family cues to -32 LUFS (ITU-R BS.1770 integrated loudness), the
paste cue to a -26 dBFS peak. Files start and end with a fade, so no click.

Usage:
  python3 tool/sounds/make_sounds.py                  # every set into assets/sounds/<set>/
  python3 tool/sounds/make_sounds.py --only bernstein/logo
  python3 tool/sounds/make_sounds.py --out /tmp/x     # another output root
  python3 tool/sounds/make_sounds.py --intro --out D  # music-bed candidates into D

The noise generator is seeded once and every set is always synthesized in the
same order, so --only writes the same bytes as a full run.
"""
import argparse
import array
import math
import os
import random
import wave

SR = 48000
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "assets", "sounds")
ONLY = None  # set of "<set>/<cue>" to write, None = all
random.seed(7)

# Loudness targets per cue (decision "Sound sets + referral", 2026-10-29).
LOGO_LUFS = -20.0
FAMILY_LUFS = -32.0
PASTE_PEAK_DBFS = -26.0
INTRO_LUFS = -24.0


def silence(sec):
    return [0.0] * int(sec * SR)


def mix(dst, src, at=0.0, gain=1.0):
    off = int(at * SR)
    need = off + len(src)
    if len(dst) < need:
        dst.extend([0.0] * (need - len(dst)))
    for i, v in enumerate(src):
        dst[off + i] += v * gain
    return dst


def env_ad(n, attack, decay_tau):
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        if i < a:
            out.append(0.5 - 0.5 * math.cos(math.pi * i / a))
        else:
            out.append(math.exp(-(i - a) / (decay_tau * SR)))
    return out


def tone(freq, dur, attack=0.005, tau=0.4, partials=((1, 1.0),), fm=None, detune=0.0):
    """Additive / FM tone. partials: (ratio, amp); fm: (ratio, index, index_tau)."""
    n = int(dur * SR)
    env = env_ad(n, max(attack, 0.004), tau)
    # raised-cosine release over the last 40 ms so a tone never ends with a cut
    rel = min(n, int(0.04 * SR))
    for i in range(rel):
        env[n - rel + i] *= 0.5 + 0.5 * math.cos(math.pi * i / rel)
    out = []
    f = freq * (1 + detune)
    for i in range(n):
        t = i / SR
        mod = 0.0
        if fm:
            r, idx, itau = fm
            mod = idx * math.exp(-t / itau) * math.sin(2 * math.pi * f * r * t)
        s = 0.0
        for ratio, amp in partials:
            s += amp * math.sin(2 * math.pi * f * ratio * t + mod)
        out.append(s * env[i])
    return out


def breath(dur, peak_at, cutoff=0.06, gain=1.0):
    """Filtered noise swell, like an exhale."""
    n = int(dur * SR)
    lp = bp = 0.0
    out = []
    p = peak_at * SR
    for i in range(n):
        x = random.uniform(-1, 1)
        lp += cutoff * (x - lp)
        bp += 0.5 * cutoff * (lp - bp)
        hp = lp - bp
        if i < p:
            e = (i / p) ** 2
        else:
            e = math.exp(-(i - p) / (0.18 * SR))
        out.append(hp * e * gain * 3.0)
    return out


def click(dur=0.05, freq=2400, gain=1.0):
    """Soft tap: a short, low-passed pluck instead of a hard click (no noise burst)."""
    return [v * gain for v in tone(freq * 0.5, max(dur, 0.12), 0.004, 0.03, ((1, 1.0), (2.0, 0.15)))]


def reverb(x, wet=0.3, size=1.0, damp=0.3):
    """Small Schroeder reverb (4 combs + 2 allpasses)."""
    combs = [int(d * size) for d in (1557, 1617, 1491, 1422)]
    fb = 0.84
    tail = int(2.5 * SR * size)
    src = x + [0.0] * tail
    acc = [0.0] * len(src)
    for d in combs:
        buf = [0.0] * d
        idx = 0
        filt = 0.0
        for i, v in enumerate(src):
            y = buf[idx]
            filt = y * (1 - damp) + filt * damp
            buf[idx] = v + filt * fb
            idx = (idx + 1) % d
            acc[i] += y
    for d in (225, 556):
        buf = [0.0] * d
        idx = 0
        for i, v in enumerate(acc):
            b = buf[idx]
            y = -v + b
            buf[idx] = v + b * 0.5
            idx = (idx + 1) % d
            acc[i] = y
    out = [src[i] * (1 - wet) + acc[i] * wet * 0.25 for i in range(len(src))]
    # trim trailing silence
    end = len(out)
    while end > 1 and abs(out[end - 1]) < 1e-4:
        end -= 1
    return out[:end]


def fade_out(x, sec=0.05):
    n = min(len(x), int(sec * SR))
    for i in range(n):
        x[len(x) - n + i] *= 1 - i / n
    return x


def _biquad(x, b, a):
    y = []
    x1 = x2 = y1 = y2 = 0.0
    b0, b1, b2 = b
    _, a1, a2 = a
    for v in x:
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y.append(o)
    return y


def integrated_lufs(channels):
    """ITU-R BS.1770-4 integrated loudness at 48 kHz (K-weighting, gating)."""
    shelf = ((1.53512485958697, -2.69169618940638, 1.19839281085285),
             (1.0, -1.69065929318241, 0.73248077421585))
    hpf = ((1.0, -2.0, 1.0), (1.0, -1.99004745483398, 0.99007225036621))
    weighted = [_biquad(_biquad(ch, *shelf), *hpf) for ch in channels]
    block, step = int(0.4 * SR), int(0.1 * SR)
    n = len(weighted[0])
    powers = []
    for start in range(0, max(1, n - block + 1), step):
        z = 0.0
        for ch in weighted:
            seg = ch[start:start + block]
            z += sum(v * v for v in seg) / block
        powers.append(z)
    loud = lambda z: -0.691 + 10 * math.log10(z) if z > 0 else -999.0
    gated = [z for z in powers if loud(z) > -70.0]
    if not gated:
        return -999.0
    rel = loud(sum(gated) / len(gated)) - 10.0
    gated = [z for z in gated if loud(z) > rel]
    return loud(sum(gated) / len(gated))


def _target(name):
    cue = name.split("-")[-1]
    if name.startswith("intro") or cue == "intro":
        return ("lufs", INTRO_LUFS)
    if cue == "paste":
        return ("peak", PASTE_PEAK_DBFS)
    if cue == "logo":
        return ("lufs", LOGO_LUFS)
    return ("lufs", FAMILY_LUFS)


def _path(name):
    """"B-bernstein-logo" -> "bernstein/logo"; intro candidates stay flat."""
    parts = name.split("-")
    if len(parts) == 3 and not name.startswith("intro"):
        return parts[1] + "/" + parts[2]
    return name


def write(name, left, right=None, peak=0.5):
    if ONLY is not None and _path(name) not in ONLY:
        return
    right = right if right is not None else left
    n = max(len(left), len(right))
    left = left + [0.0] * (n - len(left))
    right = right + [0.0] * (n - len(right))
    # 5 ms fade-in and 30 ms fade-out on the whole file: no click at either edge
    fi, fo = int(0.005 * SR), min(n, int(0.03 * SR))
    for ch in (left, right):
        for i in range(min(fi, n)):
            ch[i] *= i / fi
        for i in range(fo):
            ch[n - fo + i] *= 1 - i / fo
    m = max(max(abs(v) for v in left), max(abs(v) for v in right)) or 1.0
    g = peak / m
    left = [v * g for v in left]
    right = [v * g for v in right]
    kind, value = _target(name)
    if kind == "peak":
        g = 10 ** (value / 20) / peak
    else:
        g = 10 ** ((value - integrated_lufs([left, right])) / 20)
    data = array.array("h")
    for l, r in zip(left, right):
        data.append(int(max(-1, min(1, l * g)) * 32767))
        data.append(int(max(-1, min(1, r * g)) * 32767))
    path = os.path.join(OUT, _path(name) + ".wav")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(_path(name), f"{n / SR:.2f}s", f"{kind} {value:g}")


def stereo(build, spread=0.003):
    return build(-spread), build(spread)


# ---- Family A "Gletscher": glassy FM bells, rising fifth, airy reverb ----
def fam_a():
    glass = lambda f, d, tau, det: tone(f, d, 0.012, tau, ((1, 1.0), (2.76, 0.12)), (3.5, 0.9, 0.12), det)

    def logo(det):
        x = breath(1.4, 0.9, 0.05, 0.1)
        mix(x, glass(659.25, 2.5, 0.9, det), 0.85, 0.55)   # E5
        mix(x, glass(987.77, 2.8, 1.1, det), 1.05, 0.45)   # B5
        mix(x, tone(164.81, 3.2, 0.5, 1.2, ((1, 1), (2, 0.3)), None, det), 1.05, 0.25)  # warm E3 pad
        mix(x, click(0.05, 3000, 0.15), 2.3)                # soft settle
        return reverb(x, 0.45, 1.2, 0.35)
    write("A-gletscher-logo", *stereo(logo), peak=0.7)
    write("A-gletscher-start", reverb(mix(glass(659.25, 0.3, 0.12, 0), glass(987.77, 0.3, 0.14, 0), 0.07), 0.25, 0.6), peak=0.35)
    write("A-gletscher-stop", reverb(mix(glass(987.77, 0.3, 0.12, 0), glass(659.25, 0.3, 0.14, 0), 0.07), 0.25, 0.6), peak=0.35)
    write("A-gletscher-success", reverb(mix(mix(glass(659.25, 0.5, 0.2, 0), glass(830.61, 0.5, 0.2, 0), 0.08), glass(987.77, 0.7, 0.3, 0), 0.16), 0.3, 0.7), peak=0.35)
    write("A-gletscher-error", reverb(mix(tone(329.63, 0.35, 0.01, 0.12, ((1, 1), (2, 0.2))), tone(311.13, 0.45, 0.01, 0.16, ((1, 1), (2, 0.2))), 0.14), 0.2, 0.6), peak=0.35)
    write("A-gletscher-paste", fade_out(mix(click(0.06, 2600, 0.6), glass(1318.5, 0.12, 0.04, 0), 0.0, 0.3)), peak=0.18)


# ---- Family B "Bernstein": warm marimba-like plucks, major sixth, cozy ----
def fam_b():
    wood = lambda f, d, tau, det: tone(f, d, 0.002, tau, ((1, 1.0), (4.0, 0.25), (9.2, 0.06)), None, det)

    def logo(det):
        x = breath(1.0, 0.6, 0.04, 0.18)
        mix(x, wood(523.25, 1.6, 0.45, det), 0.55, 0.5)     # C5
        mix(x, wood(659.25, 1.6, 0.45, det), 0.72, 0.42)    # E5
        mix(x, wood(880.00, 2.0, 0.6, det), 0.89, 0.42)     # A5 (major sixth over C)
        mix(x, tone(130.81, 2.6, 0.3, 0.9, ((1, 1), (2, 0.4), (3, 0.1)), None, det), 0.89, 0.28)  # C3 warmth
        mix(x, click(0.04, 1800, 0.12), 1.8)
        return reverb(x, 0.3, 0.9, 0.5)

    def logo_soft(det):
        x = breath(1.0, 0.6, 0.04, 0.09)
        mix(x, wood(523.25, 1.6, 0.45, det), 0.55, 0.5)
        mix(x, wood(659.25, 1.6, 0.45, det), 0.72, 0.42)
        mix(x, wood(880.00, 2.0, 0.6, det), 0.89, 0.42)
        mix(x, tone(130.81, 2.6, 0.3, 0.9, ((1, 1), (2, 0.4), (3, 0.1)), None, det), 0.89, 0.28)
        mix(x, click(0.04, 1800, 0.12), 1.8)
        return reverb(x, 0.3, 0.9, 0.5)
    write("B-bernstein-logo", *stereo(logo_soft), peak=0.7)
    write("B-bernstein-start", reverb(mix(wood(523.25, 0.3, 0.1, 0), wood(880.0, 0.3, 0.12, 0), 0.06), 0.2, 0.5, 0.5), peak=0.35)
    write("B-bernstein-stop", reverb(mix(wood(880.0, 0.3, 0.1, 0), wood(523.25, 0.3, 0.12, 0), 0.06), 0.2, 0.5, 0.5), peak=0.35)
    write("B-bernstein-success", reverb(mix(mix(wood(523.25, 0.4, 0.15, 0), wood(659.25, 0.4, 0.15, 0), 0.07), wood(1046.5, 0.6, 0.25, 0), 0.14), 0.25, 0.6, 0.5), peak=0.35)
    write("B-bernstein-error", reverb(mix(wood(349.23, 0.35, 0.12, 0), wood(329.63, 0.45, 0.16, 0), 0.13), 0.2, 0.5, 0.5), peak=0.35)
    write("B-bernstein-paste", fade_out(mix(click(0.05, 1600, 0.6), wood(1046.5, 0.1, 0.03, 0), 0.0, 0.25)), peak=0.18)


# ---- Family C "Atem": minimal, breath + pure sine, octave shimmer ----
def fam_c():
    pure = lambda f, d, tau, det: tone(f, d, 0.02, tau, ((1, 1.0), (2, 0.12)), None, det)

    def logo(det):
        x = breath(1.6, 1.1, 0.07, 0.12)
        mix(x, pure(587.33, 2.6, 1.0, det), 1.0, 0.6)      # D6-ish clear tone (D5)
        mix(x, pure(1174.66, 2.0, 0.6, det), 1.25, 0.18)   # octave shimmer
        mix(x, click(0.03, 3400, 0.1), 2.4)
        return reverb(x, 0.5, 1.3, 0.25)
    write("C-atem-logo", *stereo(logo), peak=0.65)
    write("C-atem-start", reverb(mix(breath(0.15, 0.08, 0.1, 0.08), pure(587.33, 0.35, 0.15, 0), 0.06), 0.25, 0.6, 0.3), peak=0.32)
    write("C-atem-stop", reverb(mix(pure(587.33, 0.3, 0.1, 0), pure(440.0, 0.35, 0.14, 0), 0.08), 0.25, 0.6, 0.3), peak=0.32)
    write("C-atem-success", reverb(mix(pure(587.33, 0.4, 0.15, 0), pure(880.0, 0.6, 0.25, 0), 0.1), 0.3, 0.7, 0.3), peak=0.32)
    write("C-atem-error", reverb(mix(pure(293.66, 0.3, 0.1, 0), pure(277.18, 0.4, 0.14, 0), 0.12), 0.2, 0.6, 0.3), peak=0.32)
    write("C-atem-paste", fade_out(click(0.04, 3200, 0.6)), peak=0.15)


# ---- Intro music bed candidates (onboarding start only, at most ~4 s) ----
def _clip(x, sec, fade=0.6):
    x = x[: int(sec * SR)]
    return fade_out(x, fade)


def intro(candidates=True):
    """The onboarding music bed: the chosen Bernstein-Auftakt goes to
    bernstein/intro; with [candidates] both audition files are written flat."""
    random.seed(11)
    wood = lambda f, d, tau, det: tone(f, d, 0.002, tau, ((1, 1.0), (4.0, 0.25), (9.2, 0.06)), None, det)
    glass = lambda f, d, tau, det: tone(f, d, 0.012, tau, ((1, 1.0), (2.76, 0.12)), (3.5, 0.9, 0.12), det)
    pad = lambda f, d, det: tone(f, d, 0.6, 1.6, ((1, 1), (2, 0.35), (3, 0.08)), None, det)

    def warm(det):
        # Bernstein: breath, rising marimba arpeggio over a warm pad, settle on the sixth
        x = breath(0.9, 0.6, 0.04, 0.08)
        for i, f in enumerate((523.25, 659.25, 783.99, 880.0)):
            mix(x, wood(f, 1.4, 0.4, det), 0.45 + 0.22 * i, 0.42)
        mix(x, pad(130.81, 3.4, det), 0.45, 0.22)
        mix(x, pad(196.0, 3.0, det), 0.9, 0.12)
        mix(x, wood(1046.5, 1.6, 0.5, det), 1.75, 0.3)
        return _clip(reverb(x, 0.3, 0.9, 0.5), 3.9)

    def airy(det):
        # Gletscher-leaning: slow pad swell, two glass bells, long air
        x = breath(1.4, 1.0, 0.05, 0.07)
        mix(x, pad(130.81, 3.8, det), 0.0, 0.2)
        mix(x, pad(164.81, 3.6, det), 0.2, 0.14)
        mix(x, pad(220.0, 3.4, det), 0.4, 0.1)
        mix(x, glass(659.25, 2.2, 0.9, det), 1.1, 0.4)
        mix(x, glass(880.0, 2.2, 1.0, det), 1.6, 0.32)
        return _clip(reverb(x, 0.45, 1.2, 0.35), 4.0, 0.9)

    bed = stereo(warm)
    write("B-bernstein-intro", *bed, peak=0.7)
    if candidates:
        write("intro1-bernstein-auftakt", *bed, peak=0.7)
        write("intro2-gletscher-hauch", *stereo(airy), peak=0.7)


def main():
    global OUT, ONLY
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", help="output root (default: assets/sounds)")
    ap.add_argument("--only", action="append", help="<set>/<cue>, repeatable")
    ap.add_argument("--intro", action="store_true", help="music-bed candidates only")
    args = ap.parse_args()
    if args.out:
        OUT = os.path.abspath(args.out)
    if args.intro:
        intro()
        return
    ONLY = set(args.only) if args.only else None
    fam_a()
    fam_b()
    fam_c()
    intro(candidates=False)


if __name__ == "__main__":
    main()
