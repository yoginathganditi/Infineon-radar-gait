# ============================================================
# FIXED-RADAR GAIT PIPELINE (FINAL SUBMISSION VERSION)
# Updates (per professor comments):
# 1) Ensures every exported PNG is at least 1000 x 1000 pixels (auto-upscale if needed)
# 2) Increases X/Y axis label + tick font size for BOTH RT and VT figures
# 3) Keeps sharp Doppler signatures (nearest interpolation; no extra smoothing in display)
# 4) Removes whitespace around images for cleaner output
# 5) Larger images with bold, dark black, bigger fonts
# ============================================================

__all__ = ["run_fixed"]

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

# --- Submission requirement ---
MIN_PX = 1000  # each saved figure must be >= 1000 x 1000 pixels

# --- Plot style ---
plt.rcParams.update({
    "font.family": "Times New Roman",
    "font.size": 16,
    "axes.labelsize": 20,
    "axes.titlesize": 18,
    "xtick.labelsize": 18,
    "ytick.labelsize": 18,
    "legend.fontsize": 15,
    "pdf.fonttype": 42,
    "ps.fonttype": 42,
})

# ============================================================
# SAVE HELPERS (AUTO-TRIM PNG WHITESPACE + ENSURE >=1000x1000)
# ============================================================
def _trim_png_whitespace(png_path: Path, pad_px: int = 2):
    """
    Remove whitespace around image by detecting content bounding box.
    pad_px reduced to 2 for minimal whitespace.
    """
    try:
        from PIL import Image, ImageChops
        # Suppress PIL warnings for large images
        Image.MAX_IMAGE_PIXELS = None
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
    # Reduced padding from 6 to 2 for minimal whitespace
    x0 = max(0, x0 - pad_px)
    y0 = max(0, y0 - pad_px)
    x1 = min(im.width,  x1 + pad_px)
    y1 = min(im.height, y1 + pad_px)

    im.crop((x0, y0, x1, y1)).save(png_path)

def _ensure_min_png_pixels(png_path: Path, min_px: int = 1000):
    """
    If trimming/cropping or low DPI caused an image dimension to fall below min_px,
    upscale with high-quality resampling so BOTH dimensions >= min_px.
    """
    try:
        from PIL import Image
        # Suppress PIL warnings for large images
        Image.MAX_IMAGE_PIXELS = None
    except Exception:
        return

    png_path = Path(png_path)
    if not png_path.exists():
        return

    im = Image.open(png_path)
    w, h = im.size
    if w >= min_px and h >= min_px:
        return

    scale = max(min_px / max(w, 1), min_px / max(h, 1))
    new_w = int(math.ceil(w * scale))
    new_h = int(math.ceil(h * scale))

    try:
        resample = Image.Resampling.LANCZOS
    except Exception:
        resample = Image.LANCZOS

    im2 = im.resize((new_w, new_h), resample=resample)
    im2.save(png_path)

def _save_png_pdf(fig, base_path_no_ext: Path, dpi_png: int = 900, min_px: int = 1000):
    base_path_no_ext = Path(base_path_no_ext)

    try:
        fig.tight_layout(pad=0.05)  # Reduced padding from 0.20 to 0.05
    except Exception:
        pass

    png_path = base_path_no_ext.with_suffix(".png")
    pdf_path = base_path_no_ext.with_suffix(".pdf")

    # Reduced pad_inches for minimal whitespace
    fig.savefig(str(png_path), dpi=dpi_png, bbox_inches="tight", pad_inches=0.01, facecolor="white")
    fig.savefig(str(pdf_path), bbox_inches="tight", pad_inches=0.01, facecolor="white")
    plt.close(fig)

    _trim_png_whitespace(png_path, pad_px=2)  # Reduced padding
    _ensure_min_png_pixels(png_path, min_px=min_px)

def _db_from_power(p):
    return 10.0 * np.log10(np.maximum(p, 1e-12))

def _robust_jet_limits(db2d, vmin_prc=35.0, vmax_prc=99.5, min_range_db=25.0):
    lo = float(np.percentile(db2d, vmin_prc))
    hi = float(np.percentile(db2d, vmax_prc))
    if (hi - lo) < float(min_range_db):
        hi = lo + float(min_range_db)
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
# IO HELPERS
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

def reorder_to_FCRS(x: np.ndarray, expected=(128, 3, 280)) -> np.ndarray:
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

