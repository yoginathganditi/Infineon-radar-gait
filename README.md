# Infineon BGT60TR13C — 60 GHz FMCW Radar for Gait Monitoring

**Project:** EEE 500 Master's Project, California State University Sacramento  
**Authors:** Yoginath Ganditi, Mani S. Chilakala  
**Advisor:** Prof. Zahra Najafi  
**Funding:** NSF Grant No. 2243089

## What this project does
Fixed tripod-mounted 60 GHz FMCW radar (Infineon BGT60TR13C) deployed in a 
corridor for contactless gait monitoring. Detects step events and computes 
spatiotemporal gait metrics. Validated against video ground truth across 
5 gait styles: regular, slow, fast, festination, and freezing of gait (FOG).

## Hardware
- Sensor: Infineon BGT60TR13C (61–63 GHz, BW = 2 GHz)
- Range resolution: 7.5 cm | Frame rate: 12.9 fps
- Mounted on tripod at corridor end (~5 m walking segment)
## Repository structure
```
infineon-radar-gait/
├── matlab/          ← MATLAB processing scripts
├── python/          ← Python parser and visualization
├── data/            ← Data location info (raw files on Drive)
└── docs/            ← Report and poster
```
## How to run the MATLAB processing
1. Open MATLAB R2025b
2. Navigate to `matlab/`
3. Run the main processing script

## How to run the Python parser
1. Install Python 3.x
2. `pip install numpy matplotlib scipy`
3. Run: `python python/parser/parser_mmw_demo.py`

## Raw data
Raw `.dat` files are stored at: ## Raw data
Raw `.dat` files are stored on CSUS OneDrive under Dr. Eltayeb's EEE 500 Projects folder.  
Contact yoginathganditi@csus.edu or mohammed.eltayeb@csus.edu to request access.
Contact yoginathganditi@csus.edu for access.

## Published paper
Ganditi et al., "Millimeter-Wave Body-Centric Radar Sensing for Continuous 
Monitoring of Human Gait Dynamics," *Sensors* 2026, 26, 1844.
