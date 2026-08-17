import numpy as np
import scipy.io
from pathlib import Path

# Update this path
recording_folder = r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\20260203_224805_walk_any_speed"

npy_path = Path(recording_folder) / "radar.npy"
mat_path = Path(recording_folder) / "radar.mat"

if not npy_path.exists():
    print(f"Error: {npy_path} not found!")
else:
    print(f"Converting: {npy_path}")
    data = np.load(str(npy_path), allow_pickle=False)
    scipy.io.savemat(str(mat_path), {"radar_data": data})
    print(f"✓ Saved: {mat_path}")