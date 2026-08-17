# run_all_trials.py
from pathlib import Path

from fixed_radar_gait_final import run_fixed
from shoe_mounted_gait_final import run_shoe_mounted

# =========================================================
# BASE DIR / EMPTY ROOM
# =========================================================
BASE_DIR = Path(r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C")
EMPTY_ROOM_PATH = r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\empty_now20260212-162322\RadarIfxAvian_00"

# =========================================================
# DATASET PATHS
# NOTE: patterns can be a string (single trial) OR a list (multiple trials)
# =========================================================
FIXED_DATA = {
    "Mani": {
        "regular": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\regular_prof20260212-162507\RadarIfxAvian_00",
        "slow":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Slow",
        "fast":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\fast_prof20260212-162613\RadarIfxAvian_00",
        "festination": [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Festination\trial 1",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Festination\trial 2",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Festination\trial 3",
        ],
        "fog":  [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Fog\trial 1",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Fog\trial 2",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Fog\trial 3",
        ],
    },
    "Yogi": {
        "regular": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Regular",
        "slow":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Slow",
        "fast":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fast",
        "festination": [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Festination\trial 1",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Festination\trial 2",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Festination\trial 3",
        ],
        "fog": [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fog\trial 1",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fog\trial 2",
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fog\trial 3",
        ],
    },
    "Srinath": {
        "regular": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Regular",
        "slow":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Slow",
        "fast":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Fast",
        "festination": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Festination",
        "fog":        r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Fog",
    },
    "Manohar": {
        "regular": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Regular",
        "slow":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Slow",
        "fast":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Fast",
        "festination": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Festination",
        "fog":        r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Fog",
    },
}

SHOE_DATA = {
    "Mani": {
        "regular": r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Mani P1\Regular",
        "slow":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\mani_shoe__hor_slow120251230-024905\RadarIfxAvian_00",
        "fast":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\mani_shoe__hor_fast120251230-024500\RadarIfxAvian_00",
        "festination": [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Mani P1\Festination\trial 1",
           
        ],
        "fog": [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Mani P1\Fog\trial 1",
           
        ],
    },
    "Yogi": {
        "regular": r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\yogi_shoe__hor_regular120251230-023601\RadarIfxAvian_00",
        "slow":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\yogi_shoe__hor_slow120251230-023851\RadarIfxAvian_00",
        "fast":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\yogi_shoe__hor_fast120251230-024031\RadarIfxAvian_00",
        "festination": [
            r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Yogi P2\Festination\trial 1",
           
        ],
        "fog": [
            r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\yogi_shoe__hor_fog_trail220251230-022110\RadarIfxAvian_00",
        
        ],
    },
    "Srinath": {
        "regular": r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\srinath_shoe_final_regular20260101-012751\RadarIfxAvian_00",
        "slow":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\srinath_shoe_final_slow20260101-013000\RadarIfxAvian_00",
        "fast":    r"C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Srinath P3\Fast",
        "festination": r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\srinath_shoe_final_festination20260101-013314\RadarIfxAvian_00",
        "fog":        r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\srinath_shoe_final_fog20260101-013451\RadarIfxAvian_00",
    },
    "Manohar": {
        "regular": r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_regular20260101-013928\RadarIfxAvian_00",
        "slow":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_slow20260101-014107\RadarIfxAvian_00",
        "fast":    r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_fast20260101-014241\RadarIfxAvian_00",
        "festination": r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_festination20260101-014409\RadarIfxAvian_00",
        "fog":        r"C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_fog20260101-014536\RadarIfxAvian_00",
    },
}

# =========================================================
# CONTROL PANEL
# =========================================================
SUBJECT = "Mani"                 # Mani / Yogi / Srinath / Manohar
PATTERN = "fast"          # slow / regular / fast / festination / fog
SENSOR  = "fixed"                # fixed / shoe

USE_SEGMENTS  = True
SEGMENTS_MODE = "hysteresis"     # hysteresis / basic / none
STEP_MODE     = "all"            # hybrid / all / walking

MIN_STEP_HEIGHT_MPS = 0.20
DYNAMIC_GATE_HALFWIDTH_M = 0.8   # fixed-only

SAVE_SEPARATE_PLOTS = True
SHOW_PLOTS = True

# For multi-trial patterns (lists), you can:
RUN_ALL_TRIALS_IF_LIST = True    # True = run every trial in the list
TRIAL_INDEX_IF_LIST    = 0       # used only if RUN_ALL_TRIALS_IF_LIST = False

# Zoom time range for festination plots (optional)
# Set to None to disable zoom, or provide (start_sec, end_sec) tuple
# Example: ZOOM_TIME_RANGE = (5.0, 15.0)  # zooms into 5-15 second window
ZOOM_TIME_RANGE = None  # Set to (start, end) tuple for festination zoom plots

def _ensure_list(x):
    if isinstance(x, (list, tuple)):
        return list(x)
    return [x]

def run_one(subject, pattern, sensor):
    print("\n" + "="*80)
    print(f"RUNNING: subject={subject} | pattern={pattern} | sensor={sensor}")
    print(f"use_segments={USE_SEGMENTS} | segments_mode={SEGMENTS_MODE} | step_mode={STEP_MODE}")
    print(f"min_step_height_mps={MIN_STEP_HEIGHT_MPS:.2f}")
    if ZOOM_TIME_RANGE:
        print(f"zoom_time_range={ZOOM_TIME_RANGE}")
    print("="*80)

    if sensor == "fixed":
        entry = FIXED_DATA[subject][pattern]
        paths = _ensure_list(entry)

        if (len(paths) > 1) and RUN_ALL_TRIALS_IF_LIST:
            reps = []
            for i, p in enumerate(paths, start=1):
                print(f"\n--- FIXED TRIAL {i}/{len(paths)} ---")
                reps.append(run_fixed(
                    empty_folder=EMPTY_ROOM_PATH,
                    walk_folder=p,
                    frame_dt=0.078,
                    r_gate=(1.5, 7.0),
                    show=SHOW_PLOTS,
                    gt_steps=None,
                    min_gap_s=0.5,
                    use_segments=USE_SEGMENTS,
                    segments_mode=SEGMENTS_MODE,
                    segment_pad_s=0.30,
                    dynamic_gate_halfwidth_m=DYNAMIC_GATE_HALFWIDTH_M,
                    step_min_toe_mps=MIN_STEP_HEIGHT_MPS,
                    step_mode=STEP_MODE,
                    save_separate_plots=SAVE_SEPARATE_PLOTS,
                    zoom_time_range=ZOOM_TIME_RANGE,
                ))
            return reps

        p = paths[min(TRIAL_INDEX_IF_LIST, len(paths)-1)]
        return run_fixed(
            empty_folder=EMPTY_ROOM_PATH,
            walk_folder=p,
            frame_dt=0.078,
            r_gate=(1.5, 7.0),
            show=SHOW_PLOTS,
            gt_steps=None,
            min_gap_s=0.5,
            use_segments=USE_SEGMENTS,
            segments_mode=SEGMENTS_MODE,
            segment_pad_s=0.30,
            dynamic_gate_halfwidth_m=DYNAMIC_GATE_HALFWIDTH_M,
            step_min_toe_mps=MIN_STEP_HEIGHT_MPS,
            step_mode=STEP_MODE,
            save_separate_plots=SAVE_SEPARATE_PLOTS,
            zoom_time_range=ZOOM_TIME_RANGE,
        )

    if sensor == "shoe":
        entry = SHOE_DATA[subject][pattern]
        paths = _ensure_list(entry)

        if (len(paths) > 1) and RUN_ALL_TRIALS_IF_LIST:
            reps = []
            for i, p in enumerate(paths, start=1):
                print(f"\n--- SHOE TRIAL {i}/{len(paths)} ---")
                reps.append(run_shoe_mounted(
                    recording_folder=p,
                    frame_dt=None,
                    r_gate=(0.10, 1.20),
                    show=SHOW_PLOTS,
                    gt_steps=None,
                    min_gap_s=0.5,
                    use_segments=USE_SEGMENTS,
                    segments_mode=SEGMENTS_MODE,
                    segment_pad_s=0.25,
                    step_mode=STEP_MODE,
                    min_step_height_mps=MIN_STEP_HEIGHT_MPS,
                    height_prc=10,
                    save_separate_plots=SAVE_SEPARATE_PLOTS,
                    zoom_time_range=ZOOM_TIME_RANGE,
                ))
            return reps

        p = paths[min(TRIAL_INDEX_IF_LIST, len(paths)-1)]
        return run_shoe_mounted(
            recording_folder=p,
            frame_dt=None,
            r_gate=(0.10, 1.20),
            show=SHOW_PLOTS,
            gt_steps=None,
            min_gap_s=0.5,
            use_segments=USE_SEGMENTS,
            segments_mode=SEGMENTS_MODE,
            segment_pad_s=0.25,
            step_mode=STEP_MODE,
            min_step_height_mps=MIN_STEP_HEIGHT_MPS,
            height_prc=10,
            save_separate_plots=SAVE_SEPARATE_PLOTS,
            zoom_time_range=ZOOM_TIME_RANGE,
        )

    raise ValueError("SENSOR must be 'fixed' or 'shoe'")

def run_all():
    results = []
    subjects = ["Mani", "Yogi", "Srinath", "Manohar"]
    patterns = ["slow", "regular", "fast", "festination", "fog"]
    sensors  = ["fixed", "shoe"]

    for subject in subjects:
        for pattern in patterns:
            for sensor in sensors:
                rep = run_one(subject, pattern, sensor)
                results.append((subject, pattern, sensor, rep))
    return results

if __name__ == "__main__":
    run_one(SUBJECT, PATTERN, SENSOR)
    # run_all()

