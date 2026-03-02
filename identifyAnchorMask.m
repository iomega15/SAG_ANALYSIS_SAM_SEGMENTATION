function [anchor_mask_indices, anchor_mask, anchor_area_weighed_texture, ...
          anchor_top_Y, anchor_bot_Y, lumen_candidates] = ...
    identifyAnchorMask(allMasksExclusive, maskAreas, textureFeatures, ...
                       lumen_candidates, numMasks, Hc, Wc)

% --- Find all masks physically surrounding mask 1 ---
surrounding_masks = findSurroundingMasks(allMasksExclusive, numMasks, Hc, Wc);

if isempty(surrounding_masks)
    warning('identifyAnchorMask: no surrounding masks found, falling back to texture score');
    search_pool       = setdiff(lumen_candidates, 1);
    scores            = maskAreas(search_pool) .* textureFeatures(search_pool);
    [~, best_i]       = max(scores);
    surrounding_masks = search_pool(best_i);
end

% --- Extend: any remaining mask with texture >= 50% of surrounding combined ---
%total_anchor_area       = sum(maskAreas(surrounding_masks));
ALL_anchors_edge_area = sum(maskAreas(surrounding_masks) .* textureFeatures(surrounding_masks));
%anchor_area_weighed_texture   =  ALL_anchors_edge_area / total_anchor_area;
remaining        = setdiff(lumen_candidates, [1; surrounding_masks(:)]);
for m = remaining
    if maskAreas(m) > 1000 && textureFeatures(m)*maskAreas(m) >= ALL_anchors_edge_area * 0.5
        % Exclude masks touching the bottom border — these are substrate/support
        thisMask = squeeze(allMasksExclusive(m, :, :));
        if any(thisMask(end, :))
            continue;
        end
        surrounding_masks(end+1) = m; 
    end
end

% --- All structure masks together ARE the anchor ---
anchor_mask_indices = surrounding_masks;

% --- Build joined anchor mask ---
anchor_mask = false(Hc, Wc);
for m = anchor_mask_indices
    anchor_mask = anchor_mask | squeeze(allMasksExclusive(m, :, :));
end

% --- Clean joined anchor mask ---
[anchor_mask_cleaned, ~, ~, ~, ~, ~] = cleanCenterMask(anchor_mask);

% --- Recompute anchor_area_weighed_texture using cleaned joined mask ---
total_anchor_area     = sum(maskAreas(anchor_mask_indices));
anchor_area_weighed_texture = sum(maskAreas(anchor_mask_indices) .* textureFeatures(anchor_mask_indices)) / total_anchor_area;

% --- Vertical bounds from cleaned joined mask ---
anchor_top_Y = find(any(anchor_mask_cleaned, 2), 1, 'first');
anchor_bot_Y = find(any(anchor_mask_cleaned, 2), 1, 'last');

% --- Remove all structure masks from candidate pool ---
lumen_candidates = setdiff(lumen_candidates, anchor_mask_indices);

if numel(anchor_mask_indices) > 1
    fprintf('  Anchor: %d structure masks → bounds Y=[%d, %d]\n', ...
        numel(anchor_mask_indices), anchor_top_Y, anchor_bot_Y);
end
end