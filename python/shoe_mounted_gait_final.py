# ============================================================
# SHOE-MOUNTED GAIT PIPELINE (FINAL - OPTIMIZED FOR DOPPLER)
#
# What's new:
# 1) Better figure utilization (no huge white margins)
# 2) Better image clarity controls:
#       - plot-only 2D smoothing (Gaussian) - OPTIMIZED for Doppler
#       - vmin/vmax percentile control - LOWERED for better detail
#       - interpolation control (bilinear for RT, none for VT)
# 3) Toe plot does NOT show the black signed curve (only toe envelope)
# 4) Outputs overall step-count error if --gt_steps is given
#     (use this overall error as baseline for fixed distance plot)
# 5) OPTIMIZED PARAMETERS for Doppler signature visualization:
#       - Lower vmin percentiles (35.0 for RT, 8.0 for VT)
#       - Minimal smoothing (0.3, 0.3) to preserve micro-Doppler
#       - No interpolation for VT to keep Doppler crisp
# ============================================================

import json
import numpy as np
import scipy.signal as sig
from scipy.ndimage import gaussian_filter1d, binary_dilation, binary_erosion
import matplotlib.pyplot as plt
from pathlib import Path
import csv
import argparse
import math

C = 299_792_458.0

# ============================================================
# GLOBAL FONT / FIGURE SETTINGS (BIG + BOLD LABELS)
# ============================================================
# Larger fonts improve readability in exported figures.  We match
# "Times New Roman" with bold labels to mirror the user's requirements.
BASE_FONT = 14
LABEL_FONT = 24
TICK_FONT = 16
TITLE_FONT = 18
CBAR_FONT = 18

# Default colormap; fall back to "jet" if unavailable
DEFAULT_CMAP = "turbo"

plt.rcParams.update({
    "font.family": "Times New Roman",
    "font.size": BASE_FONT,
    "axes.labelsize": LABEL_FONT,
    "axes.titlesize": TITLE_FONT,
    "xtick.labelsize": TICK_FONT,
    "ytick.labelsize": TICK_FONT,
    "legend.fontsize": 13,
    "axes.labelweight": "bold",
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
})

def _apply_axes_style(ax):
    """Apply consistent tick and spine styling to axes."""
    ax.tick_params(axis="both", labelsize=TICK_FONT, width=1.2)
    for sp in ax.spines.values():
        sp.set_linewidth(1.2)
    for lab in ax.get_xticklabels() + ax.get_yticklabels():
        lab.set_fontweight("bold")

# ============================================================
# SAVE HELPERS (AUTO‑TRIM PNG WHITESPACE)
# ============================================================
def _trim_png_whitespace(png_path: Path, pad_px: int = 6):
    try:
        from PIL import Image, ImageChops
    except Exception:
        return

    png_path = Path(png_path)
    if not png_path.exists():
        return

    im = Image.open(png_path).convert("RGB")
    bg = Image.new("RGB", im.size, (255, 255, 255))
    diff = ImageChops.difference(im, bg)
    bbox = diff.getbbox()
    if not bbox:
        return

    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad_px)
    y0 = max(0, y0 - pad_px)
    x1 = min(im.width, x1 + pad_px)
    y1 = min(im.height, y1 + pad_px)

    im.crop((x0, y0, x1, y1)).save(png_path)

def _save_png_pdf(fig, base_path_no_ext: Path, dpi_png=600):
    base_path_no_ext = Path(base_path_no_ext)
    try:
        fig.tight_layout(pad=0.2)
    except Exception:
        pass

    png_path = base_path_no_ext.with_suffix(".png")
    pdf_path = base_path_no_ext.with_suffix(".pdf")

    fig.savefig(str(png_path), dpi=dpi_png, bbox_inches="tight", pad_inches=0.01, facecolor="white")
    fig.savefig(str(pdf_path), bbox_inches="tight", pad_inches=0.01, facecolor="white")
    plt.close(fig)

    _trim_png_whitespace(png_path, pad_px=6)

# ============================================================
# UTILS
# ============================================================
def _db_from_power(p):
    return 10.0 * np.log10(np.maximum(p, 1e-12))

def _robust_limits(db2d, vmin_prc=60, vmax_prc=99.5, min_range_db=20.0):
    lo = float(np.percentile(db2d, vmin_prc))
    hi = float(np.percentile(db2d, vmax_prc))
    if (hi - lo) < min_range_db:
        hi = lo + min_range_db
    return lo, hi

def _time_slice_indices(t, t0, t1):
    if t0 is None or t1 is None:
        return 0, len(t)
    a = int(np.searchsorted(t, t0, side="left"))
    b = int(np.searchsorted(t, t1, side="right"))
    a = max(0, min(a, len(t)-1))
    b = max(a+1, min(b, len(t)))
    return a, b

# ============================================================
# IO
# ============================================================
def load_json(p: Path):
    with open(p, "r") as f:
        return json.load(f)

def to_complex(arr: np.ndarray) -> np.ndarray:
    if np.iscomplexobj(arr):
        return arr.astype(np.complex64, copy=False)
    if arr.ndim >= 1 and arr.shape[-1] == 2:
        return arr[..., 0].astype(np.float32) + 1j * arr[..., 1].astype(np.float32)
    return arr.astype(np.complex64)

def reorder_to_FCRS(x: np.ndarray, expected=(128, 3, 64)) -> np.ndarray:
    x = np.asarray(x)
    shp = list(x.shape)
    chirps, rx, samples = expected
    try:
        iC = shp.index(chirps)
        iR = shp.index(rx)
        iS = shp.index(samples)
    except ValueError as e:
        raise ValueError(f"Cannot find expected dims {expected} inside shape {x.shape}") from e

    rest = [i for i in range(x.ndim) if i not in (iC, iR, iS)]
    if len(rest) != 1:
        raise ValueError(f"Expected 1 frame axis, got {len(rest)} in shape {x.shape}")
    iF = rest[0]
    return np.transpose(x, (iF, iC, iR, iS))

