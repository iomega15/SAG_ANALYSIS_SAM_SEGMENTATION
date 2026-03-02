function [anchor_mask, anchor_texture, material_top_Y, material_bot_Y, lumen_candidates, ...
          top_band_labels, candidateIndices, portion_masks, portion_areas, portion_textures, ...
          lumen_bot_row, top_band] = ...
    identifyAnchorMask(allMasksExclusive, lumen_candidates, Hc, Wc, bg_mask, Igray)

numMasks = size(allMasksExclusive, 1);
mask1    = squeeze(allMasksExclusive(1, :, :));

% --- Build label matrix ---
labelMatrix = zeros(Hc, Wc);
for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m, :, :));
    labelMatrix(thisMask) = m;
end

lumen_cols = find(any(mask1, 1));

% =====================================================================
%  BAND 1 (TOP): lumen top -> background, per column
% =====================================================================
top_band = false(Hc, Wc);
for col = lumen_cols
    lumen_top_row = find(mask1(:, col), 1, 'first');
    if isempty(lumen_top_row), continue; end
    for r = lumen_top_row - 1 : -1 : 1
        if bg_mask(r, col)
            break;
        end
        top_band(r, col) = true;
    end
end

top_band_labels = unique(labelMatrix(top_band));
top_band_labels = top_band_labels(top_band_labels > 0 & top_band_labels ~= 1);
top_band_labels = intersect(top_band_labels, lumen_candidates);

if ~isempty(top_band_labels)
    top_mask = false(Hc, Wc);
    for m = top_band_labels(:)'
        thisMask = squeeze(allMasksExclusive(m, :, :));
        top_mask = top_mask | (thisMask & top_band);
    end
    material_top_Y = find(any(top_mask, 2), 1, 'first');
else
    material_top_Y = find(any(mask1, 2), 1, 'first');
end
if isempty(material_top_Y), material_top_Y = 1; end

% =====================================================================
%  BELOW LUMEN: full width, below lumen bottom row
% =====================================================================
lumen_bot_row = find(any(mask1, 2), 1, 'last');
below_lumen   = false(Hc, Wc);
below_lumen(lumen_bot_row + 1 : Hc, :) = true;

% --- Find all masks that intersect below-lumen region ---
below_lumen_labels = unique(labelMatrix(below_lumen));
below_lumen_labels = below_lumen_labels(below_lumen_labels > 0 & below_lumen_labels ~= 1);
below_lumen_labels = intersect(below_lumen_labels, lumen_candidates);

candidates = setdiff(lumen_candidates, 1);

% --- Accumulate candidate portions for anchor selection ---
portion_masks    = {};
portion_areas    = [];
portion_textures = [];
candidateIndices = [];

for m = candidates(:)'
    thisMask = squeeze(allMasksExclusive(m, :, :));
    portion  = thisMask & below_lumen;
    if sum(portion(:)) < 100
        continue;
    end

    p_area           = sum(portion(:));
    portionExclusive = reshape(portion, [1 Hc Wc]);
    p_maskArea       = computeMaskAreas(portionExclusive, 1);
    p_texFeatures    = computeAllMaskTextures(Igray, portionExclusive, 1, p_maskArea);

    portion_masks{end+1}    = portion;                          %#ok<AGROW>
    portion_areas(end+1)    = p_area;                           %#ok<AGROW>
    portion_textures(end+1) = p_texFeatures.combinedDensity(1); %#ok<AGROW>
    candidateIndices(end+1) = m;                                %#ok<AGROW>
end

% --- Select best portion: highest area x texture ---
if ~isempty(candidateIndices)
    scores      = portion_areas .* portion_textures;
    [~, best_i] = max(scores);
    anchor_mask    = portion_masks{best_i};
    anchor_texture = portion_textures(best_i);
    material_bot_Y = find(any(anchor_mask, 2), 1, 'last');
    if isempty(material_bot_Y), material_bot_Y = Hc; end
    fprintf('  Anchor: mask %d portion, texture=%.3f, Y=[%d, %d]\n', ...
        candidateIndices(best_i), anchor_texture, material_top_Y, material_bot_Y);
else
    anchor_mask    = below_lumen;
    anchor_texture = 0;
    material_bot_Y = Hc;
    fprintf('  Anchor: fallback to full below-lumen region\n');
end

% =====================================================================
%  PRUNE lumen_candidates: remove masks in top band or below lumen
% =====================================================================
masks_to_remove = union(top_band_labels, below_lumen_labels);
lumen_candidates = setdiff(lumen_candidates, masks_to_remove);

fprintf('  Pruned %d mask(s) from lumen_candidates (top_band: [%s], below_lumen: [%s])\n', ...
    numel(masks_to_remove), ...
    num2str(top_band_labels(:)'), ...
    num2str(below_lumen_labels(:)'));

end