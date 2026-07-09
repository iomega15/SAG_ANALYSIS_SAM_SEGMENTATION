function maskAreas = recomputeMaskAreas(allMasksExclusive, numMasks)
    maskAreas = zeros(numMasks, 1);
    for m = 1:numMasks
        thisMask     = squeeze(allMasksExclusive(m, :, :));
        maskAreas(m) = sum(thisMask(:));
    end
end