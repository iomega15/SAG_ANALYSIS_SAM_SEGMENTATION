%% REMEASURE_SAG — re-run ONLY measureMembraneSag from cached lumen masks
% Iterate on the sag algorithm WITHOUT a full pipeline run. Each per-image
% backup (backup\<base>_full_results.mat) stores BWlumen_rotated (the final
% lumen mask), so we can re-run measureMembraneSag on all 990 masks in ~a
% couple minutes — no SAM, no OCR, no re-segmentation. Updates the sag
% columns in the table, re-renders the sag plots, and rewrites the CSV.
% Use this to review/tune the sag algorithm; do a full IMAGE_ANALYSIS5 run
% (bump PIPELINE_VERSION) only once the sag algorithm is finalized.

clc; clear; close all;

dropboxRoot   = fullfile(getenv('USERPROFILE'), 'Dropbox');
rootDir       = fullfile(dropboxRoot, 'MANUSCRIPTS', 'micromachines_valve_printing_framework', ...
                    'Figures', 'NanoClear', 'Sorted_ConstH5', 'Cross_Section_RVS2');
resultsFolder = fullfile(rootDir, 'results');
backupDir     = fullfile(rootDir, 'backup');
layerHeight_mm = 0.05;
pixelWidth_mm  = 0.032;

load(fullfile(rootDir, 'T_backup.mat'), 'T');
fprintf('Loaded T (%d rows). Re-measuring sag from cached masks...\n', height(T));

nOK = 0; nNoBackup = 0; nNoMask = 0; nTrust = 0;
for i = 1:height(T)
    [~, base, ~] = fileparts(T.File{i});
    bf = fullfile(backupDir, [base '_full_results.mat']);
    if ~exist(bf, 'file'), nNoBackup = nNoBackup + 1; continue; end
    S = load(bf, 'BWlumen_rotated');
    if ~isfield(S, 'BWlumen_rotated') || ~any(S.BWlumen_rotated(:))
        nNoMask = nNoMask + 1; continue;
    end

    sm = measureMembraneSag(S.BWlumen_rotated, T.mmPerPx(i), false, ...
        T.H_layers(i), T.Width_px(i), layerHeight_mm, pixelWidth_mm);
    if ~sm.valid, continue; end

    % Sag values (NaN when the measurement is untrustworthy — see the gate
    % in measureMembraneSag). Overwrites the old, ungated values.
    T.SagDepth_px(i)                   = sm.sagDepth_px;
    T.SagDepth_mm(i)                   = sm.sagDepth_mm;
    T.SagPct_ofMeasuredHeight(i)       = sm.sagPct_ofMeasuredHeight;
    T.SagPct_ofTheoreticalHeight(i)    = sm.sagPct_ofTheoreticalHeight;
    T.SagPct_ofWidthSpan(i)            = sm.sagPct_ofWidthSpan;
    T.ParabolaR2(i)                    = sm.parabolaR2;
    T.SagArea_px2(i)                   = sm.sagArea_px2;
    T.SagDepthBB_px(i)                 = sm.sagDepthBB_px;
    T.SagDepthBB_mm(i)                 = sm.sagDepthBB_mm;
    T.SagAreaBB_px2(i)                 = sm.sagAreaBB_px2;
    T.SagBB_Pct_ofMeasuredHeight(i)    = sm.sagBB_Pct_ofMeasuredHeight;
    T.SagBB_Pct_ofTheoreticalHeight(i) = sm.sagBB_Pct_ofTheoreticalHeight;
    T.SagBB_Pct_ofWidthSpan(i)         = sm.sagBB_Pct_ofWidthSpan;
    T.IsVertexBetween(i)               = sm.isVertexBetween;
    T.IsVertexLowerLeft(i)             = sm.isVertexLowerLeft;
    T.IsVertexLowerRight(i)            = sm.isVertexLowerRight;

    nOK = nOK + 1;
    if isfield(sm, 'sagTrustworthy') && sm.sagTrustworthy, nTrust = nTrust + 1; end
end
fprintf('Re-measured %d masks (%d trustworthy sag, rest NaN). no-backup=%d, empty-mask=%d\n', ...
    nOK, nTrust, nNoBackup, nNoMask);

%% Re-render sag heatmaps (2D, honest) + rewrite CSV
plotSagHeatmap(T, resultsFolder, 'SagBB_Pct_ofMeasuredHeight',  'Sag (% of measured height, BB baseline)',     '_BB');
plotSagHeatmap(T, resultsFolder, 'SagPct_ofMeasuredHeight',     'Sag (% of measured height, corner baseline)', '_corner');
writetable(T, fullfile(resultsFolder, 'image_scale_results.csv'));
fprintf('Done — sag plots + CSV updated in %s\n', resultsFolder);
