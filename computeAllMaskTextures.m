function [textureFeatures, maskAreas] = computeAllMaskTextures(Igray, allMasksExclusive, numMasks)
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
%   maskAreas       - [numMasks x 1] total mask pixel count

TRIM_FRAC = 0.25;  % discard this fraction from each side

% --- Compute filters once ---
canny_BW     = edge(Igray, 'Canny', [0.01 0.1]);
local_std    = stdfilt(Igray, ones(5));
local_std_BW = imbinarize(local_std, 'adaptive');
combined_BW  = canny_BW | local_std_BW;

[Hc, Wc] = size(Igray);

cannyDensity    = zeros(numMasks, 1);
stdDensity      = zeros(numMasks, 1);
combinedDensity = zeros(numMasks, 1);
maskAreas       = zeros(numMasks, 1);

for m = 1:numMasks
    thisMask     = squeeze(allMasksExclusive(m, :, :));
    maskAreas(m) = sum(thisMask(:));

    if maskAreas(m) < 100
        continue;
    end

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
    interior = thisMask & interior_h & interior_v;
    interior_area = sum(interior(:));

    if interior_area < 50
        continue;
    end

    % --- Separate and combined scores ---
    cannyDensity(m)    = sum(canny_BW(interior))    / interior_area;
    stdDensity(m)      = sum(local_std_BW(interior)) / interior_area;
    combinedDensity(m) = sum(combined_BW(interior))  / interior_area;
end

% --- Pack into struct ---
textureFeatures.cannyDensity    = cannyDensity;
textureFeatures.stdDensity      = stdDensity;
textureFeatures.combinedDensity = combinedDensity;
end