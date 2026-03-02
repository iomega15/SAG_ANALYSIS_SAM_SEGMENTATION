function saveStep4_7Debug(I_cropped, allMasksExclusive, lumen_candidates, ...
    selected_mask_idx, selected_polarity, debugFolder, baseName, showFigures)

fig = newFig(showFigures, 1000, 400);
numMasks = size(allMasksExclusive, 1);
[Hc, Wc, ~] = size(I_cropped);
Igray_overlay = im2double(rgb2gray(I_cropped));
base_rgb      = repmat(Igray_overlay * 0.5, [1 1 3]);   % dimmed grayscale backdrop

% Identify discarded candidates (were in lumen_candidates but not selected)
if ~isempty(selected_mask_idx)
    discarded = setdiff(lumen_candidates, selected_mask_idx);
else
    discarded = lumen_candidates;
end

% ---- LEFT PANE: Discarded candidates --------------------------------
subplot(1,2,1);
overlay_disc = base_rgb;

if isempty(discarded)
    imshow(overlay_disc);
    title('4.7: No discarded candidates', 'FontSize', 10);
else
    disc_colors = lines(numel(discarded));
    hold on;
    imshow(overlay_disc);
    for i = 1:numel(discarded)
        m        = discarded(i);
        thisMask = squeeze(allMasksExclusive(m, :, :));
        for c = 1:3
            ch = overlay_disc(:,:,c);
            ch(thisMask) = disc_colors(i, c) * 0.7 + Igray_overlay(thisMask) * 0.3;
            overlay_disc(:,:,c) = ch;
        end
    end
    imshow(overlay_disc); hold on;

    % Label each discarded mask at its centroid
    for i = 1:numel(discarded)
        m        = discarded(i);
        thisMask = squeeze(allMasksExclusive(m, :, :));
        rp       = regionprops(thisMask, 'Centroid', 'Area');
        if ~isempty(rp)
            [~, biggest] = max([rp.Area]);
            cx = rp(biggest).Centroid(1);
            cy = rp(biggest).Centroid(2);
            text(cx, cy, sprintf('mask %d', m), ...
                'Color', disc_colors(i,:), 'FontSize', 9, ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'center', ...
                'BackgroundColor', [0 0 0 0.4]);
        end
    end
    hold off;
    title(sprintf('4.7: Discarded candidates (%d)', numel(discarded)), ...
        'FontSize', 10, 'Color', 'r');
end

% ---- RIGHT PANE: Selected lumen mask --------------------------------
subplot(1,2,2);
overlay_sel = base_rgb;

if ~isempty(selected_mask_idx)
    selMask = squeeze(allMasksExclusive(selected_mask_idx, :, :));

    % Green tint blended with image
    for c = 1:3
        ch = overlay_sel(:,:,c);
        green_val = [0.2, 1.0, 0.2];
        ch(selMask) = green_val(c) * 0.5 + Igray_overlay(selMask) * 0.5;
        overlay_sel(:,:,c) = ch;
    end
    imshow(overlay_sel); hold on;

    % Mark centroid
    rp = regionprops(selMask, 'Centroid', 'Area');
    if ~isempty(rp)
        [~, biggest] = max([rp.Area]);
        cx = rp(biggest).Centroid(1);
        cy = rp(biggest).Centroid(2);
        plot(cx, cy, 'g+', 'MarkerSize', 14, 'LineWidth', 2);
    end

    % Mark image center for reference
    plot(Wc/2, Hc/2, 'wx', 'MarkerSize', 12, 'LineWidth', 2);
    legend({'Centroid', 'Image center'}, 'TextColor', 'w', ...
        'Color', [0.1 0.1 0.1], 'Location', 'southeast');
    hold off;

    title(sprintf('4.7: Selected mask %d (green)\nPolarity: %s', ...
        selected_mask_idx, selected_polarity), 'FontSize', 10);
else
    imshow(overlay_sel);
    title('4.7: No lumen selected', 'FontSize', 10, 'Color', 'r');
end

sgtitle(sprintf('%s — STEP 4.7: Central Candidate Selection', baseName), ...
    'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_7_selection.png');
end