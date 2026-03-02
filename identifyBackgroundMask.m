function [bg_mask_idx, lumen_candidates] = identifyBackgroundMask(allMasksExclusive, maskAreas, ...
                           Igray_cropped_dbl, lumen_candidates)

% Search all masks except mask 1 (lumen)
search_pool = setdiff(lumen_candidates, 1);

bg_scores = zeros(numel(search_pool), 1);
for i = 1:numel(search_pool)
    m        = search_pool(i);
    thisMask = squeeze(allMasksExclusive(m, :, :));
    if maskAreas(m) > 0
        bg_scores(i) = maskAreas(m) * mean(Igray_cropped_dbl(thisMask));
    end
end

if ~isempty(bg_scores)
    [~, bg_local] = max(bg_scores);
    bg_mask_idx   = search_pool(bg_local);
else
    bg_mask_idx = 1;  % fallback
end

lumen_candidates = setdiff(lumen_candidates, bg_mask_idx);
end