def load_recording_folder(folder: str, expected=(128, 3, 280)):
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
def compute_rd_rt(adc, cfg, nfft_r=1024, nfft_d=256):
    """
    adc: (F,C,R,S)
    rd:  (F,R,V) power
    rt:  (F,R) power
    """
    F, Cc, Rr, Ss = adc.shape
    win_r = np.hanning(Ss).astype(np.float32)
    win_d = np.blackman(Cc).astype(np.float32)

    Xr = np.fft.fft(adc * win_r[None, None, None, :], n=nfft_r, axis=-1)[..., :nfft_r // 2]
    # remove static clutter across chirps
    Xr = Xr - Xr.mean(axis=1, keepdims=True)

    Xr = Xr * win_d[None, :, None, None]
    Xd = np.fft.fftshift(np.fft.fft(Xr, n=nfft_d, axis=1), axes=1)

    p = np.sum(np.abs(Xd) ** 2, axis=2)     # sum over Rx -> (F,V,R)
    rd = np.transpose(p, (0, 2, 1))         # (F,R,V)
    rt = rd.sum(axis=2)                     # (F,R)
    return rd, rt

def vt_from_rd_static(rd, r_idx, mode="sum"):
    if mode == "sum":
        vt = rd[:, r_idx, :].sum(axis=1)  # (F,V)
    else:
        vt = rd[:, r_idx, :].max(axis=1)
    return vt.T  # (V,F)

def vt_from_rd_dynamic(rd, r_axis, torso_r, halfwidth_m=0.8, mode="sum"):
    F, R, V = rd.shape
    vt_FV = np.zeros((F, V), dtype=np.float32)
    for f in range(F):
        r0 = float(torso_r[f])
        idx = np.where((r_axis >= (r0 - halfwidth_m)) & (r_axis <= (r0 + halfwidth_m)))[0]
        if idx.size == 0:
            continue
        if mode == "sum":
            vt_FV[f] = rd[f, idx, :].sum(axis=0)
        else:
            vt_FV[f] = rd[f, idx, :].max(axis=0)
    return vt_FV.T

# ============================================================
# ENVELOPES + SEGMENTS
# ============================================================
def mad(x):
    x = np.asarray(x)
    m = np.median(x)
    return np.median(np.abs(x - m)) + 1e-6

def robust_mask_db(power_2d, k_mad=6.0):
    db = 10 * np.log10(power_2d + 1e-12)
    med = np.median(db)
    mm = np.median(np.abs(db - med)) + 1e-6
    return db > (med + k_mad * mm)

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

def _segments_from_bool(walk_bool, frame_dt, min_walk_s=1.0, min_gap_s=0.5):
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

def find_walking_segments(toe, frame_dt, segments_mode="hysteresis", walk_k=0.15, min_walk_s=1.0, min_gap_s=0.5):
    toe_s = gaussian_filter1d(np.asarray(toe), sigma=1.0)
    base = np.median(toe_s)
    spread = mad(toe_s)

    if segments_mode == "none":
        return [], None, None

    if segments_mode == "basic":
        thr = base + walk_k * spread
        walk = toe_s > thr
        walk = binary_dilation(walk, iterations=10)
        walk = binary_erosion(walk, iterations=1)
        segs = _segments_from_bool(walk, frame_dt, min_walk_s=min_walk_s, min_gap_s=min_gap_s)
        return segs, float(thr), float(thr)

    thr_on = base + walk_k * spread
    thr_off = base + (walk_k * 0.92) * spread

    walk = np.zeros_like(toe_s, dtype=bool)
    state = False
    for i, v in enumerate(toe_s):
        if (not state) and (v >= thr_on):
            state = True
        elif state and (v <= thr_off):
            state = False
        walk[i] = state

    walk = binary_dilation(walk, iterations=8)
    walk = binary_erosion(walk, iterations=1)

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
# TORSO TRACK + STEPS
# ============================================================
def track_torso_range(rt, r_axis, r_idx):
    rt_g = rt[:, r_idx]
    peak = np.argmax(rt_g, axis=1)
    torso_r = r_axis[r_idx][peak]
    return gaussian_filter1d(torso_r, sigma=2.0)

def torso_velocity(torso_r, frame_dt):
    v = np.gradient(torso_r, frame_dt)
    return gaussian_filter1d(v, sigma=2.0)

def detect_steps_from_toe(
    toe_env,
    frame_dt,
    prom_k=0.008,
    prom_floor=0.004,
    height_prc=4,
    step_min_toe_mps=0.20,
    min_step_distance_s=0.16,
):
    toe = np.asarray(toe_env, dtype=np.float32)
    min_dist = max(1, int(min_step_distance_s / frame_dt))

    prom = max(prom_k * mad(toe), prom_floor)
    height_thr = float(np.percentile(toe, height_prc))
    height_thr = max(height_thr, float(step_min_toe_mps))

    peaks, _ = sig.find_peaks(toe, height=height_thr, prominence=prom, distance=min_dist)
    return np.array(peaks, dtype=int), float(height_thr), float(prom)

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

def stride_lengths_within_segments(torso_r, peaks, segments):
    if len(peaks) < 3 or not segments:
        return np.array([], dtype=float)

    all_sl = []
    for p in split_peaks_by_segments(peaks, segments):
        if p.size >= 3:
            sl = np.abs(torso_r[p[2:]] - torso_r[p[:-2]])
            all_sl.append(sl)

    return np.concatenate(all_sl) if all_sl else np.array([], dtype=float)

# ============================================================
# CSV + REPORT CARD
# ============================================================
def extract_per_step_data(step_frames, toe, torso_r, torso_v, frame_dt):
    step_data = []
    sf = np.sort(np.asarray(step_frames, dtype=int))
    for idx, frame in enumerate(sf):
        step_id = idx + 1
        time_s = frame * frame_dt
        toe_velocity = float(toe[frame])
        torso_velocity_val = float(torso_v[frame])

        if idx == 0:
            step_time_s = 0.0
            step_length_cm = 0.0
        else:
            step_time_s = (frame - sf[idx - 1]) * frame_dt
            step_length_m = abs(torso_r[frame] - torso_r[sf[idx - 1]])
            step_length_cm = step_length_m * 100.0

        if idx + 2 < len(sf):
            stride_time_s = (sf[idx + 2] - frame) * frame_dt
            stride_length_cm = abs(torso_r[sf[idx + 2]] - torso_r[frame]) * 100.0
        else:
            stride_time_s = 0.0
            stride_length_cm = 0.0

        step_data.append({
            "step_id": step_id,
            "time_s": float(time_s),
            "toe_velocity_m_s": float(toe_velocity),
            "torso_velocity_m_s": float(torso_velocity_val),
            "step_time_s": float(step_time_s),
            "step_length_cm": float(step_length_cm),
            "stride_time_s": float(stride_time_s),
            "stride_length_cm": float(stride_length_cm),
        })
    return step_data

def save_gait_data_to_csv(output_path, report, step_data):
    output_path = Path(output_path)
    with open(output_path, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["=== GLOBAL GAIT SUMMARY (FIXED) ==="])
        writer.writerow([])
        writer.writerow(["Parameter", "Value"])
        for k, v in report.items():
            writer.writerow([k, v])
        writer.writerow([])
        writer.writerow(["=== DETAILED PER-STEP DATA (STEPS USED FOR STATS) ==="])
        writer.writerow([])
        writer.writerow(["Step_ID", "Time_s", "Toe_Velocity_m_s", "Torso_Velocity_m_s",
                         "Step_Time_s", "Step_Length_cm", "Stride_Time_s", "Stride_Length_cm"])
        for step in step_data:
            writer.writerow([
                step["step_id"],
                f"{step['time_s']:.4f}",
                f"{step['toe_velocity_m_s']:.4f}",
                f"{step['torso_velocity_m_s']:.4f}",
                f"{step['step_time_s']:.4f}",
                f"{step['step_length_cm']:.2f}",
                f"{step['stride_time_s']:.4f}" if step["stride_time_s"] > 0 else "",
                f"{step['stride_length_cm']:.2f}" if step["stride_length_cm"] > 0 else "",
            ])
    print(f"\n✓ CSV saved: {output_path.absolute()}")

def _pick_num_columns(n_steps: int) -> int:
    if n_steps <= 40:
        return 1
    if n_steps <= 80:
        return 2
    if n_steps <= 120:
        return 3
    return 4

def save_report_card_png(output_folder, report, step_data):
    output_folder = Path(output_folder)
    output_path = output_folder / "Gait_Analysis_Report_Card_FIXED.png"

    n = len(step_data)
    ncols = _pick_num_columns(n)
    rows_per_col = int(math.ceil(n / ncols)) if n > 0 else 1

    fig_w = max(14, 7.2 * ncols)
    fig_h = 14
    dpi = 350

    fig = plt.figure(figsize=(fig_w, fig_h), dpi=dpi, facecolor="white")
    gs = fig.add_gridspec(2, 1, height_ratios=[0.34, 0.66], hspace=0.05)

    ax_sum = fig.add_subplot(gs[0])
    ax_sum.axis("off")

    fig.suptitle("GAIT ANALYSIS DATA REPORT CARD (FIXED)", fontsize=22, fontweight="bold",
                 y=0.985, fontfamily="Times New Roman")

    ax_sum.text(0.02, 0.92, "GLOBAL SUMMARY", fontsize=16, fontweight="bold",
                fontfamily="Times New Roman", transform=ax_sum.transAxes)

    pretty = [(k, report.get(k, "")) for k in report.keys()]
    y = 0.84
    dy = 0.075
    for k, v in pretty[:12]:
        ax_sum.text(0.05, y, f"{k}:", fontsize=13, fontweight="bold",
                    fontfamily="Times New Roman", transform=ax_sum.transAxes)
        ax_sum.text(0.52, y, f"{v}", fontsize=13,
                    fontfamily="Times New Roman", transform=ax_sum.transAxes)
        y -= dy

    sub = gs[1].subgridspec(1, ncols, wspace=0.06)
    headers = ["Step", "Time(s)", "ToeVel", "TorsoVel", "StepT", "StepLen(cm)", "StrideT", "StrideLen(cm)"]

    fig.text(0.02, 0.62, f"DETAILED PER-STEP DATA (STEPS USED FOR STATS = {n})",
             fontsize=16, fontweight="bold", fontfamily="Times New Roman")

    header_bg = "#2C3E50"
    even_bg = "#EBF5FB"
    border = "#144160"

    for col in range(ncols):
        ax = fig.add_subplot(sub[0, col])
        ax.axis("off")

        start = col * rows_per_col
        end = min((col + 1) * rows_per_col, n)
        chunk = step_data[start:end]

        rows = []
        for s in chunk:
            rows.append([
                s["step_id"],
                f'{s["time_s"]:.3f}',
                f'{s["toe_velocity_m_s"]:.3f}',
                f'{s["torso_velocity_m_s"]:.3f}',
                f'{s["step_time_s"]:.3f}',
                f'{s["step_length_cm"]:.2f}',
                f'{s["stride_time_s"]:.3f}' if s["stride_time_s"] > 0 else "-",
                f'{s["stride_length_cm"]:.2f}' if s["stride_length_cm"] > 0 else "-",
            ])

        table = ax.table(
            cellText=rows,
            colLabels=headers,
            cellLoc="center",
            colLoc="center",
            bbox=[0.00, 0.02, 1.00, 0.96],
        )
        table.auto_set_font_size(False)
        table.set_fontsize(10 if n > 60 else 11)
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

    fig.savefig(output_path, dpi=dpi, bbox_inches="tight", pad_inches=0.01, facecolor="white")
    plt.close(fig)
    _ensure_min_png_pixels(output_path, min_px=MIN_PX)
    print(f"✓ Report card saved: {output_path.absolute()}")

# ============================================================
# SEPARATE PLOTS — RT / VT (WITH BIGGER AXIS FONTS)
# ============================================================
def save_separate_plots_fixed(
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
    min_step_toe_mps: float,
    report_rows,
    zoom_time_range=None,
    vmin_prc=35.0,
    vmax_prc=99.5,
    min_range_db=25.0,
    dpi_png=900,
):
    from mpl_toolkits.axes_grid1 import make_axes_locatable

    out_folder = Path(out_folder)
    out_folder.mkdir(parents=True, exist_ok=True)

    t = np.arange(rt.shape[0]) * frame_dt

    # --- MUCH LARGER fonts specifically for RT & VT axes (bold, dark black) ---
    AX_LBL_FS = 32  # Increased from 26 to 32
    TICK_FS   = 24  # Increased from 20 to 24
    CBAR_FS   = 28  # Increased from 22 to 28

    def _heatmap(fig_w, fig_h, data2d, extent, xlabel, ylabel, outname):
        db2d = _db_from_power(data2d)
        vmin, vmax = _robust_jet_limits(db2d, vmin_prc=vmin_prc, vmax_prc=vmax_prc, min_range_db=min_range_db)

        fig, ax = plt.subplots(figsize=(fig_w, fig_h), facecolor="white")
        im = ax.imshow(
            db2d, aspect="auto", origin="lower",
            extent=extent, cmap="jet", vmin=vmin, vmax=vmax,
            interpolation="nearest",  # keeps Doppler edges sharp
        )

        # Bold, dark black axis labels
        ax.set_xlabel(xlabel, fontsize=AX_LBL_FS, fontweight="bold", color="black")
        ax.set_ylabel(ylabel, fontsize=AX_LBL_FS, fontweight="bold", color="black")
        
        # Bold, dark black tick labels
        ax.tick_params(axis="both", labelsize=TICK_FS, colors="black", width=2, length=8)
        # Make tick labels bold
        for label in ax.get_xticklabels():
            label.set_fontweight("bold")
            label.set_color("black")
        for label in ax.get_yticklabels():
            label.set_fontweight("bold")
            label.set_color("black")

        divider = make_axes_locatable(ax)
        cax = divider.append_axes("right", size="4.0%", pad=0.08)
        cbar = fig.colorbar(im, cax=cax)
        cbar.set_label("dB", fontsize=CBAR_FS, fontweight="bold", color="black")  # Bold, dark black colorbar label
        cbar.ax.tick_params(labelsize=TICK_FS, colors="black", width=2, length=6)
        # Make colorbar tick labels bold
        for label in cbar.ax.get_yticklabels():
            label.set_fontweight("bold")
            label.set_color("black")

        # Reduced margins for minimal whitespace
        fig.subplots_adjust(left=0.10, right=0.88, bottom=0.12, top=0.98)
        _save_png_pdf(fig, out_folder / outname, dpi_png=dpi_png, min_px=MIN_PX)

    # INCREASED figure sizes: from 12.0x6.5 to 16.0x9.0 for much larger images
    _heatmap(
        fig_w=16.0, fig_h=9.0,  # Increased from 12.0x6.5
        data2d=rt.T,
        extent=[t[0], t[-1], r_axis[0], r_axis[-1]],
        xlabel="Time (s)", ylabel="Range (m)",
        outname="RT_Range_Time",
    )

    _heatmap(
        fig_w=16.0, fig_h=9.0,  # Increased from 12.0x6.5
        data2d=vt,
        extent=[t[0], t[-1], v_axis[0], v_axis[-1]],
        xlabel="Time (s)", ylabel="Estimated radial velocity (m/s)",
        outname="VT_Velocity_Time",
    )

    if zoom_time_range is not None:
        zs, ze = zoom_time_range
        i0, i1 = _time_slice_indices(t, zs, ze)
        rt_z = rt[i0:i1, :]
        vt_z = vt[:, i0:i1]
        t_z = t[i0:i1]
        tag = f"_ZOOM_{zs:.2f}_{ze:.2f}"

        _heatmap(
            fig_w=16.0, fig_h=9.0,  # Increased from 12.0x6.5
            data2d=rt_z.T,
            extent=[t_z[0], t_z[-1], r_axis[0], r_axis[-1]],
            xlabel="Time (s)", ylabel="Range (m)",
            outname=f"RT_Range_Time{tag}",
        )
        _heatmap(
            fig_w=16.0, fig_h=9.0,  # Increased from 12.0x6.5
            data2d=vt_z,
            extent=[t_z[0], t_z[-1], v_axis[0], v_axis[-1]],
            xlabel="Time (s)", ylabel="Estimated radial velocity (m/s)",
            outname=f"VT_Velocity_Time{tag}",
        )

    # Toe plot (larger with bold fonts)
    fig, ax = plt.subplots(figsize=(16.0, 8.0), facecolor="white")  # Increased from 12.0x6.0
    ax.plot(t, toe, linewidth=2.5, label="Toe Envelope", color="black")
    ax.axhline(min_step_toe_mps, linestyle="--", linewidth=1.8, alpha=0.8,
               label=f"Min step toe = {min_step_toe_mps:.2f} m/s", color="red")

    if steps_all is not None and len(steps_all):
        ax.scatter(steps_all * frame_dt, toe[steps_all], s=30, color="gray", alpha=0.45,
                   label=f"All peaks (n={int(len(steps_all))})")
    if steps_used is not None and len(steps_used):
        ax.scatter(steps_used * frame_dt, toe[steps_used], s=50, color="red",
                   label=f"Steps used (n={int(len(steps_used))})", zorder=5)

    for (a, b) in walk_segments:
        ax.axvspan(a*frame_dt, b*frame_dt, color="green", alpha=0.12)

    ax.set_title("Toe Envelope + Peaks + Segments", fontsize=24, fontweight="bold", color="black")
    ax.set_xlabel("Time (s)", fontsize=28, fontweight="bold", color="black")
    ax.set_ylabel("Estimated radial velocity (m/s)", fontsize=28, fontweight="bold", color="black")
    ax.tick_params(axis="both", labelsize=22, colors="black", width=2, length=8)
    # Make tick labels bold
    for label in ax.get_xticklabels():
        label.set_fontweight("bold")
        label.set_color("black")
    for label in ax.get_yticklabels():
        label.set_fontweight("bold")
        label.set_color("black")
    ax.grid(True, alpha=0.25)
    ax.legend(loc="upper right", frameon=False, fontsize=18)
    # Reduced margins for minimal whitespace
    fig.subplots_adjust(left=0.08, right=0.98, bottom=0.12, top=0.92)
    _save_png_pdf(fig, out_folder / "ToeEnvelope_Peaks_Segments", dpi_png=dpi_png, min_px=MIN_PX)

    # Summary table (larger)
    fig, ax = plt.subplots(figsize=(14.0, 9.0), facecolor="white")  # Increased from 12.0x7.0
    ax.axis("off")
    table = ax.table(cellText=report_rows, loc="center", cellLoc="left", colWidths=[0.42, 0.52])
    table.auto_set_font_size(False)
    table.set_fontsize(16)  # Increased from 14
    table.scale(1, 1.85)  # Increased from 1.75
    # Make table text bold and black
    for (i, j), cell in table.get_celld().items():
        cell.get_text().set_fontweight("bold")
        cell.get_text().set_color("black")
    # Reduced margins for minimal whitespace
    fig.subplots_adjust(left=0.02, right=0.98, top=0.98, bottom=0.02)
    _save_png_pdf(fig, out_folder / "Summary_Table", dpi_png=dpi_png, min_px=MIN_PX)

# ============================================================
# MAIN RUN (FIXED)
# ============================================================
def run_fixed(
    empty_folder: str,
    walk_folder: str,
    frame_dt: float = 0.078,
    r_gate=(1.5, 7.0),
    show=True,

    gt_steps=None,
    gt_gaps=None,
    min_gap_s=0.5,
    use_segments=True,
    segments_mode="hysteresis",
    segment_pad_s=0.50,

    dynamic_gate_halfwidth_m=0.0,
    step_min_toe_mps=0.20,
    step_mode="hybrid",

    save_separate_plots=True,
    zoom_time_range=None,

    dpi_png=900,
    nfft_r=1024,
    nfft_d=256,
    vmin_prc=35.0,
    vmax_prc=99.5,
    min_range_db=25.0,

    prom_k=0.008,
    prom_floor=0.004,
    height_prc=4,
    min_step_distance_s=0.16,
):
    bg_adc, _, _ = load_recording_folder(empty_folder, expected=(128, 3, 280))
    wk_adc, wk_cfg_json, _ = load_recording_folder(walk_folder, expected=(128, 3, 280))
    cfg = derive_cfg_params(wk_cfg_json)

    wk_adc = wk_adc - bg_adc.mean(axis=0, keepdims=True)

    rd, rt = compute_rd_rt(wk_adc, cfg, nfft_r=int(nfft_r), nfft_d=int(nfft_d))
    r_axis = make_range_axis(cfg, int(nfft_r))
    v_axis = make_velocity_axis(cfg, int(nfft_d))
    r_idx = range_gate_indices(r_axis, r_gate[0], r_gate[1])

    torso_r = track_torso_range(rt, r_axis, r_idx)
    torso_v = torso_velocity(torso_r, frame_dt)

    if dynamic_gate_halfwidth_m and dynamic_gate_halfwidth_m > 0:
        vt = vt_from_rd_dynamic(rd, r_axis, torso_r, halfwidth_m=float(dynamic_gate_halfwidth_m), mode="sum")
        vt_mode = f"dynamic({dynamic_gate_halfwidth_m:.2f}m)"
    else:
        vt = vt_from_rd_static(rd, r_idx, mode="sum")
        vt_mode = "static"

    toe, _ = toe_envelope(vt, v_axis)

    walk_segments, thr_on, thr_off = find_walking_segments(
        toe, frame_dt,
        segments_mode=segments_mode,
        walk_k=0.15, min_walk_s=1.0, min_gap_s=min_gap_s
    )

    walking_mask = build_walking_mask(len(toe), walk_segments, frame_dt, pad_s=segment_pad_s) \
        if (use_segments and walk_segments) else np.ones(len(toe), dtype=bool)

    peaks_all, height_thr, prom_used = detect_steps_from_toe(
        toe, frame_dt,
        prom_k=prom_k,
        prom_floor=prom_floor,
        height_prc=height_prc,
        step_min_toe_mps=step_min_toe_mps,
        min_step_distance_s=min_step_distance_s,
    )

    peaks_walk = peaks_all[walking_mask[peaks_all]] if (use_segments and peaks_all.size) else peaks_all.copy()

    if step_mode == "all":
        steps_for_stats = peaks_all
        steps_for_plot_all = peaks_all
        steps_for_plot_used = peaks_all
    elif step_mode == "walking":
        steps_for_stats = peaks_walk if use_segments else peaks_all
        steps_for_plot_all = np.array([], dtype=int)
        steps_for_plot_used = steps_for_stats
    else:
        steps_for_stats = peaks_walk if use_segments else peaks_all
        steps_for_plot_all = peaks_all
        steps_for_plot_used = steps_for_stats

    total_steps_all = int(peaks_all.size)
    total_steps_walking = int(peaks_walk.size)
    total_steps_used = int(steps_for_stats.size)
    total_duration = float(len(torso_r) * frame_dt)

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

    seg_for_stride = walk_segments if (use_segments and walk_segments and step_mode != "all") else [(0, len(torso_r))]
    s_len = stride_lengths_within_segments(torso_r, steps_for_stats, seg_for_stride)
    avg_stride_length = float(np.mean(s_len)) if s_len.size else 0.0
    total_distance = float(np.sum(s_len)) if s_len.size else 0.0

    if use_segments and walk_segments and step_mode != "all":
        avg_walking_speed = float(np.median(np.abs(torso_v[walking_mask])))
    else:
        avg_walking_speed = float(np.median(np.abs(torso_v))) if len(torso_v) else 0.0

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

        "avg_stride_length_m": f"{avg_stride_length:.3f}",
        "avg_walking_speed_mps": f"{avg_walking_speed:.3f}",
        "total_distance_m": f"{total_distance:.3f}",

        "total_duration_s": f"{total_duration:.2f}",
        "walking_duration_s": f"{walking_duration:.2f}",
        "num_walking_segments": int(len(walk_segments)),

        "use_segments": bool(use_segments),
        "segments_mode": str(segments_mode),
        "segment_pad_s": f"{segment_pad_s:.2f}",
        "vt_gate_mode": vt_mode,

        "walk_thr_on": f"{thr_on:.3f}" if thr_on is not None else "",
        "walk_thr_off": f"{thr_off:.3f}" if thr_off is not None else "",

        "step_min_toe_mps": f"{float(step_min_toe_mps):.2f}",
        "step_height_thr_used": f"{height_thr:.3f}",
        "step_prom_used": f"{prom_used:.3f}",

        "nfft_r": int(nfft_r),
        "nfft_d": int(nfft_d),
        "vmin_prc": float(vmin_prc),
        "vmax_prc": float(vmax_prc),
        "png_dpi": int(dpi_png),

        "prom_k": float(prom_k),
        "prom_floor": float(prom_floor),
        "height_prc": float(height_prc),
        "min_step_distance_s": float(min_step_distance_s),
    }

    if gt_steps is not None and gt_steps > 0:
        err = total_steps_used - int(gt_steps)
        report["gt_steps"] = int(gt_steps)
        report["step_count_error"] = int(err)
        report["step_count_error_pct"] = f"{(100.0 * err / gt_steps):.2f}"

    if gt_gaps is not None:
        report["gt_gaps"] = int(gt_gaps)
        report["gap_count_error"] = int(len(walk_segments) - int(gt_gaps))

    step_data = extract_per_step_data(steps_for_stats.astype(int).tolist(), toe, torso_r, torso_v, frame_dt)

    walk_folder_path = Path(walk_folder)
    save_gait_data_to_csv(walk_folder_path / "Gait_Analysis_Results_FIXED.csv", report, step_data)
    save_report_card_png(walk_folder_path, report, step_data)

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
        ["Avg walking speed", f"{avg_walking_speed:.3f} m/s"],
        ["Avg stride length", f"{avg_stride_length*100.0:.1f} cm"],
        ["# Segments", f"{len(walk_segments)}"],
        ["VT Gate", vt_mode],
        ["nfft_r / nfft_d", f"{int(nfft_r)} / {int(nfft_d)}"],
        ["PNG dpi", f"{int(dpi_png)}"],
        ["Min pixels", f"{MIN_PX}x{MIN_PX}"],
    ]

    if save_separate_plots:
        save_separate_plots_fixed(
            out_folder=walk_folder_path,
            rt=rt,
            vt=vt,
            toe=toe,
            r_axis=r_axis,
            v_axis=v_axis,
            frame_dt=frame_dt,
            walk_segments=walk_segments,
            steps_all=steps_for_plot_all,
            steps_used=steps_for_plot_used,
            min_step_toe_mps=step_min_toe_mps,
            report_rows=report_rows,
            zoom_time_range=zoom_time_range,
            vmin_prc=vmin_prc,
            vmax_prc=vmax_prc,
            min_range_db=min_range_db,
            dpi_png=dpi_png,
        )

    if show:
        for fn, fs in [
            ("RT_Range_Time.png", (16.0, 9.0)),
            ("VT_Velocity_Time.png", (16.0, 9.0)),
            ("ToeEnvelope_Peaks_Segments.png", (16.0, 8.0)),
            ("Summary_Table.png", (14.0, 9.0)),
        ]:
            p = walk_folder_path / fn
            if p.exists():
                img = plt.imread(str(p))
                fig, ax = plt.subplots(figsize=fs)
                ax.imshow(img)
                ax.axis("off")
                fig.tight_layout(pad=0)
                plt.show()

        print("FINAL REPORT:", report)

    return report

