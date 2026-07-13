function textureFeatures = computeAllMaskTextures(Igray, allMasksExclusive, numMasks, maskAreas)
%COMPUTEALLMASKTEXTURES  Interior-only texture scores using percentage-based
% peripheral trimming per row and column.
%
% For each mask:
%   1. Per row: find leftmost and rightmost mask pixel, discard outer 25%
%      on each side, keep central 50%
%   2. Per column: same vertically
%   3. Interior = intersection of horizontal AND vertical central bands
%   4. Scores = edge density within that interior region (Canny and StdFilt separately)
%
% Outputs:
%   textureFeatures - struct with fields:
%       .cannyDensity    - [numMasks x 1] Canny edge density per interior
%       .stdDensity      - [numMasks x 1] Local-std edge density per interior
%       .combinedDensity - [numMasks x 1] combined (OR) edge density per interior

TRIM_FRAC = 0.25;

% Absolute floor for "real" local contrast (gray levels are 0..1). The old
% imbinarize(local_std,'adaptive') was contrast-NORMALIZING: inside a smooth,
% near-uniform lumen it amplified faint sensor noise into dense "texture",
% which made real lumens score HIGHER texture density than the visibly
% striated printed anchor (observed: lumen 0.46-0.88 vs anchor 0.29-0.45),
% and validateLumenTexture then rejected real lumens as "not formed"
% (ratio 1.1-1.7 false negatives, e.g. H5_W9_ML6_R0, H5_W15_ML2_R1).
% An absolute threshold keeps genuine layer striations (strong std) while a
% smooth lumen interior correctly scores near zero.
STD_ABS_THRESH = 0.03;

% --- Compute filters once ---
canny_BW     = edge(Igray, 'Canny', [0.01 0.1]);
local_std    = stdfilt(Igray, ones(5));
local_std_BW = local_std > STD_ABS_THRESH;
combined_BW  = canny_BW | local_std_BW;

[Hc, Wc] = size(Igray);

cannyDensity    = zeros(numMasks, 1);
stdDensity      = zeros(numMasks, 1);
combinedDensity = zeros(numMasks, 1);

for m = 1:numMasks
    if maskAreas(m) < 100
        continue;
    end

    thisMask = squeeze(allMasksExclusive(m, :, :));

    % --- Horizontal trimming: per row ---
    interior_h = false(Hc, Wc);
    for r = 1:Hc
        row_pixels = find(thisMask(r, :));
        if numel(row_pixels) < 4
            continue;
        end
        left  = row_pixels(1);
        right = row_pixels(end);
        span  = right - left;
        trim  = round(span * TRIM_FRAC);
        interior_h(r, (left + trim):(right - trim)) = true;
    end

    % --- Vertical trimming: per column ---
    interior_v = false(Hc, Wc);
    for c = 1:Wc
        col_pixels = find(thisMask(:, c));
        if numel(col_pixels) < 4
            continue;
        end
        top    = col_pixels(1);
        bottom = col_pixels(end);
        span   = bottom - top;
        trim   = round(span * TRIM_FRAC);
        interior_v((top + trim):(bottom - trim), c) = true;
    end

    % --- Interior = must pass BOTH trims AND be within mask ---
    interior      = thisMask & interior_h & interior_v;
    interior_area = sum(interior(:));
    if interior_area < 50
        continue;
    end

    % --- Separate and combined scores ---
    cannyDensity(m)    = sum(canny_BW(interior))     / interior_area;
    stdDensity(m)      = sum(local_std_BW(interior))  / interior_area;
    combinedDensity(m) = sum(combined_BW(interior))   / interior_area;
end

% --- Pack into struct ---
textureFeatures.cannyDensity    = cannyDensity;
textureFeatures.stdDensity      = stdDensity;
textureFeatures.combinedDensity = combinedDensity;
end