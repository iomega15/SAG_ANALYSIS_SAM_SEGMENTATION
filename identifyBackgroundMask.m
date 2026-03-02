function [bg_mask_idx, bg_mask, lumen_candidates] = identifyBackgroundMask( ...
    allMasksExclusive, maskAreas, Igray_cropped_dbl, lumen_candidates, textureFeatures)

lumen_mask    = squeeze(allMasksExclusive(1, :, :));
lumen_top_row = find(any(lumen_mask, 2), 1, 'first');
if isempty(lumen_top_row), lumen_top_row = 1; end

search_pool = setdiff(lumen_candidates, 1);
bg_scores   = zeros(numel(search_pool), 1);

for i = 1:numel(search_pool)
    m        = search_pool(i);
    thisMask = squeeze(allMasksExclusive(m, :, :));
    if maskAreas(m) == 0, continue; end

    % --- Spatial prior: must be majority above lumen ---
    rows_of_mask = find(any(thisMask, 2));
    frac_above   = sum(rows_of_mask < lumen_top_row) / numel(rows_of_mask);
    if frac_above < 0.5
        continue;
    end

    % --- Texture prior: background should be smooth ---
    tex = textureFeatures.combinedDensity(m);
    if tex > 0.5
        continue;
    end

    % --- Score: large, bright, above lumen, smooth ---
    smoothness   = 1 - tex;
    bg_scores(i) = maskAreas(m) * mean(Igray_cropped_dbl(thisMask)) ...
                   * frac_above * smoothness;
end

if any(bg_scores > 0)
    [~, bg_local] = max(bg_scores);
    bg_mask_idx   = search_pool(bg_local);
else
    warning('identifyBackgroundMask: no candidate passed spatial/texture gates, falling back to brightest above lumen');
    for i = 1:numel(search_pool)
        m        = search_pool(i);
        thisMask = squeeze(allMasksExclusive(m, :, :));
        if maskAreas(m) == 0, continue; end
        rows_of_mask = find(any(thisMask, 2));
        frac_above   = sum(rows_of_mask < lumen_top_row) / numel(rows_of_mask);
        bg_scores(i) = maskAreas(m) * mean(Igray_cropped_dbl(thisMask)) * frac_above;
    end
    [~, bg_local] = max(bg_scores);
    bg_mask_idx   = search_pool(bg_local);
end

lumen_candidates = setdiff(lumen_candidates, bg_mask_idx);
bg_mask          = squeeze(allMasksExclusive(bg_mask_idx, :, :));
end