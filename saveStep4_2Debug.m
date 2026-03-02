function saveStep4_2Debug(I_cropped, allMasksExclusive, bg_mask_idx, textureFeatures, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 900, 400);
numMasks = size(allMasksExclusive, 1);
colors   = lines(numMasks);

subplot(1,2,1);
overlay = zeros(size(I_cropped,1), size(I_cropped,2), 3);
for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = overlay(:,:,c);
        ch(thisMask) = colors(m,c);
        overlay(:,:,c) = ch;
    end
end
imshow(overlay);
title(sprintf('4.3: Background mask %d (density=%.3f)', bg_mask_idx, textureFeatures.combinedDensity(bg_mask_idx)),'FontSize',10);

subplot(1,2,2);
b = bar([textureFeatures.cannyDensity, textureFeatures.stdDensity, textureFeatures.combinedDensity]);
b(1).FaceColor = [0.2 0.6 1.0];  % blue for Canny
b(2).FaceColor = [1.0 0.5 0.0];  % orange for StdFilt
b(3).FaceColor = [0.4 0.8 0.3];  % green for Combined
xlabel('Mask Index'); ylabel('Edge Density');
legend('Canny', 'StdFilt', 'Combined', 'Location', 'northeast', 'FontSize', 7);
title('4.3: Edge Density per Mask','FontSize',10);
% Annotate background bar with arrow instead of changing color
text(bg_mask_idx, textureFeatures.combinedDensity(bg_mask_idx) + 0.005, 'BG', ...
    'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold', 'Color', 'r');

sgtitle(sprintf('%s - STEP 4.3: Background Identification', baseName),'Interpreter','none','FontSize',12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_3_background.png');
end