def parse_args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--empty_folder", required=True)
    ap.add_argument("--walk_folder", required=True)

    ap.add_argument("--frame_dt", type=float, default=0.078)
    ap.add_argument("--rmin", type=float, default=1.5)
    ap.add_argument("--rmax", type=float, default=7.0)

    ap.add_argument("--min_gap_s", type=float, default=0.5)
    ap.add_argument("--use_segments", action="store_true")
    ap.add_argument("--segments_mode", type=str, default="hysteresis", choices=["hysteresis", "basic", "none"])
    ap.add_argument("--segment_pad_s", type=float, default=0.50)

    ap.add_argument("--dynamic_gate_halfwidth_m", type=float, default=0.0)
    ap.add_argument("--step_min_toe_mps", type=float, default=0.20)
    ap.add_argument("--step_mode", type=str, default="hybrid", choices=["hybrid", "all", "walking"])

    ap.add_argument("--no_save_plots", action="store_true")
    ap.add_argument("--gt_steps", type=int, default=None)
    ap.add_argument("--gt_gaps", type=int, default=None)
    ap.add_argument("--no_show", action="store_true")

    ap.add_argument("--zoom_start", type=float, default=None)
    ap.add_argument("--zoom_end", type=float, default=None)

    ap.add_argument("--dpi_png", type=int, default=900)
    ap.add_argument("--nfft_r", type=int, default=1024)
    ap.add_argument("--nfft_d", type=int, default=256)
    ap.add_argument("--vmin_prc", type=float, default=35.0)
    ap.add_argument("--vmax_prc", type=float, default=99.5)
    ap.add_argument("--min_range_db", type=float, default=25.0)

    ap.add_argument("--prom_k", type=float, default=0.008)
    ap.add_argument("--prom_floor", type=float, default=0.004)
    ap.add_argument("--height_prc", type=float, default=4)
    ap.add_argument("--min_step_distance_s", type=float, default=0.16)

    return ap.parse_args()

