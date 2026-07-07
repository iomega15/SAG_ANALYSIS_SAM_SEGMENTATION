function T = classifyLumenFormation(T)
%CLASSIFYLUMENFORMATION  Classify lumens as open/occluded/failed.
%
% Writes results into T.LumenStatus using canonical vocabulary:
%   'open'      — bright lumen (channel is open)
%   'occluded'  — dark lumen (channel formed but is blocked/dark)
%   'failed'    — not formed (no real lumen detected)
%   'no_data'   — insufficient SAM data to classify
%
% Two-stage classification:
%   Stage 1: formed vs failed using ImfillScore + TextureRatio
%   Stage 2: open vs occluded using PolarityScore
%
% Also writes diagnostic columns: PolarityScore, AreaRatio, LumenClass
%   LumenClass preserves the raw classifier labels (bright/dark/not_formed)
%   for debugging; LumenStatus is the canonical column used by all plots.

% --- Compute derived features ---
T.PolarityScore = (T.SAM_ScoreInv - T.SAM_ScoreGray) ./ ...
                  (T.SAM_ScoreInv + T.SAM_ScoreGray + 1e-6);
T.AreaRatio     = T.SAM_LumenAreaPx ./ (T.SAM_AnchorAreaPx + 1);

% --- Identify rows with complete data ---
has_data = T.SAM_LumenValid & ...
           ~isnan(T.SAM_TextureRatio) & ...
           ~isnan(T.SAM_ImfillScore) & ...
           ~isnan(T.PolarityScore) & ...
           ~isnan(T.AreaRatio);

n_valid = sum(has_data);
fprintf('Classifying %d lumens into open/occluded/failed\n', n_valid);

% --- Initialize output columns ---
if ~ismember('LumenClass', T.Properties.VariableNames)
    T.LumenClass = repmat({'no_data'}, height(T), 1);
end
if ~ismember('LumenStatus', T.Properties.VariableNames)
    T.LumenStatus = repmat({'no_data'}, height(T), 1);
end

if n_valid < 3
    warning('Too few valid lumens (%d) for classification — skipping', n_valid);
    return;
end

valid_idx = find(has_data);

% =====================================================================
%  Stage 1: Formed vs Not Formed
% =====================================================================
imfill_vals  = T.SAM_ImfillScore(has_data);
texture_vals = T.SAM_TextureRatio(has_data);

% Adaptive imfill threshold via Otsu
imfill_normed = (imfill_vals - min(imfill_vals)) / ...
                (max(imfill_vals) - min(imfill_vals) + 1e-6);
imfill_thresh_normed = graythresh(imfill_normed);
imfill_thresh = imfill_thresh_normed * (max(imfill_vals) - min(imfill_vals)) + min(imfill_vals);

texture_thresh = 0.15;

fprintf('  Imfill threshold (Otsu): %.1f\n', imfill_thresh);
fprintf('  Texture threshold: %.2f\n', texture_thresh);

is_formed = (T.SAM_ImfillScore(has_data) >= imfill_thresh) & ...
            (T.SAM_TextureRatio(has_data) <= texture_thresh);

% =====================================================================
%  Stage 2: Bright vs Dark (among formed only)
% =====================================================================
polarity_vals = T.PolarityScore(has_data);

% Raw classifier label → canonical status mapping:
%   bright      → open
%   dark        → occluded
%   not_formed  → failed

for j = 1:n_valid
    row = valid_idx(j);
    if is_formed(j)
        if polarity_vals(j) > 0
            T.LumenClass{row}  = 'bright';
            T.LumenStatus{row} = 'open';
        else
            T.LumenClass{row}  = 'dark';
            T.LumenStatus{row} = 'occluded';
        end
    else
        T.LumenClass{row}  = 'not_formed';
        T.LumenStatus{row} = 'failed';
    end
end

% --- Print summary ---
fprintf('\nClassification results:\n');
fprintf('  %-15s  %-15s  %s\n', 'LumenClass', 'LumenStatus', 'Count');
fprintf('  %-15s  %-15s  %s\n', '-----------', '-----------', '-----');

% Map for display
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