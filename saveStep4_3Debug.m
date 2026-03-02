function saveStep4_3Debug(I_cropped, allMasksExclusive, anchor_mask, ...
    material_top_Y, material_bot_Y, top_band_labels, contributing, ...
    portion_masks, portion_areas, portion_textures, ...
    textureFeatures, lumen_bot_row, top_band, ...
    debugFolder, baseName, showFigures)

numMasks = size(allMasksExclusive, 1);
colors   = lines(numMasks);
nc = numel(contributing);
nt = numel(top_band_labels);

% Find winning portion index
if nc > 0
    [~, best_i] = max(portion_areas .* portion_textures);
    winning_mask_idx = contributing(best_i);
else
    best_i = [];
    winning_mask_idx = [];
end

fig = newFig(showFigures, 1500, 500);
Igray_display = im2double(rgb2gray(I_cropped));

% --- Panel 1: Image with top band + below-lumen portions + boundaries ---
subplot(1,3,1);
overlay = repmat(Igray_display, [1 1 3]);

% Color top band portions
for mi = 1:nt
    m = top_band_labels(mi);
    thisMask = squeeze(allMasksExclusive(m, :, :)) & top_band;
    for c = 1:3
        ch = overlay(:,:,c);
        ch(thisMask) = colors(m,c) * 0.6 + ch(thisMask) * 0.4;
        overlay(:,:,c) = ch;
    end
end

% Color below-lumen portions
for mi = 1:nc
    thisPortion = portion_masks{mi};
    m = contributing(mi);
    for c = 1:3
        ch = overlay(:,:,c);
        ch(thisPortion) = colors(m,c) * 0.6 + ch(thisPortion) * 0.4;
        overlay(:,:,c) = ch;
    end
end

% Highlight winning anchor portion brighter
overlay(:,:,1) = min(overlay(:,:,1) + 0.3 * double(anchor_mask), 1);
overlay(:,:,2) = min(overlay(:,:,2) + 0.3 * double(anchor_mask), 1);
overlay(:,:,3) = min(overlay(:,:,3) + 0.3 * double(anchor_mask), 1);

% Boundary lines — fat (5px)
LINE_W = 25;
for d = 0:LINE_W-1
    r = min(lumen_bot_row + d, size(overlay,1));
    overlay(r, :, 1) = 0; overlay(r, :, 2) = 0; overlay(r, :, 3) = 1;  % blue

    r = max(material_top_Y - d, 1);
    overlay(r, :, 1) = 0; overlay(r, :, 2) = 1; overlay(r, :, 3) = 1;  % cyan

    r = min(material_bot_Y + d, size(overlay,1));
    overlay(r, :, 1) = 1; overlay(r, :, 2) = 0; overlay(r, :, 3) = 1;  % magenta
end

imshow(overlay); hold on;
all_shown = union(top_band_labels(:)', contributing(:)');
if ~isempty(all_shown)
    lh = gobjects(numel(all_shown) + 3, 1);
    for mi = 1:numel(all_shown)
        lh(mi) = patch(NaN, NaN, colors(all_shown(mi),:));
    end
    lh(end-2) = plot(NaN, NaN, '-', 'Color', [0 1 1], 'LineWidth', 2);
    lh(end-1) = plot(NaN, NaN, '-', 'Color', [0 0 1], 'LineWidth', 2);  
    lh(end)   = plot(NaN, NaN, '-', 'Color', [1 0 1], 'LineWidth', 2);
    ll = [arrayfun(@(m) sprintf('Mask %d', m), all_shown, 'UniformOutput', false), ...
          {'Anchor top'}, {'Lumen bottom'},{'Anchor bot'}];
    legend(lh, ll, 'Location', 'southeastoutside', 'FontSize', 7);
end
hold off;
title('Top Band + Below-Lumen Portions', 'FontSize', 10);

% --- Panel 2: Portion edge densities (all scores are portion-based) ---
subplot(1,3,2);
if nc > 0
    portion_canny = textureFeatures.cannyDensity(contributing(:));
    portion_std   = textureFeatures.stdDensity(contributing(:));

    x = 1:nc;
    hold on;
    b1 = bar(x - 0.25, portion_textures(:), 0.2, 'FaceColor', [0.4 0.8 0.3]);
    b2 = bar(x,         portion_canny(:),   0.2, 'FaceColor', [0.2 0.6 1.0]);
    b3 = bar(x + 0.25, portion_std(:),      0.2, 'FaceColor', [1.0 0.4 0.1]);
    hold off;

    set(gca, 'XTick', x, 'XTickLabel', arrayfun(@(m) sprintf('M%d', m), ...
        contributing, 'UniformOutput', false));
    xlabel('Mask'); ylabel('Portion Edge Density');
    legend([b1 b2 b3], {'Combined', 'Canny', 'StdFilt'}, 'Location', 'best', 'FontSize', 7);
else
    axis off;
    text(0.5, 0.5, 'No below-lumen portions', 'HorizontalAlignment', 'center', 'FontSize', 11);
end

% --- Panel 3: Portion area x texture scores + winner annotation ---
subplot(1,3,3);
if nc > 0
    scores = portion_areas .* portion_textures;
    b = bar(scores); b.FaceColor = 'flat';
    for mi = 1:nc
        b.CData(mi,:) = colors(contributing(mi),:);
    end
    set(gca, 'XTickLabel', arrayfun(@(m) sprintf('M%d', m), ...
        contributing, 'UniformOutput', false));
    xlabel('Mask'); ylabel('Portion Area × Density');
    % Annotate winner
    if ~isempty(best_i)
        text(best_i, scores(best_i), sprintf('  WINNER\nMask %d', winning_mask_idx), ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', 'r', ...
            'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'center');
    end
else
    axis off;
    text(0.5, 0.5, 'No below-lumen portions', 'HorizontalAlignment', 'center', 'FontSize', 11);
end
title('Below-Lumen Portions: Area × Density', 'FontSize', 10);

sgtitle(sprintf('%s - STEP 4.3: Anchor Mask Construction', baseName), ...
    'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_3_anchor.png');
end