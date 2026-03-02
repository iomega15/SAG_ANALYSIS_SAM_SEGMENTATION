function [lumen_candidates, removed_outside_anchor] = ...
    eliminateOutsideMaterialBounds(allMasksExclusive, lumen_candidates, material_top_Y, material_bot_Y)

removed_outside_anchor = [];
keep                   = true(size(lumen_candidates));

for i = 1:numel(lumen_candidates)
    m        = lumen_candidates(i);
    thisMask = squeeze(allMasksExclusive(m, :, :));
    rp_cand  = regionprops(thisMask, 'Centroid');
    if ~isempty(rp_cand)
        centroid_Y = rp_cand(1).Centroid(2);
        % Lumen centroid must fall within vertical extent of 3D-printed anchor
        if centroid_Y < material_top_Y || centroid_Y > material_bot_Y
            keep(i) = false;
        end
    end
end

removed_outside_anchor = lumen_candidates(~keep);
lumen_candidates         = lumen_candidates(keep);
end