if __name__ == "__main__":
    args = parse_args()
    zoom = None
    if args.zoom_start is not None and args.zoom_end is not None and args.zoom_end > args.zoom_start:
        zoom = (args.zoom_start, args.zoom_end)

    run_fixed(
        empty_folder=args.empty_folder,
        walk_folder=args.walk_folder,
        frame_dt=args.frame_dt,
        r_gate=(args.rmin, args.rmax),
        show=(not args.no_show),
        gt_steps=args.gt_steps,
        gt_gaps=args.gt_gaps,
        min_gap_s=args.min_gap_s,
        use_segments=args.use_segments,
        segments_mode=args.segments_mode,
        segment_pad_s=args.segment_pad_s,
        dynamic_gate_halfwidth_m=args.dynamic_gate_halfwidth_m,
        step_min_toe_mps=args.step_min_toe_mps,
        step_mode=args.step_mode,
        save_separate_plots=(not args.no_save_plots),
        zoom_time_range=zoom,
        dpi_png=args.dpi_png,
        nfft_r=args.nfft_r,
        nfft_d=args.nfft_d,
        vmin_prc=args.vmin_prc,
        vmax_prc=args.vmax_prc,
        min_range_db=args.min_range_db,
        prom_k=args.prom_k,
        prom_floor=args.prom_floor,
        height_prc=args.height_prc,
        min_step_distance_s=args.min_step_distance_s,
    )