def load_recording_folder(folder: str, expected=(128, 3, 64)):
    folder = Path(folder)
    cfg = load_json(folder / "config.json")
    meta = load_json(folder / "meta.json")
    x = np.load(folder / "radar.npy", allow_pickle=False)
    x = to_complex(x)
    x = reorder_to_FCRS(x, expected=expected)
    return x, cfg, meta

# ============================================================
# CONFIG + AXES
# ============================================================
def derive_cfg_params(config_json):
    s = config_json["device_config"]["fmcw_single_shape"]
    fs = float(s["sample_rate_Hz"])
    ns = int(s["num_samples_per_chirp"])
    nc = int(s["num_chirps_per_frame"])
    rx = len(s["rx_antennas"])
    f_start = float(s["start_frequency_Hz"])
    f_end = float(s["end_frequency_Hz"])
    Tr = float(s["chirp_repetition_time_s"])
    frame_T = float(s["frame_repetition_time_s"])

    B = f_end - f_start
    f0 = 0.5 * (f_start + f_end)
    lam = C / f0
    Tc = ns / fs
    slope = B / Tc

    return dict(
        fs=fs, num_samples=ns, num_chirps=nc, num_rx=rx,
        f_start=f_start, f_end=f_end, f0=f0, B=B, lam=lam,
        Tr=Tr, frame_T=frame_T, Tc=Tc, slope=slope
    )

