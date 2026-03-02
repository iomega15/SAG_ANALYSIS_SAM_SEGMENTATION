  function maskAreas = computeMaskAreas(allMasksExclusive, numMasks)
% COMPUTEMASKAREAS  Compute pixel area of each exclusive mask.

maskAreas = zeros(numMasks, 1);
for m = 1:numMasks
    thisMask     = squeeze(allMasksExclusive(m, :, :));
    maskAreas(m) = sum(thisMask(:));
end
end