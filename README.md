# Sag / printability analysis of 3D-printed microfluidic channels (side views)

MATLAB + Python program that classifies each channel of a 3D-printed
*printability device* as **open**, **occluded**, or **not formed** from a
back-illuminated side view, and measures how far the printed channel roof sags.
It is one of three programs described in the preprint
*Cross-Section and Top-View Image-Analysis Pipelines for Automated
Characterization of 3D-Printed Microfluidic Channels and Valves*
(Nguyen et al., 2026); the companion valve-design framework is
[engrXiv 10.31224/8053](https://doi.org/10.31224/8053).

Related programs:
[VALVE_CLOSURE_ANALYSIS](https://github.com/iomega15/VALVE_CLOSURE_ANALYSIS)
(membrane reach from open/closed pairs; imports this repository) and
[TOP_VIEW_CHANNEL_PINCH](https://github.com/iomega15/TOP_VIEW_CHANNEL_PINCH)
(channel formation along the length, from top views).

## How it works
1. **Segmentation.** The Segment Anything Model (SAM, ViT-B) proposes a channel
   mask from one center-point prompt, plus scene masks from a 6 x 6 prompt grid
   (`sam_segment_all.py`, called from `segmentLumenSAM2.m`).
2. **Validation.** Ten classical tests decide whether the candidate is the
   channel: exclusive masks, speck cleanup, texture scoring, backlight and
   printed-material anchor identification, border/bounds eliminations,
   enclosure scoring by morphological reconstruction, target-anchored
   selection, a size gate, and an intensity-contrast test that assigns
   bright (open) or dark (occluded) polarity.
3. **Classification.** Replicate majority vote, then map rules (touchdown
   inference, island removal, monotone banding) in `computeChannelStateMatrix.m`.
4. **Sag.** Rotation leveling from the layer lines (`autoRotateImage.m`), roof
   profile, parabola vertex, and sag against two baselines (`measureMembraneSag.m`).

Every step writes a diagnostic figure (`saveStep*Debug.m`, `saveFinalSummaryDebug.m`).

## Requirements
* MATLAB R2026a (tested) with the Image Processing Toolbox and the Computer
  Vision Toolbox (OCR of the scale-bar label).
* Python 3.10 with PyTorch 2.5.1 (CPU is enough), torchvision, `segment-anything` 1.0,
  OpenCV, NumPy. Step-by-step setup: [`ENVIRONMENT_SETUP.md`](ENVIRONMENT_SETUP.md).
* The SAM checkpoint `sam_vit_b_01ec64.pth` (358 MB, not in this repository):
  download it from the [segment-anything release](https://github.com/facebookresearch/segment-anything#model-checkpoints)
  into this folder.

## Usage
1. Name the images `H{n}_W{n}_ML{n}_R{n}_{MMDDYY}.jpg` (H = channel height in
   layers, W = channel width in printer pixels, ML = roof thickness in layers,
   R = replicate).
2. Set `rootDir` and the printer constants (`pixelWidth_mm`, `layerHeight_mm`,
   `assumedBarValue_mm`) under `%% USER INPUTS` in `IMAGE_ANALYSIS5.m`.
3. Point MATLAB at the Python environment (`pyenv`, see ENVIRONMENT_SETUP.md), then
   run `IMAGE_ANALYSIS5.m`. SAM output is cached per image, so reruns after a
   code change skip inference.
4. `REMEASURE_SAG.m` and `REPLOT_HEATMAPS.m` recompute sag or redraw the maps
   from the cached tables.

Outputs (in `results/` beside the images): per-image tables (CSV and MAT), the
channel-state map, sag maps and 3D views, and `debug_sag_analysis/` with the
diagnostic figures. [`HANDOFF.md`](HANDOFF.md) documents the design decisions.

## License
MIT, see [`LICENSE`](LICENSE).
