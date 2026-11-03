"""FilmLab app icon: a lens at dawn — Mt Fuji at sunrise seen through the glass, with a ring of
film-simulation colours on the barrel. Rendered at 4x and downsampled for clean edges."""
import math
import sys
import numpy as np
from PIL import Image, ImageFilter

S = 4096                      # supersampled canvas
K = S / 1024                  # 1024-pt design units -> pixels
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
X, Y = xx / K, yy / K         # coordinates in design units
CX, CY = 512.0, 512.0
R = np.hypot(X - CX, Y - CY)
ANG = np.arctan2(Y - CY, X - CX)


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def lerp(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def ramp(t, stops):
    """Piecewise-linear colour ramp; stops = [(pos, '#hex'), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
        m = (t >= p0) & (t <= p1)
        f = ((t - p0) / max(p1 - p0, 1e-6))[m]
        out[m] = hexrgb(c0) * (1 - f[:, None]) + hexrgb(c1) * f[:, None]
    return out


def aa(d):
    """Anti-aliased coverage from a signed distance (negative = inside), in pixels."""
    return np.clip(0.5 - d * K, 0, 1)


def over(base, color, alpha):
    a = np.clip(alpha, 0, 1)[..., None]
    return base * (1 - a) + color * a


# ---------------------------------------------------------------- background tile
bg = ramp(np.hypot(X - 512, Y - 430) / 760, [(0, "#2a2a2f"), (0.55, "#141416"), (1, "#070708")])

img = bg.copy()
# warm sunrise glow spilling from behind the lens
img = over(img, hexrgb("#f2a46f"), np.exp(-(np.hypot(X - 560, Y - 470) / 470) ** 2) * 0.16)

# soft drop shadow under the lens
shadow = np.clip(1 - (R - 360) / 90, 0, 1) ** 2 * 0.55
shadow *= np.clip((Y - 300) / 400, 0.3, 1)
img = over(img, np.zeros(3), shadow * (R > 300))

# ---------------------------------------------------------------- lens barrel
R_OUT, R_KNURL, R_BAND_O, R_BAND_I, R_BEZEL, R_GLASS = 432, 368, 359, 335, 326, 312

light = 0.5 + 0.5 * np.cos(ANG - math.radians(-130))      # lit from the top-left
metal = lerp(hexrgb("#1c1c20"), hexrgb("#7a7a82"), light ** 1.6)
# knurled grip: fine radial ridges
ridges = 0.5 + 0.5 * np.cos(ANG * 180)
knurl = metal * (0.78 + 0.22 * ridges[..., None])
ring = np.where(((R > R_KNURL) & (R < R_OUT - 10))[..., None], knurl, metal)
# chamfered outer lip and inner step catch the light
lip = np.exp(-((R - (R_OUT - 5)) / 3.5) ** 2) * (0.25 + 0.75 * light)
step = np.exp(-((R - R_KNURL) / 2.5) ** 2) * (0.2 + 0.8 * light)
ring = ring + (lip + step)[..., None] * 0.45
img = over(img, ring, aa(R - R_OUT))

# ---------------------------------------------------------------- film-simulation colour band
SIMS = ["#5b8fd6", "#e2445c", "#f0a6a0", "#4f8a8b", "#6dbe7a", "#e8c9a0",
        "#a3a35b", "#e59b3a", "#7fa6a0", "#c9c9c9", "#b08a5b", "#8f7fc6"]
n = len(SIMS)
band = np.zeros_like(img)
seg = ((ANG + math.pi) / (2 * math.pi) * n) % n
idx = np.floor(seg).astype(int) % n
frac = seg - np.floor(seg)
for i, c in enumerate(SIMS):
    band[idx == i] = hexrgb(c)
gap = np.minimum(frac, 1 - frac) * (2 * math.pi * 325 / n)   # distance to segment edge, in units
seg_cov = np.clip((gap - 3.0) * K, 0, 1)
band = band * (0.82 + 0.18 * light[..., None])                  # same lighting as the metal
band_cov = aa(R - R_BAND_O) * aa(R_BAND_I - R) * seg_cov
img = over(img, np.full(3, 0.04), aa(R - R_BAND_O) * (R > R_BAND_I - 1))   # dark channel
img = over(img, band, band_cov)

# ---------------------------------------------------------------- bezel
bezel = lerp(hexrgb("#050506"), hexrgb("#2b2b30"), light ** 2)
img = over(img, bezel, aa(R - R_BEZEL))
img = over(img, hexrgb("#9a9aa2"), np.exp(-((R - R_BEZEL + 1.5) / 1.6) ** 2) * light * 0.6)

# ---------------------------------------------------------------- the scene in the glass
_X, _Y = X, Y
SC = R_GLASS / 292
X = CX + (_X - CX) / SC
Y = CY + (_Y - CY) / SC
HORIZON = 600.0
sky = ramp((Y - 210) / (HORIZON - 210), [(0, "#1f2a44"), (0.35, "#56608a"), (0.68, "#c98f8f"), (0.9, "#f2b088"), (1, "#f8cf9c")])
scene = sky.copy()

# sun with glow, just right of the summit
SX, SY, SR = 650.0, 468.0, 30.0
sd = np.hypot(X - SX, Y - SY)
scene = over(scene, hexrgb("#ffd9a8"), np.exp(-(sd / 150) ** 2) * 0.55)
scene = over(scene, hexrgb("#fff1d6"), aa(sd - SR))


def fuji_height(x):
    """Ridge line of the mountain (y in units, smaller = higher)."""
    dx = np.abs(x - 512)
    flat = 34                                   # Fuji's truncated summit
    t = np.clip((dx - flat) / 340, 0, 1)
    rim = 2.5 * np.sin(x * 0.09) * (dx < flat + 4)          # crater rim
    return 420 + 186 * (1 - (1 - t) ** 1.9) + rim


ridge = fuji_height(X)
mountain = ramp((Y - 410) / (HORIZON - 410), [(0, "#3a4566"), (1, "#1a2033")])
# light side of the slope (sun on the right)
mountain = lerp(mountain, mountain * 1.25 + 0.03, np.clip((X - 512) / 300, 0, 1) * 0.6)
m_cov = np.clip((Y - ridge) * K + 0.5, 0, 1) * (Y < HORIZON + 2)
scene = over(scene, mountain, m_cov)

# snow cap with gullies
u = X - 512
gullies = (6 * np.sin(u * 0.13 + 0.7) + 4 * np.sin(u * 0.29 + 2.1) + 3 * np.sin(u * 0.61 + 0.3))
streaks = 9 * np.clip(np.sin(u * 0.21 + 1.3), 0, 1) ** 6        # a few long snow fingers
snow_line = 478 + gullies + streaks - np.clip(np.abs(u) - 60, 0, None) * 0.18
snow = lerp(hexrgb("#cfd6e6"), hexrgb("#fff3e2"), np.clip((X - 455) / 130, 0, 1))
s_cov = m_cov * np.clip((snow_line - Y) * K + 0.5, 0, 1)
scene = over(scene, snow, s_cov)

# lake: reflected sky and a sun streak
lake_t = (Y - HORIZON) / 140
lake = ramp(lake_t, [(0, "#d99a7c"), (0.25, "#6b5d78"), (1, "#141a2a")])
streak = np.exp(-((X - SX) / (10 + (Y - HORIZON) * 0.35)) ** 2) * (0.5 + 0.5 * np.sin(Y * 1.1)) * np.exp(-lake_t * 1.6)
lake = over(lake, hexrgb("#ffe0b0"), streak * 0.8)
scene = np.where((Y > HORIZON)[..., None], lake, scene)
# mountain reflection, faint
mirror = fuji_height(X)
refl_cov = np.clip(((2 * HORIZON - mirror) - Y) * K + 0.5, 0, 1) * (Y > HORIZON) * 0.35
scene = over(scene, hexrgb("#1a2033"), refl_cov)
# dark shoreline
trees = HORIZON - 3 - 3.5 * np.abs(np.sin(X * 0.21)) * np.abs(np.sin(X * 0.047 + 1))
shore = HORIZON + 5
scene = over(scene, hexrgb("#0d111b"), np.clip((Y - trees) * K, 0, 1) * np.clip((shore - Y) * K, 0, 1))

X, Y = _X, _Y
# glass: vignette, coating tint, reflections
vign = np.clip((R - 150) / (R_GLASS - 150), 0, 1) ** 2.2
scene = scene * (1 - 0.55 * vign[..., None])
scene = over(scene, hexrgb("#5b3fa0"), np.exp(-((R - R_GLASS + 10) / 9) ** 2) * 0.25)   # violet coating edge
img = over(img, scene, aa(R - R_GLASS))

# top-left crescent reflection
c1 = np.hypot(X - (CX - 40), Y - (CY - 40))
c2 = np.hypot(X - (CX + 10), Y - (CY + 10))
cres = aa(c1 - 286) * np.clip((c2 - 262) * K, 0, 1) * np.clip((-(X - CX) - (Y - CY) + 40) / 300, 0, 1)
img = over(img, np.ones(3), cres * 0.35)
# small specular highlight
spec = np.hypot(X - 362, Y - 350)
img = over(img, np.ones(3), np.exp(-(spec / 14) ** 2) * 0.8)
img = over(img, np.ones(3), np.exp(-(np.hypot(X - 392, Y - 384) / 6) ** 2) * 0.6)

# ---------------------------------------------------------------- output
def save(arr, alpha, path):
    rgb = (np.clip(arr, 0, 1) * 255).astype(np.uint8)
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    im = Image.fromarray(np.dstack([rgb, a])).resize((1024, 1024), Image.LANCZOS)
    if alpha.min() >= 1:
        im = im.convert("RGB")
    im.save(path)


out = sys.argv[1]
ones = np.ones_like(R)
save(img, ones, f"{out}/AppIcon.png")
# Dark appearance: the lens on its own; iOS draws its dark backdrop behind it.
lens_alpha = aa(R - R_OUT)
save(img, lens_alpha, f"{out}/AppIcon-Dark.png")
# Tinted appearance: luminance only; iOS applies the user's tint.
lum = img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114
lum = np.clip((lum - 0.05) * 1.25, 0, 1)
save(np.repeat(lum[..., None], 3, axis=2), lens_alpha, f"{out}/AppIcon-Tinted.png")
print("ok")
