function [lumen_candidates, removed_border] = ...
    eliminateBorderCandidates(allMasksExclusive, lumen_candidates)

removed_border = [];
keep           = true(size(lumen_candidates));

for i = 1:numel(lumen_candidates)
    m        = lumen_candidates(i);
    thisMask = squeeze(allMasksExclusive(m, :, :));
    % A mask touching any image border cannot be an enclosed lumen
    if any(thisMask(1,:)) || any(thisMask(end,:)) || ...
       any(thisMask(:,1)) || any(thisMask(:,end))
        keep(i) = false;
    end
end

removed_border = lumen_candidates(~keep);
lumen_candidates = lumen_candidates(keep);
end