function saveStep4_8Debug(I_cropped, allMasksExclusive, ...
    selected_mask_idx, anchor_mask, ...
    texture_contrast, lumen_density, anchor_density, lumen_valid, ...
    debugFolder, baseName, CONTRAST_THRESHOLD, showFigures)

%[Hc, Wc, ~] = size(I_cropped);
Igray_overlay = im2double(rgb2gray(I_cropped));
base_rgb      = repmat(Igray_overlay * 0.4, [1 1 3]);

fig = newFig(showFigures, 1400, 450);

% ---- LEFT: Anchor mask (red) vs Selected candidate (green) ----------
subplot(1,3,1);
overlay = base_rgb;

% Joined anchor in red
for c = 1:3
    ch = overlay(:,:,c);
    red = [0.9, 0.2, 0.2];
    ch(anchor_mask) = red(c) * 0.6 + Igray_overlay(anchor_mask) * 0.4;
    overlay(:,:,c) = ch;
end

% Selected candidate in green
if ~isempty(selected_mask_idx)
    selMask = squeeze(allMasksExclusive(selected_mask_idx, :, :));
    for c = 1:3
        ch = overlay(:,:,c);
        green = [0.2, 1.0, 0.2];
        ch(selMask) = green(c) * 0.6 + Igray_overlay(selMask) * 0.4;
        overlay(:,:,c) = ch;
    end
end
imshow(overlay); hold on;

anchor_label = 'Anchor (portion)';
%anchor_label = sprintf('Anchor (masks %s)', num2str(anchor_mask_indices));
h_anchor = patch(NaN, NaN, [0.9, 0.2, 0.2], 'EdgeColor', 'none', 'DisplayName', anchor_label);
if ~isempty(selected_mask_idx)
    h_cand = patch(NaN, NaN, [0.2, 1.0, 0.2], 'EdgeColor', 'none', ...
        'DisplayName', sprintf('Candidate (#%d)', selected_mask_idx));
    legend([h_anchor, h_cand], 'TextColor', 'w', 'Color', [0.1 0.1 0.1 0.7], ...
        'Location', 'southoutside', 'FontSize', 9, 'Orientation', 'horizontal');
else
    legend(h_anchor, 'TextColor', 'w', 'Color', [0.1 0.1 0.1 0.7], ...
        'Location', 'southoutside', 'FontSize', 9);
end
hold off;
title('Anchor vs Candidate', 'FontSize', 10);

% ---- MIDDLE: Bar chart --------------------------------------------------
subplot(1,3,2);
bar_labels = {anchor_label};
bar_vals   = [anchor_density];
bar_colors = [0.9, 0.2, 0.2];

if ~isempty(selected_mask_idx)
    bar_labels{end+1}   = sprintf('Candidate (#%d)', selected_mask_idx);
    bar_vals(end+1)     = lumen_density;
    bar_colors(end+1,:) = [0.2, 0.8, 0.2];
end

b = bar(bar_vals, 0.6); b.FaceColor = 'flat';
for k = 1:numel(bar_vals)
    b.CData(k,:) = bar_colors(k,:);
end
set(gca, 'XTickLabel', bar_labels, 'FontSize', 9);
ylabel('Edge Density');
title(sprintf('Texture Contrast = %.2f\n(anchor − lumen) / anchor', texture_contrast), 'FontSize', 10);

% ---- RIGHT: Verdict ------------------------------------------------------
subplot(1,3,3);
axis off; hold on;

if lumen_valid
    verdict_str   = 'PASS';
    verdict_color = [0.1, 0.7, 0.1];
else
    verdict_str   = 'FAIL';
    verdict_color = [0.9, 0.1, 0.1];
end

text(0.5, 0.7, verdict_str, 'FontSize', 36, 'FontWeight', 'bold', ...
    'Color', verdict_color, 'HorizontalAlignment', 'center', 'Units', 'normalized');

info_lines = {
    sprintf('Anchor density:    %.4f', anchor_density)
    sprintf('Lumen density:     %.4f', lumen_density)
    sprintf('Texture contrast:  %.2f', texture_contrast)
    sprintf('Threshold:         %.2f', CONTRAST_THRESHOLD)
    ''
    sprintf('Candidate is %s smooth', ternary(lumen_valid, 'sufficiently', 'NOT'))
};
text(0.5, 0.35, info_lines, 'FontSize', 10, 'HorizontalAlignment', 'center', ...
    'Units', 'normalized', 'VerticalAlignment', 'top');
hold off;
title('4.8: Texture Validation Verdict', 'FontSize', 10);

sgtitle(sprintf('%s — STEP 4.8: Texture Validation (Candidate vs Anchor)', baseName), ...
    'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_8_texture_validation.png');
end

function out = ternary(cond, valTrue, valFalse)
    if cond, out = valTrue; else, out = valFalse; end
end