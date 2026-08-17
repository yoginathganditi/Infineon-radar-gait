import numpy as np
import scipy.io
from pathlib import Path

BASE_DIR = Path(r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C")

def convert_one(npy_path: Path):
    """Convert one radar.npy to radar.mat"""
    folder = npy_path.parent
    mat_file = folder / "radar.mat"
    
    if mat_file.exists():
        print(f"⊗ Already exists: {folder}")
        return False
    
    try:
        print(f"Converting: {folder}")
        data = np.load(npy_path, allow_pickle=False)
        scipy.io.savemat(str(mat_file), {"radar_data": data})
        print(f"  ✓ Saved: {mat_file}")
        return True
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return False

def main():
    print("=== Converting all radar.npy files to radar.mat ===\n")
    
    # Find all radar.npy files
    npys = list(BASE_DIR.rglob("radar.npy"))
    print(f"Found {len(npys)} radar.npy files\n")
    
    converted = 0
    for p in npys:
        if convert_one(p):
            converted += 1
    
    print(f"\n✓ Conversion complete! Converted {converted}/{len(npys)} files")

if __name__ == "__main__":
    main()