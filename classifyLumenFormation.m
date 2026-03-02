function T = classifyLumenFormation(T)
%CLASSIFYLUMENFORMATION  Classify lumens as bright/dark/not_formed.
%
% Two-stage classification:
%   Stage 1: formed vs not_formed using ImfillScore + TextureRatio
%   Stage 2: bright vs dark using PolarityScore

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
fprintf('Classifying %d lumens into bright/dark/not_formed\n', n_valid);

% --- Initialize output ---
if ~ismember('LumenClass', T.Properties.VariableNames)
    T.LumenClass = repmat({'no_data'}, height(T), 1);
end

if n_valid < 3
    warning('Too few valid lumens (%d) for classification — skipping', n_valid);
    return;
end

valid_idx = find(has_data);

% =====================================================================
%  Stage 1: Formed vs Not Formed
% =====================================================================
% Formed lumens have: high imfill AND low texture ratio
% Use Otsu on ImfillScore to find the natural split

imfill_vals  = T.SAM_ImfillScore(has_data);
texture_vals = T.SAM_TextureRatio(has_data);

% Adaptive imfill threshold via Otsu on the imfill scores
imfill_normed = (imfill_vals - min(imfill_vals)) / (max(imfill_vals) - min(imfill_vals) + 1e-6);
imfill_thresh_normed = graythresh(imfill_normed);
imfill_thresh = imfill_thresh_normed * (max(imfill_vals) - min(imfill_vals)) + min(imfill_vals);

% Texture ratio threshold — formed lumens should be below this
texture_thresh = 0.15;  % lumens are voids, texture ratio should be near 0

fprintf('  Imfill threshold (Otsu): %.1f\n', imfill_thresh);
fprintf('  Texture threshold: %.2f\n', texture_thresh);

is_formed = (T.SAM_ImfillScore(has_data) >= imfill_thresh) & ...
            (T.SAM_TextureRatio(has_data) <= texture_thresh);

% =====================================================================
%  Stage 2: Bright vs Dark (among formed only)
% =====================================================================
% PolarityScore > 0 → bright lumen (dark void filled by imfill)
% PolarityScore < 0 → dark lumen (bright void filled by inverse imfill)

polarity_vals = T.PolarityScore(has_data);

for j = 1:n_valid
    row = valid_idx(j);
    if is_formed(j)
        if polarity_vals(j) > 0
            T.LumenClass{row} = 'bright';
        else
            T.LumenClass{row} = 'dark';
        end
    else
        T.LumenClass{row} = 'not_formed';
    end
end

% --- Print summary ---
cats   = categories(categorical(T.LumenClass));
counts = countcats(categorical(T.LumenClass));
fprintf('\nClassification counts:\n');
for j = 1:numel(cats)
    fprintf('  %-12s: %d\n', cats{j}, counts(j));
end
end