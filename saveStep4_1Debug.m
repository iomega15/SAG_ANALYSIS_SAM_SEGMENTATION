function saveStep4_1Debug(I_cropped, allMasksExclusive, textureFeatures, maskAreas, numMasks, Hc, Wc, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 1800, 500);
colors = lines(numMasks);

subplot(1,4,1);
b = bar([textureFeatures.cannyDensity, textureFeatures.stdDensity, textureFeatures.combinedDensity]);
b(1).FaceColor = [0.2 0.6 1.0];  % blue for Canny
b(2).FaceColor = [1.0 0.5 0.0];  % orange for StdFilt
b(3).FaceColor = [0.4 0.8 0.3];  % green for Combined
xlabel('Mask Index'); ylabel('Edge Density');
legend('Canny', 'StdFilt', 'Combined', 'Location', 'northeastoutside', 'FontSize', 7);
title('4.1: Edge Density per Mask', 'FontSize', 10);

subplot(1,4,2);
b = bar(maskAreas);
b.FaceColor = 'flat';
b.CData = colors;
xlabel('Mask Index'); ylabel('Area (px)');
title('4.1: Mask Areas', 'FontSize', 10);

subplot(1,4,3);
scores = maskAreas .* textureFeatures.combinedDensity;
b = bar(scores);
b.FaceColor = 'flat';
b.CData = colors;
xlabel('Mask Index'); ylabel('Area \times Combined Density');
title('4.1: Combined Scores', 'FontSize', 10);

subplot(1,4,4);
maskOverlay = zeros(Hc, Wc, 3);
for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = maskOverlay(:,:,c);
        ch(thisMask) = colors(m,c);
        maskOverlay(:,:,c) = ch;
    end
end
imshow(maskOverlay*0.7 + im2double(I_cropped)*0.3); hold on;

% Legend: one dummy patch per mask
legendHandles = gobjects(numMasks, 1);
for m = 1:numMasks
    legendHandles(m) = patch(NaN, NaN, colors(m,:));
end
legend(legendHandles, arrayfun(@(m) sprintf('Mask %d', m), 1:numMasks, ...
    'UniformOutput', false), 'Location', 'southeastoutside', 'FontSize', 8);
hold off;

title('4.1: All Exclusive Masks', 'FontSize', 10);
sgtitle(sprintf('%s - STEP 4.1: Texture Features', baseName), 'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_1_features.png');
end