import json
import numpy as np
from pathlib import Path
from scipy.io import savemat

def convert(folder_str: str):
    folder = Path(folder_str)
    cfg = json.loads((folder / "config.json").read_text())
    s = cfg["device_config"]["fmcw_single_shape"]
    C = int(s["num_chirps_per_frame"])
    S = int(s["num_samples_per_chirp"])
    R = len(s["rx_antennas"])

    x = np.load(folder / "radar.npy", allow_pickle=False)
    if x.ndim >= 1 and x.shape[-1] == 2:
        x = x[..., 0].astype(np.float32) + 1j * x[..., 1].astype(np.float32)

    shp = list(x.shape)
    # robust mapping even if C==S
    iR = [i for i,d in enumerate(shp) if d == R][0]
    cand = [i for i in range(len(shp)) if i != iR]
    # pick samples as last matching S if possible
    s_axes = [i for i in cand if shp[i] == S]
    c_axes = [i for i in cand if shp[i] == C]
    if (len(s_axes)==0) or (len(c_axes)==0):
        raise ValueError(f"Can't find C={C} and S={S} in shape {shp}")
    iS = (len(shp)-1) if (len(shp)-1 in s_axes) else s_axes[-1]
    iC = [i for i in c_axes if i != iS][0] if len(c_axes) > 1 else c_axes[0]
    iF = [i for i in range(len(shp)) if i not in (iC,iR,iS)][0]

    x = np.transpose(x, (iF,iC,iR,iS)).astype(np.complex64)
    out = folder / "radar_recording.mat"
    savemat(out, {"adc": x, "config": cfg}, do_compression=True)
    print("Saved:", out, "shape:", x.shape)

if __name__ == "__main__":
    convert(r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\two_persons20260219-134957\RadarIfxAvian_00")
    convert(r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\two persons empty\RadarIfxAvian_00")
