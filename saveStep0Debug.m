function saveStep0Debug(Irgb, I_cropped, H, W, h_valid, h_roi, target_x, target_y, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 1400, 500);
subplot(1,4,1); imshow(Irgb);
title(sprintf('Original Image\n%d x %d', H, W), 'FontSize', 10);
subplot(1,4,2); imshow(Irgb); hold on;
rectangle('Position', [1, h_valid, W-1, h_roi], 'EdgeColor', 'r', 'LineWidth', 2);
line([1 W], [h_valid h_valid], 'Color', 'b', 'LineStyle', '--', 'LineWidth', 2); hold off;
title(sprintf('ROI Excluded\nBottom %.0f%%', (h_roi/H)*100), 'FontSize', 10);
subplot(1,4,3); imshow(I_cropped); hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 30, 'LineWidth', 4); hold off;
title(sprintf('Cropped + Target\n(%d, %d)', target_x, target_y), 'FontSize', 10);
subplot(1,4,4); imshow(I_cropped); hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 30, 'LineWidth', 4);
line([target_x-50 target_x+50], [target_y target_y], 'Color', 'r', 'LineWidth', 1);
line([target_x target_x], [target_y-50 target_y+50], 'Color', 'r', 'LineWidth', 1); hold off;
title('Center Crosshairs', 'FontSize', 10);
sgtitle(sprintf('%s - STEP 0: Input Preparation', baseName), 'Interpreter', 'none', 'FontSize', 12);
saveFig(fig, showFigures, debugFolder, baseName, '_step0_input.png');
end