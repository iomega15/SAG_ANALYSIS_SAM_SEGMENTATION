function saveStep2_5Debug(I_cropped, allMasks, allMasksExclusive, numMasks, Hc, Wc, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 1400, 500);
colors = lines(numMasks);

% Original overlapping masks
subplot(1,3,1);
ovBefore = zeros(Hc, Wc, 3);
for m = 1:numMasks
    thisMask = squeeze(allMasks(m,:,:));
    for c = 1:3
        ch = ovBefore(:,:,c);
        ch(thisMask) = colors(m,c);
        ovBefore(:,:,c) = ch;
    end
end
imshow(ovBefore * 0.7 + im2double(I_cropped) * 0.3);
title(sprintf('Before: %d masks (overlapping)', numMasks), 'FontSize', 10);

% Exclusive masks
subplot(1,3,2);
ovAfter = zeros(Hc, Wc, 3);
for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = ovAfter(:,:,c);
        ch(thisMask) = colors(m,c);
        ovAfter(:,:,c) = ch;
    end
end
imshow(ovAfter * 0.7 + im2double(I_cropped) * 0.3);
title(sprintf('After: %d exclusive masks', numMasks), 'FontSize', 10);

% Difference: pixels that changed assignment
subplot(1,3,3);
% Any pixel where the two colorings differ
diff_map = any(abs(ovBefore - ovAfter) > 0.01, 3);
% Show those pixels in red over the image
diffOverlay = im2double(I_cropped);
diffOverlay(:,:,1) = max(diffOverlay(:,:,1), double(diff_map));
diffOverlay(:,:,2) = diffOverlay(:,:,2) .* double(~diff_map);
diffOverlay(:,:,3) = diffOverlay(:,:,3) .* double(~diff_map);
imshow(diffOverlay);
title(sprintf('Reassigned pixels (red)\n%d px changed', sum(diff_map(:))), 'FontSize', 10);

sgtitle(sprintf('%s - STEP 2.5: Exclusive Mask Preparation', baseName), 'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step2_5_exclusive.png');
end