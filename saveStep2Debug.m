function saveStep2Debug(I_cropped, BW_raw, BW_cleaned, rp, allAreas, nRegions, keepIdx, removeIdx, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 1600, 600);
subplot(2,3,1);
[L,~] = bwlabel(BW_raw); imshow(label2rgb(L,'jet','k','shuffle')); hold on;
for k=1:nRegions; c=rp(k).Centroid; text(c(1),c(2),sprintf('%d',k),'Color','w','FontSize',10,'FontWeight','bold'); end; hold off;
title(sprintf('All %d Components', nRegions), 'FontSize', 10);
subplot(2,3,2); bar(allAreas); xlabel('Region'); ylabel('Area (px)'); title('Region Areas','FontSize',10);
subplot(2,3,3);
if nRegions > 2
    histogram(log10(allAreas+1),15); xlabel('log_{10}(Area)'); title('Log-Area Distribution','FontSize',10);
else
    text(0.5,0.5,sprintf('Only %d regions\n(no Otsu needed)',nRegions),'HorizontalAlignment','center','FontSize',12); axis off;
end
subplot(2,3,4); imshow(I_cropped); hold on;
for idx=removeIdx; rm=false(size(BW_raw)); rm(rp(idx).PixelIdxList)=true; visboundaries(rm,'Color','r','LineWidth',2); end; hold off;
title(sprintf('REMOVED: %d regions',numel(removeIdx)),'FontSize',10,'Color','r');
subplot(2,3,5); imshow(I_cropped); hold on;
for idx=keepIdx; km=false(size(BW_raw)); km(rp(idx).PixelIdxList)=true; visboundaries(km,'Color','g','LineWidth',2); end; hold off;
title(sprintf('KEPT: %d regions',numel(keepIdx)),'FontSize',10,'Color',[0 0.6 0]);
subplot(2,3,6); imshowpair(BW_raw, BW_cleaned,'montage'); title('Before vs After','FontSize',10);
sgtitle(sprintf('%s - STEP 2: Adaptive Cluster Cleanup', baseName),'Interpreter','none','FontSize',12);
saveFig(fig, showFigures, debugFolder, baseName, '_step2_cleanup.png');
end