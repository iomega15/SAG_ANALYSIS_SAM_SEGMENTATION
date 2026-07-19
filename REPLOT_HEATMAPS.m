%% REPLOT_HEATMAPS — regenerate the channel-state heatmaps from a finished run
% Reads the final results CSV written by IMAGE_ANALYSIS5.m and re-runs ONLY
% the map-level classification rules + heatmap rendering (touchdown
% inference, monotone-stage banding) — no SAM, no OCR, no sag measurement.
% Use this to iterate on the heatmap rules without a multi-hour pipeline
% rerun. Overwrites channel_state_heatmap_* / heatmap_*.pdf in results\.

clc; clear all; close all;

dropboxRoot = fullfile(getenv('USERPROFILE'), 'Dropbox');
rootDir = fullfile(dropboxRoot, 'MANUSCRIPTS', 'micromachines_valve_printing_framework', ...
    'Figures', 'NanoClear', 'Sorted_ConstH5', 'Cross_Section_RVS2');
resultsFolder = fullfile(rootDir, 'results');
csvFile = fullfile(resultsFolder, 'image_scale_results.csv');

if ~exist(csvFile, 'file')
    error('Final results CSV not found: %s (run IMAGE_ANALYSIS5.m first)', csvFile);
end

T = readtable(csvFile, 'TextType', 'char');
fprintf('Loaded %d rows from %s\n', height(T), csvFile);

plotOcclusionHeatmap(T, resultsFolder, 'sam');
plotOcclusionHeatmap(T, resultsFolder, 'classified');

fprintf('Done — heatmaps rewritten in %s\n', resultsFolder);
