# Sag / printability pipeline — developer handoff

Last updated 2026-07-22. Read alongside `ENVIRONMENT_SETUP.md` (Python + SAM install).
This file is the map of *what runs what* and the current state of the sag work.

## What this pipeline does

Takes cross-section micrographs of 3D-printed microfluidic channels (FunToDo NanoClear,
Asiga DLP) named `H<h>_W<width>_ML<roof>_R<rep>_<date>.jpg`, segments the lumen with SAM,
classifies each channel's state, measures membrane roof-sag, and renders the summary
figures over the Width × Roof-thickness design space.

## Entry points

| Script | Use | Cost |
|---|---|---|
| **`IMAGE_ANALYSIS5.m`** | Full pipeline: SAM segment → classify → sag → CSV + figures. The one to run for real. | ~2–5 h (990 imgs; SAM cached) |
| **`REMEASURE_SAG.m`** | Fast sag-only iteration. Re-runs ONLY `measureMembraneSag` from cached lumen masks in the per-image backups, then re-renders sag figures + rewrites CSV. No SAM/OCR. Use while tuning the sag algorithm. | ~2 min |
| `REPLOT_HEATMAPS.m` | Re-render heatmaps from `T_backup.mat` without re-measuring. | seconds |

`REMEASURE_SAG.m` must stay behaviourally in sync with the sag block of `IMAGE_ANALYSIS5.m`
(same `measureMembraneSag` call + same plotter calls). It is a wrapper for iteration only;
the pipeline of record is `IMAGE_ANALYSIS5.m`.

## Data / caching layout (per data folder, e.g. `Cross_Section_RVS2/`)

- `SAM_MASK_CACHE/*_samraw.mat` — raw SAM output. Always on; makes SAM re-runs free.
- `*_ocr.mat` — OCR scale-bar cache.
- `backup/<base>_full_results.mat` — per-image result cache (incl. `BWlumen_rotated`, the
  final lumen mask REMEASURE_SAG reads). `backup/T_backup.mat` — banked table.
- `results/image_scale_results.csv` — the one-row-per-image output table.
- `debug_sag_analysis/*_FINAL.png` — per-image final debug (kept at top level).
  `debug_sag_analysis/detailed_steps/` — all other per-image step figures.

Cache gating in `IMAGE_ANALYSIS5.m`: `resumeRun` (keep backup folder) + `useResultCache`
(skip finished rows) + `PIPELINE_VERSION` stamp (bump to force recompute). **Per-step
debug figures are sacred — never disable them.**

## Sag measurement — current design (DO NOT silently change)

- `measureMembraneSag.m` fits the lumen top edge and reports sag two ways: **corner
  baseline** (deflection below the higher of the two lumen corners) and BB baseline
  (below the bounding-box top). **We publish the corner baseline** — `SagPct_ofMeasuredHeight`.
  The BB baseline over-read edge wiggles on wide flat roofs (e.g. W120 read 19.5% vs the
  correct 0.8%) and is retired for plotting.
- Sag is plotted **only for OPEN (bright) lumens**. Occluded/not-formed cells have no
  meaningful roof-sag.
- **Touchdown = 100%.** `computeChannelStateMatrix.m` (shared with the channel-state map)
  classifies each cell F/X/O/T; cells classed **Touchdown** are plotted as 100% sag (roof
  collapsed to the floor = full-height deflection). This is not fabricated data — it is the
  same validated classification the channel-state map draws.

## Classification (shared)

- `buildStatusFromSAM.m` — per-image status from SAM polarity (bright→open, dark→occluded,
  invalid→failed).
- `computeChannelStateMatrix.m` — grid of F/X/O/T codes via island-ban + monotone 4-stage
  (F→X→O→T) banding. **Single source of truth** for both `plotOcclusionHeatmap.m` (the
  channel-state map) and the sag plotters. Change classification HERE, once.

## Figure outputs (`results/`)

- `channel_state_heatmap_Default_H5.png` — qualitative channel-state map (F/X/O/T).
- `sag_heatmap_Default_H5_corner.png` — **primary** 2D sag heatmap. Gray = no open lumen
  (labeled in-figure). Jet colormap, touchdown = 100.
- `sag_3Dbar_Default_H5_corner.png` (+ `_alt_az{130,45,-135,90}`) — 3D bar/skyline;
  gradient-along-height bars, semi-transparent (FaceAlpha 0.6), jet. Canonical view az −45.
- `sag_3Dsurf_Default_H5_corner.png` (+ `_alt_az*`) — smooth 3D surface, translucent, with
  data-point dots. **INTERPOLATES between grid points** → illustrative only, not the
  quantitative figure.

Colorscheme convention: **jet, 0 (blue) → 100 (dark red)**, `caxis [0 100]`, across all
sag figures for consistency with each other.

## Current state

- `PIPELINE_VERSION = 'IA5_2026-07-22a'`.
- Detection FROZEN at ~99.5% (do not re-tune without cause; see `Cross_Section_RVS2/flagged_failures.md`).
- Corner-baseline sag + touchdown=100% + jet/gradient/translucent figures are **baked into
  `IMAGE_ANALYSIS5.m`** (tail calls `plotSagHeatmap`/`plotSag3D`/`plotSag3Dsurf` with
  `_corner`). A plain `IMAGE_ANALYSIS5.m` run reproduces everything with no wrapper.

## ⚠️ Pending

- **Full `IMAGE_ANALYSIS5.m` run still owed** to bake corner-sag into the per-image
  `backup/*_full_results.mat`. The current figures/CSV are correct (via REMEASURE_SAG), but
  the backups were written by the pre-corner run. Values will not change on the full run —
  only the backups become self-consistent with `PIPELINE_VERSION`.

## Gotchas

- Paths are machine-agnostic: `fullfile(getenv('USERPROFILE'), 'Dropbox', ...)`. Runs on
  rvoronov / Olympus / altvi unchanged.
- `sam_vit_b_01ec64.pth` (358 MB) is **gitignored** — never commit it; download per
  `ENVIRONMENT_SETUP.md`.
- Only MATLAB/Python code is version-controlled here; data + figures live in the Dropbox
  data folders, not in git.
- Retired code is in `unused_archive/` (e.g. `plotComparativeSag*`, old classification
  stages, `plotWallTilt`). `plotComparativeSag.m` at top level is deprecated — it
  fabricated 100% sag for missing wide groups; do not reuse.
- Crash-resume: each image is banked on completion; a crash loses only the in-flight image.
  Clean any half-written `backup/*_full_results.mat` before relaunching.

## Related

- Manuscript-facing figure/caption handoff:
  `MANUSCRIPTS/micromachines_valve_printing_framework/SAG_FIGURE_HANDOFF.md`.
