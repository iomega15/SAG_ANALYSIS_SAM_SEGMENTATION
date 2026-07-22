function T = classifyLumenFormation(T)
%CLASSIFYLUMENFORMATION  Map per-image pipeline decisions to canonical status.
%
% REBUILT 2026-07-18 (fix batch 4). The previous version re-classified all
% images post-hoc with an adaptive Otsu threshold on SAM_ImfillScore plus a
% TextureRatio<=0.15 rule. On the first complete 840-image run that layer
% relabeled 329 genuinely-found lumens as 'failed' and produced exactly ONE
% occluded image out of 840 (the raw pipeline found 219) — erasing the
% entire occluded band from the classified heatmap. Those thresholds
% predate every gate the per-image pipeline now applies (target-anchored
% selection, intensity-contrast validation, geometry priors), so the
% pipeline's own per-image decision is strictly better informed.
%
% This version is therefore a PASSTHROUGH of the per-image results:
%   SAM_LumenValid & polarity 'bright' -> LumenClass 'bright',     LumenStatus 'open'
%   SAM_LumenValid & polarity 'dark'   -> LumenClass 'dark',       LumenStatus 'occluded'
%   otherwise                          -> LumenClass 'not_formed', LumenStatus 'failed'
%
% Map-level physics corrections (membrane-touchdown inference, the
% no-open-left-of-the-occluded-band rule) are applied downstream in
% plotOcclusionHeatmap, where the (W, ML) grid context exists.

% --- Diagnostic columns (kept for continuity/debugging) ---
T.PolarityScore = (T.SAM_ScoreInv - T.SAM_ScoreGray) ./ ...
                  (T.SAM_ScoreInv + T.SAM_ScoreGray + 1e-6);
T.AreaRatio     = T.SAM_LumenAreaPx ./ (T.SAM_AnchorAreaPx + 1);

if ~ismember('LumenClass', T.Properties.VariableNames)
    T.LumenClass = repmat({'no_data'}, height(T), 1);
end
if ~ismember('LumenStatus', T.Properties.VariableNames)
    T.LumenStatus = repmat({'no_data'}, height(T), 1);
end

for i = 1:height(T)
    if T.SAM_LumenValid(i) && strcmp(T.SAM_Polarity{i}, 'bright')
        T.LumenClass{i}  = 'bright';
        T.LumenStatus{i} = 'open';
    elseif T.SAM_LumenValid(i) && strcmp(T.SAM_Polarity{i}, 'dark')
        T.LumenClass{i}  = 'dark';
        T.LumenStatus{i} = 'occluded';
    else
        T.LumenClass{i}  = 'not_formed';
        T.LumenStatus{i} = 'failed';
    end
end

% --- Print summary ---
fprintf('\nClassification results (passthrough of per-image pipeline):\n');
fprintf('  %-15s  %-15s  %s\n', 'LumenClass', 'LumenStatus', 'Count');
fprintf('  %-15s  %-15s  %s\n', '-----------', '-----------', '-----');

classLabels  = {'bright', 'dark', 'not_formed', 'no_data'};
statusLabels = {'open',   'occluded', 'failed',  'no_data'};

for j = 1:numel(classLabels)
    n = sum(strcmp(T.LumenClass, classLabels{j}));
    if n > 0
        fprintf('  %-15s  %-15s  %d (%.1f%%)\n', ...
            classLabels{j}, statusLabels{j}, n, 100*n/height(T));
    end
end
fprintf('  Total: %d\n', height(T));

end
