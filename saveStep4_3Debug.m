function saveStep4_3Debug(I_cropped, allMasksExclusive, anchor_mask_indices, anchor_mask, ...
    anchor_top_Y, anchor_bot_Y, textureFeatures, maskAreas, Hc, Wc, debugFolder, baseName, showFigures)

fig = newFig(showFigures, 1200, 450);
numMasks = size(allMasksExclusive, 1);
colors   = lines(numMasks);

subplot(1,3,1);
scores = maskAreas(2:end) .* textureFeatures(2:end);
b = bar(2:numel(maskAreas), scores); b.FaceColor = 'flat';
cdata = colors(2:end,:);
for m = anchor_mask_indices
    if m >= 2
        cdata(m-1,:) = [0.9 0.2 0.2];  % red for all anchor masks
    end
end
b.CData = cdata;
xlabel('Mask Index'); ylabel('Area \times EdgeDensity');
title(sprintf('4.3: Anchor Scores\n(anchor masks=%s, red)', num2str(anchor_mask_indices)),'FontSize',10);

subplot(1,3,2);
overlay2 = zeros(Hc, Wc, 3);
overlay2(:,:,1) = double(anchor_mask);  % joined anchor in solid red
imshow(overlay2); hold on;
line([1 size(I_cropped,2)],[anchor_top_Y anchor_top_Y],'Color','y','LineWidth',2);
line([1 size(I_cropped,2)],[anchor_bot_Y anchor_bot_Y],'Color','y','LineWidth',2); hold off;
title(sprintf('4.3: Anchor (red)\nTop Y=%d  Bot Y=%d (yellow)', anchor_top_Y, anchor_bot_Y),'FontSize',10);

subplot(1,3,3);
overlay = zeros(Hc, Wc, 3);
for m = 1:numMasks
    if ismember(m, anchor_mask_indices); continue; end
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = overlay(:,:,c);
        ch(thisMask) = colors(m,c);
        overlay(:,:,c) = ch;
    end
end
imshow(overlay);
title('4.3: Non-anchor masks','FontSize',10);

sgtitle(sprintf('%s - STEP 4.3: 3D-Printed Anchor', baseName),'Interpreter','none','FontSize',12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_3_anchor.png');
end