def make_range_axis(cfg, nfft_r):
    fb = np.arange(nfft_r // 2) * (cfg["fs"] / nfft_r)
    return C * fb / (2.0 * cfg["slope"])

def make_velocity_axis(cfg, nfft_d):
    fd = (np.arange(nfft_d) - nfft_d / 2) / (nfft_d * cfg["Tr"])
    return (cfg["lam"] / 2.0) * fd

def range_gate_indices(r_axis, rmin, rmax):
    return np.where((r_axis >= rmin) & (r_axis <= rmax))[0]

# ============================================================
# RD/RT/VT
# ============================================================
def compute_rd_rt(adc, cfg, nfft_r=256, nfft_d=128):
    F, Cc, Rr, Ss = adc.shape
    win_r = np.hanning(Ss).astype(np.float32)
    win_d = np.blackman(Cc).astype(np.float32)

    Xr = np.fft.fft(adc * win_r[None, None, None, :], n=nfft_r, axis=-1)[..., :nfft_r // 2]
    Xr = Xr - Xr.mean(axis=1, keepdims=True)

    Xr = Xr * win_d[None, :, None, None]
    Xd = np.fft.fftshift(np.fft.fft(Xr, n=nfft_d, axis=1), axes=1)

    # REMOVED: notch around 0 Doppler (was causing black line in VT)
    # zero = nfft_d // 2
    # Xd[:, zero-1:zero+2, :, :] = 0

    p = np.sum(np.abs(Xd) ** 2, axis=2)
    rd = np.transpose(p, (0, 2, 1))   # (F, R, V)
    rt = rd.sum(axis=2)               # (F, R)
    return rd, rt

def vt_from_rd(rd, r_idx, mode="sum"):
    if mode == "sum":
        vt = rd[:, r_idx, :].sum(axis=1)  # (F, V)
    else:
        vt = rd[:, r_idx, :].max(axis=1)
    return vt.T  # (V, F)

# ============================================================
# ENVELOPES + SEGMENTS
# ============================================================
def mad(x):
    x = np.asarray(x)
    m = np.median(x)
    return np.median(np.abs(x - m)) + 1e-6

def robust_mask_db(power_2d, k_mad=6.0):
    db = 10*np.log10(power_2d + 1e-12)
    med = np.median(db)
    mm = np.median(np.abs(db - med)) + 1e-6
    return db > (med + k_mad*mm)

def clean_mask(mask, dil=2, ero=2):
    m = mask
    for _ in range(dil):
        m = binary_dilation(m)
    for _ in range(ero):
        m = binary_erosion(m)
    return m

def toe_envelope(vt, v_axis):
    mask = robust_mask_db(vt, k_mad=6.0)
    mask = clean_mask(mask, dil=2, ero=2)

    vabs = np.abs(v_axis)
    toe = np.zeros(vt.shape[1], dtype=np.float32)
    for t in range(vt.shape[1]):
        idx = np.where(mask[:, t])[0]
        toe[t] = np.percentile(vabs[idx], 98) if idx.size >= 5 else 0.0

    toe = gaussian_filter1d(toe, sigma=1.0)
    return toe, mask

def _segments_from_bool(walk_bool, frame_dt, min_walk_s=0.8, min_gap_s=0.5):
    walk = np.asarray(walk_bool, dtype=bool)
    segments = []
    n = len(walk)
    i = 0
    min_len = int(max(1, min_walk_s / frame_dt))
    min_gap = int(max(1, min_gap_s / frame_dt))

    while i < n:
        if not walk[i]:
            i += 1
            continue
        a = i
        while i < n and walk[i]:
            i += 1
        b = i
        if (b - a) >= min_len:
            segments.append([a, b])

    merged = []
    for seg in segments:
        if not merged:
            merged.append(seg)
            continue
        if seg[0] - merged[-1][1] < min_gap:
            merged[-1][1] = seg[1]
        else:
            merged.append(seg)
    return [(int(a), int(b)) for a, b in merged]

def find_walking_segments(toe, frame_dt, segments_mode="hysteresis", walk_k=0.15, min_walk_s=0.8, min_gap_s=0.5):
    toe_s = gaussian_filter1d(np.asarray(toe), sigma=1.0)
    base = np.median(toe_s)
    spread = mad(toe_s)

    if segments_mode == "none":
        return [], None, None

    if segments_mode == "basic":
        thr = base + walk_k * spread
        walk = toe_s > thr
        walk = binary_dilation(walk, iterations=8)
        walk = binary_erosion(walk, iterations=2)
        segs = _segments_from_bool(walk, frame_dt, min_walk_s=min_walk_s, min_gap_s=min_gap_s)
        return segs, float(thr), float(thr)

    thr_on = base + walk_k * spread
    thr_off = base + (walk_k * 0.92) * spread

    walk = np.zeros_like(toe_s, dtype=bool)
    state = False
    for i, v in enumerate(toe_s):
        if not state and v >= thr_on:
            state = True
        elif state and v <= thr_off:
            state = False
        walk[i] = state

    walk = binary_dilation(walk, iterations=6)
    walk = binary_erosion(walk, iterations=2)

    segs = _segments_from_bool(walk, frame_dt, min_walk_s=min_walk_s, min_gap_s=min_gap_s)
    return segs, float(thr_on), float(thr_off)

def build_walking_mask(n_frames, segments, frame_dt, pad_s=0.0):
    mask = np.zeros(n_frames, dtype=bool)
    pad = int(max(0, pad_s / frame_dt))
    for (a, b) in segments:
        a2 = max(0, a - pad)
        b2 = min(n_frames, b + pad)
        mask[a2:b2] = True
    return mask

# ============================================================
# RANGE CENTROID
# ============================================================
def range_centroid(rt, r_axis, r_idx):
    rt_g = rt[:, r_idx]
    r = r_axis[r_idx]
    denom = rt_g.sum(axis=1) + 1e-12
    num = (rt_g * r[None, :]).sum(axis=1)
    rc = num / denom
    return gaussian_filter1d(rc, sigma=1.5)

# ============================================================
# STEP DETECTION
# ============================================================
def detect_steps_from_toe(
    toe,
    frame_dt,
    prom_k=0.02,
    prom_floor=0.010,
    height_prc=10,
    min_step_height_mps=0.20,
):
    toe = np.asarray(toe, dtype=np.float32)
    min_dist = max(1, int(0.18 / frame_dt))
    prom = max(prom_k * mad(toe), prom_floor)

    height_thr = float(np.percentile(toe, height_prc))
    height_thr = max(height_thr, float(min_step_height_mps))

    peaks, _ = sig.find_peaks(toe, prominence=prom, height=height_thr, distance=min_dist)
    return np.asarray(peaks, dtype=int), float(height_thr), float(prom)

def compute_step_table(peaks, rc_m, v_axis, vt, frame_dt):
    peaks = np.sort(np.asarray(peaks, dtype=int))
    rows = []

    vpos = np.where(v_axis > 0)[0]
    vneg = np.where(v_axis < 0)[0]

    for i, p in enumerate(peaks, start=1):
        t = p * frame_dt
        step_t = 0.0 if i == 1 else (p - peaks[i-2]) * frame_dt

        col = vt[:, p]
        v_app = float(abs(v_axis[vneg[np.argmax(col[vneg])]])) if vneg.size else 0.0
        v_sep = float(abs(v_axis[vpos[np.argmax(col[vpos])]])) if vpos.size else 0.0

        d_align_cm = float(rc_m[p] * 100.0)
        rows.append([i, f"{t:.3f}", f"{step_t:.3f}", f"{v_app:.3f}", f"{v_sep:.3f}", f"{d_align_cm:.2f}"])
    return rows

def symmetry_index_from_alt_steps(values):
    v = np.asarray(values, dtype=float)
    if v.size < 4:
        return 0.0
    odd = v[0::2]
    even = v[1::2]
    m1 = float(np.mean(odd)) if odd.size else 0.0
    m2 = float(np.mean(even)) if even.size else 0.0
    denom = (m1 + m2) / 2.0 + 1e-12
    return float(abs(m1 - m2) / denom)

def split_peaks_by_segments(peaks, segments):
    peaks = np.sort(np.asarray(peaks, dtype=int))
    out = []
    for (a, b) in segments:
        p = peaks[(peaks >= a) & (peaks < b)]
        if p.size:
            out.append(p)
    return out

def step_intervals_within_segments(peaks, segments, frame_dt):
    seg_peaks = split_peaks_by_segments(peaks, segments)
    dts = []
    for p in seg_peaks:
        p = np.asarray(p, dtype=int)
        if p.size >= 2:
            dts.append(np.diff(p) * frame_dt)
    return np.concatenate(dts) if dts else np.array([], dtype=float)

def stride_intervals_within_segments(peaks, segments, frame_dt):
    seg_peaks = split_peaks_by_segments(peaks, segments)
    dts = []
    for p in seg_peaks:
        p = np.asarray(p, dtype=int)
        if p.size >= 3:
            dts.append((p[2:] - p[:-2]) * frame_dt)
    return np.concatenate(dts) if dts else np.array([], dtype=float)

def mean_and_cv(x):
    x = np.asarray(x, dtype=float)
    if x.size == 0:
        return 0.0, 0.0
    m = float(np.mean(x))
    cv = float(100.0 * (np.std(x) / (m + 1e-12)))
    return m, cv

def fog_count_within_segments(peaks, segments, frame_dt, max_step_gap_s=1.5):
    dt = step_intervals_within_segments(peaks, segments, frame_dt)
    if dt.size == 0:
        return 0
    return int(np.sum(dt > max_step_gap_s))

# ============================================================
# CSV + REPORT CARD
# ============================================================
def _pick_num_columns(n_steps: int) -> int:
    if n_steps <= 50: return 1
    if n_steps <= 100: return 2
    if n_steps <= 150: return 3
    return 4

def save_csv(output_path, report, step_rows):
    output_path = Path(output_path)
    with open(output_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["=== GLOBAL GAIT SUMMARY (SHOE) ==="])
        w.writerow([])
        w.writerow(["Parameter", "Value"])
        for k, v in report.items():
            w.writerow([k, v])
        w.writerow([])
        w.writerow(["=== PER-STEP DATA (STEPS USED FOR STATS) ==="])
        w.writerow([])
        w.writerow(["Step", "Time(s)", "Step(s)", "v_app", "v_sep", "d_align(cm)"])
        for r in step_rows:
            w.writerow(r)
    print(f"✓ CSV saved: {output_path.absolute()}")

def save_report_card_png(output_folder, report, step_rows, filename="Gait_Analysis_Report_Card_SHOE.png"):
    output_folder = Path(output_folder)
    output_path = output_folder / filename

    n = len(step_rows)
    ncols = _pick_num_columns(n)
    rows_per_col = int(math.ceil(n / ncols)) if n > 0 else 1

    fig_w = max(14, 6.8 * ncols)
    fig_h = 14
    dpi = 350

    fig = plt.figure(figsize=(fig_w, fig_h), dpi=dpi, facecolor="white")
    gs = fig.add_gridspec(2, 1, height_ratios=[0.34, 0.66], hspace=0.05)

    ax_sum = fig.add_subplot(gs[0])
    ax_sum.axis("off")

    fig.suptitle("GAIT ANALYSIS DATA REPORT CARD (SHOE)", fontsize=22, fontweight="bold",
                 y=0.985, fontfamily="Times New Roman")

    ax_sum.text(0.02, 0.92, "GLOBAL SUMMARY", fontsize=16, fontweight="bold",
                fontfamily="Times New Roman", transform=ax_sum.transAxes)

    items = list(report.items())
    y = 0.84
    dy = 0.075
    for k, v in items[:12]:
        ax_sum.text(0.05, y, f"{k}:", fontsize=13, fontweight="bold",
                    fontfamily="Times New Roman", transform=ax_sum.transAxes)
        ax_sum.text(0.52, y, f"{v}", fontsize=13,
                    fontfamily="Times New Roman", transform=ax_sum.transAxes)
        y -= dy

    fig.text(0.02, 0.62, f"PER-STEP DATA (n={n})",
             fontsize=16, fontweight="bold", fontfamily="Times New Roman")

    sub = gs[1].subgridspec(1, ncols, wspace=0.06)
    headers = ["Step", "Time(s)", "Step(s)", "v_app", "v_sep", "d_align(cm)"]

    header_bg = "#2C3E50"
    even_bg = "#EBF5FB"
    border = "#BDC3C7"

    for col in range(ncols):
        ax = fig.add_subplot(sub[0, col])
        ax.axis("off")

        start = col * rows_per_col
        end = min((col + 1) * rows_per_col, n)
        chunk = step_rows[start:end]

        table = ax.table(
            cellText=chunk,
            colLabels=headers,
            cellLoc="center",
            colLoc="center",
            bbox=[0.00, 0.02, 1.00, 0.96],
        )
        table.auto_set_font_size(False)
        table.set_fontsize(10 if n > 80 else 11)
        table.scale(1, 1.45)

        for (r, c), cell in table.get_celld().items():
            if r == 0:
                cell.set_facecolor(header_bg)
                cell.get_text().set_color("white")
                cell.get_text().set_weight("bold")
                cell.set_edgecolor("white")
                cell.set_linewidth(1.5)
            else:
                cell.set_facecolor(even_bg if r % 2 == 0 else "white")
                cell.set_edgecolor(border)
                cell.set_linewidth(0.8)
                cell.get_text().set_fontfamily("monospace")

    fig.savefig(output_path, dpi=dpi, bbox_inches="tight", pad_inches=0.25, facecolor="white")
    plt.close(fig)
    print(f"✓ Report card saved: {output_path.absolute()}")

# ============================================================
# PLOTS - OPTIMIZED FOR DOPPLER SIGNATURES WITH BIG BOLD LABELS
# ============================================================
def save_separate_plots_shoe(
    out_folder: Path,
    rt: np.ndarray,
    vt: np.ndarray,
    toe: np.ndarray,
    r_axis: np.ndarray,
    v_axis: np.ndarray,
    frame_dt: float,
    walk_segments,
    steps_all: np.ndarray,
    steps_used: np.ndarray,
    min_step_height_mps: float,
    report_rows,
    r_gate=(0.10, 1.20),
    v_plot_lim=(-3.8, 3.8),
    zoom_time_range=None,
    # OPTIMIZED PARAMETERS FOR DOPPLER SIGNATURES
    rt_vmin_percentile=35.0,  # Lowered from 60 for better RT contrast
    vt_vmin_percentile=8.0,   # Lowered to reveal Doppler detail
    vmax_percentile=99.7,      # Keep high to preserve peak intensity
    smooth_sigma_y=0.3,        # Reduced from 0.8 for minimal blur
    smooth_sigma_x=0.3,        # Reduced from 0.8 for minimal blur
    rt_interpolation="bilinear",  # Smooth for RT
    vt_interpolation="none",      # Crisp for VT Doppler
):
    """Save individual heatmaps with optimized parameters for Doppler signature visualization.
    
    Key optimizations:
    - Lower vmin percentiles to reveal more Doppler detail
    - Minimal smoothing to preserve micro-Doppler features
    - No interpolation for VT to keep Doppler crisp
    - Bilinear interpolation for RT for smoother appearance
    - BIG BOLD LABELS matching fixed-radar pipeline
    - FIXED: RT plot extent matches actual data range to avoid white space
    - FIXED: Removed notch filter to eliminate black line in VT
    """
    from mpl_toolkits.axes_grid1 import make_axes_locatable
    from scipy.ndimage import gaussian_filter

    out_folder = Path(out_folder)
    out_folder.mkdir(parents=True, exist_ok=True)

    t = np.arange(rt.shape[0]) * frame_dt

    def _heatmap(fig_w, fig_h, power2d, extent, xlabel, ylabel, outname, ylim=None, vmin_prc=None, interp_mode="bilinear", is_rt=False):
        # Apply minimal smoothing only if sigma > 0
        if (smooth_sigma_y > 0) or (smooth_sigma_x > 0):
            power2d = gaussian_filter(power2d, sigma=(smooth_sigma_y, smooth_sigma_x))

        db2d = _db_from_power(power2d)
        vmin, vmax = _robust_limits(db2d, vmin_prc=vmin_prc, vmax_prc=vmax_percentile)

        fig, ax = plt.subplots(figsize=(fig_w, fig_h), facecolor="white")
        im = ax.imshow(
            db2d, aspect="auto", origin="lower",
            extent=extent, cmap="jet", vmin=vmin, vmax=vmax,
            interpolation=interp_mode,
        )
        ax.set_xlabel(xlabel, fontsize=LABEL_FONT, fontweight="bold")
        ax.set_ylabel(ylabel, fontsize=LABEL_FONT, fontweight="bold")
        _apply_axes_style(ax)
        
        # For RT plots, set ylim to match extent to avoid white space
        # For VT plots, use provided ylim if available
        if is_rt:
            # Use the extent range for ylim to match the actual data
            ax.set_ylim(extent[2], extent[3])
        elif ylim is not None:
            ax.set_ylim(ylim[0], ylim[1])

        divider = make_axes_locatable(ax)
        cax = divider.append_axes("right", size="3.6%", pad=0.08)
        cbar = fig.colorbar(im, cax=cax)
        cbar.set_label("dB", fontsize=CBAR_FONT, fontweight="bold")
        cbar.ax.tick_params(labelsize=TICK_FONT, width=1.0)
        for lab in cbar.ax.get_yticklabels():
            lab.set_fontweight("bold")

        fig.subplots_adjust(left=0.11, right=0.90, bottom=0.20, top=0.97)
        _save_png_pdf(fig, out_folder / outname)

    # RT - with bilinear interpolation and RT-specific vmin
    # Calculate actual range extent from r_axis based on r_gate
    r_idx_gate = range_gate_indices(r_axis, r_gate[0], r_gate[1])
    if len(r_idx_gate) > 0:
        r_min_actual = float(r_axis[r_idx_gate[0]])
        r_max_actual = float(r_axis[r_idx_gate[-1]])
    else:
        r_min_actual = r_gate[0]
        r_max_actual = r_gate[1]
    
    _heatmap(
        fig_w=14.8, fig_h=6.0,  # BIG FIGURE SIZE
        power2d=rt.T,
        extent=[t[0], t[-1], r_min_actual, r_max_actual],  # Use actual data range
        xlabel="Time (s)",
        ylabel="Range (m)",
        outname="RT_Range_Time",
        ylim=None,  # Don't set ylim, let it use extent
        vmin_prc=rt_vmin_percentile,
        interp_mode=rt_interpolation,
        is_rt=True,  # Mark as RT plot
    )

    # VT - with no interpolation and VT-specific vmin for crisp Doppler
    _heatmap(
        fig_w=14.8, fig_h=6.0,  # BIG FIGURE SIZE
        power2d=vt,
        extent=[t[0], t[-1], v_axis[0], v_axis[-1]],
        xlabel="Time (s)",
        ylabel="Relative radial velocity (m/s)",
        outname="VT_Velocity_Time",
        ylim=v_plot_lim,
        vmin_prc=vt_vmin_percentile,
        interp_mode=vt_interpolation,
        is_rt=False,
    )

    # Zoom RT/VT
    if zoom_time_range is not None:
        zs, ze = zoom_time_range
        i0, i1 = _time_slice_indices(t, zs, ze)

        rt_z = rt[i0:i1, :]
        vt_z = vt[:, i0:i1]
        t_z = t[i0:i1]
        tag = f"_ZOOM_{zs:.2f}_{ze:.2f}"

        _heatmap(
            fig_w=14.8, fig_h=6.0,  # BIG FIGURE SIZE
            power2d=rt_z.T,
            extent=[t_z[0], t_z[-1], r_min_actual, r_max_actual],  # Use actual data range
            xlabel="Time (s)",
            ylabel="Range (m)",
            outname=f"RT_Range_Time{tag}",
            ylim=None,  # Don't set ylim, let it use extent
            vmin_prc=rt_vmin_percentile,
            interp_mode=rt_interpolation,
            is_rt=True,  # Mark as RT plot
        )

        _heatmap(
            fig_w=14.8, fig_h=6.0,  # BIG FIGURE SIZE
            power2d=vt_z,
            extent=[t_z[0], t_z[-1], v_axis[0], v_axis[-1]],
            xlabel="Time (s)",
            ylabel="Relative radial velocity (m/s)",
            outname=f"VT_Velocity_Time{tag}",
            ylim=v_plot_lim,
            vmin_prc=vt_vmin_percentile,
            interp_mode=vt_interpolation,
            is_rt=False,
        )

    # Toe + peaks + segments (NO black signed curve) - ENHANCED
    fig, ax = plt.subplots(figsize=(14.8, 6.0), facecolor="white")  # BIG FIGURE SIZE
    ax.plot(t, toe, linewidth=2.2, label="Toe Envelope")
    ax.axhline(min_step_height_mps, linestyle="--", linewidth=1.6, alpha=0.85,
               label=f"Min step height = {min_step_height_mps:.2f} m/s")

    if steps_all is not None and len(steps_all):
        ax.scatter(steps_all * frame_dt, toe[steps_all], s=40, color="gray", alpha=0.45,
                   label=f"All peaks (n={int(len(steps_all))})")
    if steps_used is not None and len(steps_used):
        ax.scatter(steps_used * frame_dt, toe[steps_used], s=55, color="red",
                   label=f"Steps used (n={int(len(steps_used))})", zorder=5)

    for (a, b) in walk_segments:
        ax.axvspan(a * frame_dt, b * frame_dt, color="green", alpha=0.12)

    ax.set_title("Toe Envelope + Peaks + Segments", fontsize=TITLE_FONT, fontweight="bold")
    ax.set_xlabel("Time (s)", fontsize=LABEL_FONT, fontweight="bold")
    ax.set_ylabel("Relative radial velocity (m/s)", fontsize=LABEL_FONT, fontweight="bold")
    _apply_axes_style(ax)
    ax.grid(True, alpha=0.25)
    ax.legend(loc="upper right", frameon=False)
    fig.subplots_adjust(left=0.11, right=0.98, bottom=0.20, top=0.92)
    _save_png_pdf(fig, out_folder / "ToeEnvelope_Peaks_Segments")

    # Summary table - ENHANCED
    fig, ax = plt.subplots(figsize=(14.8, 5.4), facecolor="white")  # BIG FIGURE SIZE
    ax.axis("off")
    table = ax.table(cellText=report_rows, loc="center", cellLoc="left", colWidths=[0.42, 0.52])
    table.auto_set_font_size(False)
    table.set_fontsize(14)  # Increased from 11
    table.scale(1, 1.65)
    fig.subplots_adjust(left=0.03, right=0.97, top=0.95, bottom=0.05)
    _save_png_pdf(fig, out_folder / "Summary_Table")

# ============================================================
# MAIN RUN (SHOE) - OPTIMIZED FOR DOPPLER
# ============================================================
def run_shoe_mounted(
    recording_folder: str,
    frame_dt=None,
    r_gate=(0.10, 1.20),
    show=True,
    gt_steps=None,
    min_gap_s=0.5,

    use_segments=True,
    segments_mode="hysteresis",
    segment_pad_s=0.25,
    step_mode="hybrid",

    min_step_height_mps=0.20,
    height_prc=10,

    # OPTIMIZED plot clarity knobs for Doppler signatures
    rt_vmin_percentile=35.0,  # Lowered from 60 for better RT contrast
    vt_vmin_percentile=8.0,   # Lowered to reveal Doppler detail
    vmax_percentile=99.7,      # Keep high to preserve peak intensity
    smooth_sigma_y=0.3,        # Reduced from 0.8 for minimal blur
    smooth_sigma_x=0.3,        # Reduced from 0.8 for minimal blur
    rt_interpolation="bilinear",  # Smooth for RT
    vt_interpolation="none",      # Crisp for VT Doppler
    v_plot_lim=(-3.8, 3.8),

    save_separate_plots=True,
    zoom_time_range=None,
):
    """Run the shoe-mounted gait pipeline with optimized parameters for Doppler signature visualization.
    
    Key optimizations:
    - Lower vmin percentiles (35.0 for RT, 8.0 for VT) to reveal more detail
    - Minimal smoothing (0.3, 0.3) to preserve micro-Doppler features
    - No interpolation for VT to keep Doppler crisp
    - Bilinear interpolation for RT for smoother appearance
    - BIG BOLD LABELS matching fixed-radar pipeline
    - FIXED: RT plot shows only data range, no white space at top
    - FIXED: Removed notch filter to eliminate black line in VT
    """
    adc, cfg_json, _ = load_recording_folder(recording_folder, expected=(128, 3, 64))
    cfg = derive_cfg_params(cfg_json)

    if frame_dt is None:
        frame_dt = float(cfg["frame_T"])

    rd, rt = compute_rd_rt(adc, cfg, nfft_r=256, nfft_d=cfg["num_chirps"])
    r_axis = make_range_axis(cfg, 256)
    v_axis = make_velocity_axis(cfg, cfg["num_chirps"])
    r_idx = range_gate_indices(r_axis, r_gate[0], r_gate[1])

    vt = vt_from_rd(rd, r_idx, mode="sum")
    toe, _ = toe_envelope(vt, v_axis)
    rc_m = range_centroid(rt, r_axis, r_idx)

    walk_segments, thr_on, thr_off = find_walking_segments(
        toe, frame_dt,
        segments_mode=segments_mode,
        walk_k=0.15, min_walk_s=0.8, min_gap_s=min_gap_s
    )

    peaks_all, height_thr_used, prom_used = detect_steps_from_toe(
        toe, frame_dt,
        prom_k=0.02, prom_floor=0.010,
        height_prc=height_prc,
        min_step_height_mps=min_step_height_mps,
    )

    walking_mask = build_walking_mask(len(toe), walk_segments, frame_dt, pad_s=segment_pad_s) \
        if (use_segments and walk_segments) else np.ones(len(toe), dtype=bool)

    peaks_walk = peaks_all[walking_mask[peaks_all]] if (use_segments and peaks_all.size) else peaks_all.copy()

    if step_mode == "walking":
        steps_for_stats = peaks_walk if use_segments else peaks_all
        steps_for_plot_all = np.array([], dtype=int)
        steps_for_plot_used = steps_for_stats
    elif step_mode == "all":
        steps_for_stats = peaks_all
        steps_for_plot_all = peaks_all
        steps_for_plot_used = peaks_all
    else:
        steps_for_stats = peaks_walk if use_segments else peaks_all
        steps_for_plot_all = peaks_all
        steps_for_plot_used = steps_for_stats

    step_rows = compute_step_table(steps_for_stats, rc_m, v_axis, vt, frame_dt)

    total_steps_all = int(peaks_all.size)
    total_steps_walking = int(peaks_walk.size)
    total_steps_used = int(steps_for_stats.size)
    total_duration = float(len(toe) * frame_dt)

    if use_segments and walk_segments and (step_mode != "all"):
        walking_duration = float(sum((b - a) * frame_dt for (a, b) in walk_segments))
    else:
        walking_duration = float((steps_for_stats[-1] - steps_for_stats[0]) * frame_dt) if steps_for_stats.size >= 2 else 0.0

    cadence_spm = (total_steps_used / walking_duration) * 60.0 if walking_duration > 0 else 0.0

    if use_segments and walk_segments and (step_mode != "all"):
        step_times = step_intervals_within_segments(steps_for_stats, walk_segments, frame_dt)
        stride_times = stride_intervals_within_segments(steps_for_stats, walk_segments, frame_dt)
    else:
        s = np.sort(np.asarray(steps_for_stats, dtype=int))
        step_times = (np.diff(s) * frame_dt) if s.size >= 2 else np.array([], dtype=float)
        stride_times = ((s[2:] - s[:-2]) * frame_dt) if s.size >= 3 else np.array([], dtype=float)

    mean_step_time, step_time_cv = mean_and_cv(step_times)
    mean_stride_time, stride_time_cv = mean_and_cv(stride_times)

    v_app_vals = np.array([float(r[3]) for r in step_rows], dtype=float) if step_rows else np.array([])
    v_sep_vals = np.array([float(r[4]) for r in step_rows], dtype=float) if step_rows else np.array([])
    d_align_vals = np.array([float(r[5]) for r in step_rows], dtype=float) if step_rows else np.array([])

    peak_vapp_mean = float(np.mean(v_app_vals)) if v_app_vals.size else 0.0
    peak_vsep_mean = float(np.mean(v_sep_vals)) if v_sep_vals.size else 0.0
    d_align_mean = float(np.mean(d_align_vals)) if d_align_vals.size else 0.0
    clearance_var = float(np.std(d_align_vals)) if d_align_vals.size else 0.0
    sym_idx = symmetry_index_from_alt_steps(v_sep_vals) if v_sep_vals.size else 0.0

    if use_segments and walk_segments and (step_mode != "all"):
        fog_count = fog_count_within_segments(steps_for_stats, walk_segments, frame_dt, max_step_gap_s=1.5)
    else:
        fog_count = int(np.sum(step_times > 1.5)) if step_times.size else 0

    report = {
        "step_mode": str(step_mode),
        "total_steps_all": total_steps_all,
        "total_steps_walking": total_steps_walking,
        "total_steps_used_for_stats": total_steps_used,

        "cadence_spm": f"{cadence_spm:.2f}",
        "mean_step_time_s": f"{mean_step_time:.3f}",
        "step_time_cv_pct": f"{step_time_cv:.2f}",
        "mean_stride_time_s": f"{mean_stride_time:.3f}",
        "stride_time_cv_pct": f"{stride_time_cv:.2f}",

        "peak_vapp_mean_mps": f"{peak_vapp_mean:.3f}",
        "peak_vsep_mean_mps": f"{peak_vsep_mean:.3f}",
        "symmetry_index": f"{sym_idx:.3f}",
        "d_align_mean_cm": f"{d_align_mean:.2f}",
        "clearance_variability_cm": f"{clearance_var:.2f}",

        "fog_episode_count": int(fog_count),

        "num_walking_segments": int(len(walk_segments)),
        "total_duration_s": f"{total_duration:.2f}",
        "walking_duration_s": f"{walking_duration:.2f}",

        "use_segments": bool(use_segments),
        "segments_mode": str(segments_mode),
        "segment_pad_s": f"{segment_pad_s:.2f}",

        "walk_thr_on": f"{thr_on:.3f}" if thr_on is not None else "",
        "walk_thr_off": f"{thr_off:.3f}" if thr_off is not None else "",

        "min_step_height_mps": f"{min_step_height_mps:.2f}",
        "step_height_thr_used": f"{height_thr_used:.3f}",
        "step_height_prc": int(height_prc),
        "step_prom_used": f"{prom_used:.3f}",
        
        # Add optimized parameters to report
        "rt_vmin_percentile": float(rt_vmin_percentile),
        "vt_vmin_percentile": float(vt_vmin_percentile),
        "vmax_percentile": float(vmax_percentile),
        "smooth_sigma": f"({smooth_sigma_y:.1f}, {smooth_sigma_x:.1f})",
        "rt_interpolation": str(rt_interpolation),
        "vt_interpolation": str(vt_interpolation),
    }

    if gt_steps is not None and gt_steps > 0:
        err = total_steps_used - int(gt_steps)
        report["gt_steps"] = int(gt_steps)
        report["step_count_error"] = int(err)
        report["step_count_error_pct"] = f"{(100.0 * err / gt_steps):.2f}"

    rec_path = Path(recording_folder)
    save_csv(rec_path / "Gait_Analysis_Results_SHOE.csv", report, step_rows)
    save_report_card_png(rec_path, report, step_rows, filename="Gait_Analysis_Report_Card_SHOE.png")

    report_rows = [
        ["step_mode", str(step_mode)],
        ["Total peaks (ALL)", f"{total_steps_all}"],
        ["Peaks in segments", f"{total_steps_walking}"],
        ["Steps used for stats", f"{total_steps_used}"],
        ["Cadence", f"{cadence_spm:.2f} spm"],
        ["Mean step time", f"{mean_step_time:.3f} s"],
        ["Step time CV", f"{step_time_cv:.1f} %"],
        ["Mean stride time", f"{mean_stride_time:.3f} s"],
        ["Stride time CV", f"{stride_time_cv:.1f} %"],
        ["Swing velocity (v_sep mean)", f"{peak_vsep_mean:.3f} m/s"],
        ["FOG gaps", f"{fog_count}"],
        ["# Segments", f"{len(walk_segments)}"],
    ]

    if save_separate_plots:
        save_separate_plots_shoe(
            out_folder=rec_path,
            rt=rt,
            vt=vt,
            toe=toe,
            r_axis=r_axis,
            v_axis=v_axis,
            frame_dt=frame_dt,
            walk_segments=walk_segments,
            steps_all=steps_for_plot_all,
            steps_used=steps_for_plot_used,
            min_step_height_mps=min_step_height_mps,
            report_rows=report_rows,
            r_gate=r_gate,
            v_plot_lim=v_plot_lim,
            zoom_time_range=zoom_time_range,
            rt_vmin_percentile=rt_vmin_percentile,
            vt_vmin_percentile=vt_vmin_percentile,
            vmax_percentile=vmax_percentile,
            smooth_sigma_y=smooth_sigma_y,
            smooth_sigma_x=smooth_sigma_x,
            rt_interpolation=rt_interpolation,
            vt_interpolation=vt_interpolation,
        )

    if show:
        for fn, fs in [
            ("RT_Range_Time.png", (14.8, 6.0)),  # Updated to match figure sizes
            ("VT_Velocity_Time.png", (14.8, 6.0)),  # Updated to match figure sizes
            ("ToeEnvelope_Peaks_Segments.png", (14.8, 6.0)),  # Updated to match figure sizes
            ("Summary_Table.png", (14.8, 5.4)),  # Updated to match figure sizes
        ]:
            p = rec_path / fn
            if p.exists():
                img = plt.imread(str(p))
                fig, ax = plt.subplots(figsize=fs)
                ax.imshow(img)
                ax.axis("off")
                fig.tight_layout(pad=0)
                plt.show()

        print("FINAL REPORT:", report)

    return report

# ============================================================
# CLI
# ============================================================
def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--recording_folder", required=True)
    ap.add_argument("--frame_dt", type=float, default=None)
    ap.add_argument("--rmin", type=float, default=0.10)
    ap.add_argument("--rmax", type=float, default=1.20)
    ap.add_argument("--min_gap_s", type=float, default=0.5)

    ap.add_argument("--step_mode", type=str, default="hybrid", choices=["hybrid", "all", "walking"])
    ap.add_argument("--use_segments", action="store_true")
    ap.add_argument("--no_segments", action="store_true")
    ap.add_argument("--segments_mode", type=str, default="hysteresis", choices=["hysteresis", "basic", "none"])
    ap.add_argument("--segment_pad_s", type=float, default=0.25)

    ap.add_argument("--min_step_height_mps", type=float, default=0.20)
    ap.add_argument("--height_prc", type=int, default=10)

    ap.add_argument("--gt_steps", type=int, default=None)
    ap.add_argument("--no_save_plots", action="store_true")
    ap.add_argument("--no_show", action="store_true")

    ap.add_argument("--zoom_start", type=float, default=None)
    ap.add_argument("--zoom_end", type=float, default=None)

    # OPTIMIZED plot clarity knobs for Doppler signatures
    ap.add_argument("--rt_vmin_prc", type=float, default=35.0, help="RT vmin percentile (lowered for better contrast)")
    ap.add_argument("--vt_vmin_prc", type=float, default=8.0, help="VT vmin percentile (lowered to reveal Doppler detail)")
    ap.add_argument("--vmax_prc", type=float, default=99.7, help="vmax percentile (keep high to preserve peaks)")
    ap.add_argument("--smooth_sigma_y", type=float, default=0.3, help="Smoothing sigma along y-axis (reduced for minimal blur)")
    ap.add_argument("--smooth_sigma_x", type=float, default=0.3, help="Smoothing sigma along x-axis (reduced for minimal blur)")
    ap.add_argument("--rt_interpolation", type=str, default="bilinear", choices=["nearest", "bilinear", "bicubic", "lanczos", "none"], help="Interpolation for RT plot")
    ap.add_argument("--vt_interpolation", type=str, default="none", choices=["nearest", "bilinear", "bicubic", "lanczos", "none"], help="Interpolation for VT plot (none for crisp Doppler)")
    ap.add_argument("--vplot_min", type=float, default=-3.8)
    ap.add_argument("--vplot_max", type=float, default=3.8)

    ap.set_defaults(use_segments=True)
    return ap.parse_args()

if __name__ == "__main__":
    args = parse_args()
    use_segments = bool(args.use_segments) and (not bool(args.no_segments))

    zoom = None
    if args.zoom_start is not None and args.zoom_end is not None and args.zoom_end > args.zoom_start:
        zoom = (args.zoom_start, args.zoom_end)

    run_shoe_mounted(
        recording_folder=args.recording_folder,
        frame_dt=args.frame_dt,
        r_gate=(args.rmin, args.rmax),
        show=(not args.no_show),
        gt_steps=args.gt_steps,
        min_gap_s=args.min_gap_s,
        use_segments=use_segments,
        segments_mode=args.segments_mode,
        segment_pad_s=args.segment_pad_s,
        step_mode=args.step_mode,
        min_step_height_mps=args.min_step_height_mps,
        height_prc=args.height_prc,
        save_separate_plots=(not args.no_save_plots),
        zoom_time_range=zoom,

        rt_vmin_percentile=args.rt_vmin_prc,
        vt_vmin_percentile=args.vt_vmin_prc,
        vmax_percentile=args.vmax_prc,
        smooth_sigma_y=args.smooth_sigma_y,
        smooth_sigma_x=args.smooth_sigma_x,
        rt_interpolation=args.rt_interpolation,
        vt_interpolation=args.vt_interpolation,
        v_plot_lim=(args.vplot_min, args.vplot_max),
    )