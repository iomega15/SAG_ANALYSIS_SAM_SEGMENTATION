function saveFinalSummaryDebug(I_cropped, BW_raw, BW_lumen, BW_3d_printed, ...
    allMasksExclusive, numMasks, quality, target_x, target_y, ...
    debugFolder, baseName, showFigures)
%SAVEFINALSUMMARYDEBUG  8-panel overview of the full segmentation pipeline.

fig = newFig(showFigures, 1800, 600);
[Hc, Wc, ~] = size(I_cropped);
colors = lines(numMasks);

% --- 1. Input + Target ---
subplot(2,4,1);
imshow(I_cropped); hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 20, 'LineWidth', 2); hold off;
title('1. Input + Target', 'FontSize', 10);

% --- 2. Raw Center Mask ---
subplot(2,4,2);
imshow(BW_raw);
title('2. Raw Center Mask', 'FontSize', 10);

% --- 3. All Masks ---
subplot(2,4,3);
mo = zeros(Hc, Wc, 3);
for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = mo(:,:,c);
        ch(thisMask) = colors(m,c);
        mo(:,:,c) = ch;
    end
end
imshow(mo * 0.6 + im2double(I_cropped) * 0.4);
title(sprintf('3. All %d Masks', numMasks), 'FontSize', 10);

% --- 4. 3D-Printed Anchor ---
subplot(2,4,4);
imshow(BW_3d_printed);
title('4. Anchor (3D-printed)', 'FontSize', 10);

% --- 5. Final Lumen ---
subplot(2,4,5);
imshow(BW_lumen);
title(sprintf('5. Final Lumen\n%d px', sum(BW_lumen(:))), 'FontSize', 10);

% --- 6. Overlay with polarity color ---
subplot(2,4,6);
if strcmp(quality.polarity, 'bright')
    oc = [0 1 0];
elseif strcmp(quality.polarity, 'dark')
    oc = [1 0.5 0];
else
    oc = [1 1 0];
end
imshow(labeloverlay(I_cropped, BW_lumen, 'Colormap', oc, 'Transparency', 0.4));
title(sprintf('6. Overlay\nPolarity: %s', upper(quality.polarity)), 'FontSize', 10);

% --- 7. Structure (R) + Lumen (G) ---
subplot(2,4,7);
ov = im2double(I_cropped);
for c = 1:3
    ch = ov(:,:,c);
    if c == 1
        ch(BW_3d_printed) = ch(BW_3d_printed) * 0.5 + 0.5;
    else
        ch(BW_3d_printed) = ch(BW_3d_printed) * 0.5;
    end
    ov(:,:,c) = ch;
end
for c = 1:3
    ch = ov(:,:,c);
    if c == 2
        ch(BW_lumen) = ch(BW_lumen) * 0.5 + 0.5;
    else
        ch(BW_lumen) = ch(BW_lumen) * 0.5;
    end
    ov(:,:,c) = ch;
end
imshow(ov);
title('7. Anchor(R) + Lumen(G)', 'FontSize', 10);

% --- 8. Quality Summary ---
subplot(2,4,8);
axis off;

if quality.lumen_valid
    sc = [0 0.6 0];
else
    sc = [0.8 0 0];
end

y = 0.96;
dy = 0.10;

text(0.05, y, 'QUALITY SUMMARY:', 'FontSize', 11, 'FontWeight', 'bold'); y = y - dy;
text(0.05, y, sprintf('Status: %s', quality.status), 'FontSize', 10, 'Color', sc); y = y - dy;
text(0.05, y, sprintf('Valid: %d', quality.lumen_valid), 'FontSize', 10); y = y - dy;
text(0.05, y, sprintf('Polarity: %s', upper(quality.polarity)), 'FontSize', 10); y = y - dy;
text(0.05, y, sprintf('Confidence: %.2f', quality.confidence), 'FontSize', 10); y = y - dy;
text(0.05, y, sprintf('Masks: %d total', quality.num_masks), 'FontSize', 10); y = y - dy;

if isfield(quality, 'texture_contrast')
    text(0.05, y, sprintf('Texture contrast: %.2f', quality.texture_contrast), 'FontSize', 10); y = y - dy;
end

if isfield(quality, 'lumen_area_px') && ~isnan(quality.lumen_area_px)
    text(0.05, y, sprintf('Lumen area: %d px', quality.lumen_area_px), 'FontSize', 10); y = y - dy;
end

if ~isempty(quality.rejection_reason)
    text(0.05, y, sprintf('Reason: %s', quality.rejection_reason), ...
        'FontSize', 9, 'Color', 'r');
end

% --- Supertitle ---
if quality.lumen_valid
    tc = [0 0.5 0];
    ss = sprintf('LUMEN FOUND - %s', upper(quality.polarity));
else
    tc = [0.8 0 0];
    ss = 'NO LUMEN';
end
sgtitle(sprintf('%s - FINAL: %s', baseName, ss), ...
    'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold', 'Color', tc);

saveFig(fig, showFigures, debugFolder, baseName, '_FINAL.png');
end