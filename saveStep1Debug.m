function saveStep1Debug(I_cropped, BW_center_raw, allMasks, numMasks, target_x, target_y, confidence, Hc, Wc, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 1600, 500);
subplot(1,4,1); imshow(I_cropped); hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 25, 'LineWidth', 3); hold off;
title('Input + Target', 'FontSize', 10);
subplot(1,4,2); imshow(BW_center_raw);
title(sprintf('Center Mask (raw)\n%d pixels, conf=%.2f', sum(BW_center_raw(:)), confidence), 'FontSize', 10);
subplot(1,4,3); imshow(labeloverlay(I_cropped, BW_center_raw, 'Colormap', [1 1 0], 'Transparency', 0.4));
title('Center Mask Overlay', 'FontSize', 10);
subplot(1,4,4);
maskOverlay = zeros(Hc, Wc, 3); colors = lines(numMasks);
for m = 1:numMasks
    thisMask = squeeze(allMasks(m,:,:));
    for c=1:3; ch=maskOverlay(:,:,c); ch(thisMask)=colors(m,c); maskOverlay(:,:,c)=ch; end
end
imshow(maskOverlay*0.6 + im2double(I_cropped)*0.4);
title(sprintf('All %d SAM Masks', numMasks), 'FontSize', 10);
sgtitle(sprintf('%s - STEP 1: SAM Output', baseName), 'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step1_sam_output.png');
end