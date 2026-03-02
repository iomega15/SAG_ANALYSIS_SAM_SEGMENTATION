function [BW_center_cleaned, keepIdx, removeIdx, rp, allAreas, nRegions] = ...
    cleanCenterMask(BW_center_raw)
% CLEANCENTERMASSK  Log-area 3-class Otsu cleanup of SAM center mask.

BW_center_cleaned = BW_center_raw;
keepIdx   = [];
removeIdx = [];
rp        = [];
allAreas  = [];
nRegions  = 0;

if ~any(BW_center_raw(:))
    return;
end

rp       = regionprops(BW_center_raw, 'Area', 'PixelIdxList', 'BoundingBox', 'Centroid');
allAreas = [rp.Area];
nRegions = numel(rp);

if nRegions > 2
    logAreas = log10(allAreas + 1);
    try
        levels     = multithresh(logAreas, 2);
        class2_idx = find(logAreas >= levels(1) & logAreas < levels(2));
        class3_idx = find(logAreas >= levels(2));
        keepIdx    = class3_idx;
        for k = class2_idx
            if (levels(2) - logAreas(k)) < (logAreas(k) - levels(1))
                keepIdx = [keepIdx, k]; %#ok<AGROW>
            end
        end
        removeIdx         = setdiff(1:nRegions, keepIdx);
        BW_center_cleaned = false(size(BW_center_raw));
        for idx = keepIdx
            BW_center_cleaned(rp(idx).PixelIdxList) = true;
        end
    catch
        [~, maxIdx]       = max(allAreas);
        BW_center_cleaned = false(size(BW_center_raw));
        BW_center_cleaned(rp(maxIdx).PixelIdxList) = true;
        keepIdx   = maxIdx;
        removeIdx = setdiff(1:nRegions, maxIdx);
    end
else
    [~, maxIdx]       = max(allAreas);
    BW_center_cleaned = false(size(BW_center_raw));
    BW_center_cleaned(rp(maxIdx).PixelIdxList) = true;
    keepIdx   = maxIdx;
    removeIdx = setdiff(1:nRegions, maxIdx);
end
end