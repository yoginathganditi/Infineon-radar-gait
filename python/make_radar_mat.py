import json
import numpy as np
from pathlib import Path
from scipy.io import savemat

rec_folder = Path(r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\two_persons20260219-144928\RadarIfxAvian_00")

cfg = json.loads((rec_folder / "config.json").read_text())
s = cfg["device_config"]["fmcw_single_shape"]
S = int(s["num_samples_per_chirp"])
C = int(s["num_chirps_per_frame"])
R = len(s["rx_antennas"])

x = np.load(rec_folder / "radar.npy", allow_pickle=False)

# IQ -> complex
if x.ndim >= 1 and x.shape[-1] == 2:
    x = x[..., 0].astype(np.float32) + 1j * x[..., 1].astype(np.float32)

shp = list(x.shape)
print("radar.npy shape:", shp)
print("expected C,R,S:", (C, R, S))

# ---- Robust axis finder (works even if C == S) ----
# Find RX axis by matching R (usually unique = 3)
candR = [i for i,d in enumerate(shp) if d == R]
if len(candR) != 1:
    raise ValueError(f"Cannot uniquely find RX axis (R={R}) in shape {shp}. candidates={candR}")
iR = candR[0]

# Candidates for C and S
candC = [i for i,d in enumerate(shp) if d == C and i != iR]
candS = [i for i,d in enumerate(shp) if d == S and i != iR]

# If C and S are the same number (e.g., 64 and 64), cand lists overlap.
# We must pick distinct axes: choose C as the axis that is NOT last if possible.
if C == S:
    # remove duplicates
    overlap = sorted(set(candC).intersection(set(candS)))
    if len(overlap) < 2:
        raise ValueError(f"Ambiguous axes: C==S=={C} but not enough matching dims in {shp}.")
    # Heuristic: samples axis is often the last axis, chirps is often not last
    if (len(overlap) == 2) and (max(overlap) == len(shp)-1):
        iS = len(shp)-1
        iC = min(overlap)
    else:
        # fallback: take last as S, first as C
        iS = overlap[-1]
        iC = overlap[0]
else:
    if len(candC) < 1:
        raise ValueError(f"Cannot find chirps axis (C={C}) in shape {shp}")
    if len(candS) < 1:
        raise ValueError(f"Cannot find samples axis (S={S}) in shape {shp}")

    # Heuristic: samples axis tends to be the last dimension
    iS = candS[-1] if (len(shp)-1 in candS) else candS[0]
    # Chirps is then the remaining C candidate not used
    iC = [i for i in candC if i != iS][0] if (len(candC) > 1) else candC[0]

# Frame axis = remaining
all_axes = set(range(len(shp)))
used = {iC, iR, iS}
rest = sorted(list(all_axes - used))
if len(rest) != 1:
    raise ValueError(f"Cannot infer frame axis uniquely. shape={shp}, used={used}, rest={rest}")
iF = rest[0]

print("Axis mapping (F,C,R,S) indices:", (iF, iC, iR, iS))
print("Dims  (F,C,R,S) sizes:  ", (shp[iF], shp[iC], shp[iR], shp[iS]))

x = np.transpose(x, (iF, iC, iR, iS)).astype(np.complex64)

out_path = rec_folder / "radar_recording.mat"
savemat(out_path, {"adc": x, "config": cfg}, do_compression=True)

print("Saved:", out_path)
print("adc shape (F,C,R,S):", x.shape)
