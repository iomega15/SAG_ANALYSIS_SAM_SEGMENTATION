function allMasksExclusive = prepareExclusiveMasks(allMasks, numMasks, Hc, Wc)

% Fill holes
allMasksFilled = allMasks;
for m = 1:numMasks
    thisMask = squeeze(allMasks(m, :, :));
    allMasksFilled(m, :, :) = imfill(thisMask, 'holes');
end

% Compute area of each mask
maskAreas = zeros(numMasks, 1);
for m = 1:numMasks
    maskAreas(m) = sum(sum(squeeze(allMasksFilled(m, :, :))));
end

% Sort smallest to largest
[~, sortedIdx] = sort(maskAreas, 'ascend');

% Assign each pixel to smallest mask only
allMasksExclusive = false(numMasks, Hc, Wc);
claimedPixels = false(Hc, Wc);

for i = 1:numMasks
    m = sortedIdx(i);
    thisMask = squeeze(allMasksFilled(m, :, :));
    exclusiveMask = thisMask & ~claimedPixels;
    allMasksExclusive(m, :, :) = exclusiveMask;
    claimedPixels = claimedPixels | exclusiveMask;
end

end