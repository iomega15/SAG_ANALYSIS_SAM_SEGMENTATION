function saveStep4_5Debug(I_cropped, allMasksExclusive, lumen_candidates, removed_outside_anchor, anchor_top_Y, anchor_bot_Y, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 1000, 400);
numMasks = size(allMasksExclusive, 1);
colors   = lines(numMasks);

subplot(1,2,1);
overlay = zeros(size(I_cropped,1), size(I_cropped,2), 3);
for m = removed_outside_anchor
    thisMask = squeeze(allMasksExclusive(m,:,:));
    overlay(:,:,1) = overlay(:,:,1) + double(thisMask);  % solid red
end
imshow(overlay); hold on;
line([1 size(I_cropped,2)],[anchor_top_Y anchor_top_Y],'Color','y','LineWidth',2);
line([1 size(I_cropped,2)],[anchor_bot_Y anchor_bot_Y],'Color','y','LineWidth',2); hold off;
title(sprintf('4.5: Outside-anchor removed (red)\n%d masks, TopY=%d BotY=%d', ...
    numel(removed_outside_anchor), anchor_top_Y, anchor_bot_Y),'FontSize',10);

subplot(1,2,2);
overlay2 = zeros(size(I_cropped,1), size(I_cropped,2), 3);
for m = lumen_candidates
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = overlay2(:,:,c);
        ch(thisMask) = colors(m,c);
        overlay2(:,:,c) = ch;
    end
end
imshow(overlay2); hold on;
line([1 size(I_cropped,2)],[anchor_top_Y anchor_top_Y],'Color','y','LineWidth',2);
line([1 size(I_cropped,2)],[anchor_bot_Y anchor_bot_Y],'Color','y','LineWidth',2); hold off;
title(sprintf('4.5: Remaining candidates\n%d masks', numel(lumen_candidates)),'FontSize',10);

sgtitle(sprintf('%s - STEP 4.5: Outside-Anchor Elimination', baseName),'Interpreter','none','FontSize',12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_5_outsideanchor.png');
end