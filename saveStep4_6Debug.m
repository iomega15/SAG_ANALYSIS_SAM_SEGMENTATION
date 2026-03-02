function saveStep4_6Debug(I_cropped, allMasksExclusive, lumen_candidates, ...
    candidate_polarity, candidate_scores, imfill_cache, ...
    anchor_score, diff_gray_full, diff_inv_full, debugFolder, baseName, showFigures)

fig = newFig(showFigures, 1600, 500);
numMasks = size(allMasksExclusive, 1);
colors   = lines(numMasks);

% --- Panel 1: imfill scores per candidate vs anchor baseline ---
subplot(1,4,1);
if isempty(lumen_candidates)
    axis off;
    text(0.5, 0.5, 'No candidates', 'HorizontalAlignment', 'center', 'FontSize', 12);
else
    gray_scores = zeros(numel(lumen_candidates), 1);
    inv_scores  = zeros(numel(lumen_candidates), 1);
    for i = 1:numel(lumen_candidates)
        m = lumen_candidates(i);
        gray_scores(i) = imfill_cache(m).score_gray;
        inv_scores(i)  = imfill_cache(m).score_inv;
    end
    hold on;
    h1 = bar(lumen_candidates - 0.2, gray_scores, 0.35, 'b');
    h2 = bar(lumen_candidates + 0.2, inv_scores,  0.35, 'r');
    yl = yline(anchor_score, 'k--', 'LineWidth', 1.5, 'LabelHorizontalAlignment', 'left');
    yl.HandleVisibility = 'off';
    hold off;
    legend([h1 h2], {'gray','inv'}, 'Location', 'northeast');
    xlabel('Mask'); ylabel('Mean imfill response (px intensity)');
end
title(sprintf('4.6: imfill scores\nanchor baseline=%.1f', anchor_score),'FontSize',10);

% --- Panel 2: diff_gray image ---
subplot(1,4,2);
imshow(diff_gray_full, []); colorbar;
title('4.6: diff\_gray','FontSize',10);

% --- Panel 3: diff_inv image ---
subplot(1,4,3);
imshow(diff_inv_full, []); colorbar;
title('4.6: diff\_inv','FontSize',10);

% --- Panel 4: winning candidates overlaid ---
subplot(1,4,4);
overlay = zeros(size(I_cropped,1), size(I_cropped,2), 3);
for i = 1:numel(lumen_candidates)
    m        = lumen_candidates(i);
    thisMask = squeeze(allMasksExclusive(m,:,:));
    for c = 1:3
        ch = overlay(:,:,c);
        ch(thisMask) = colors(m,c);
        overlay(:,:,c) = ch;
    end
end
imshow(overlay);
candStr = '';
for i = 1:numel(lumen_candidates)
    candStr = [candStr sprintf('Mask %d: %s (%.1f)\n', ...
        lumen_candidates(i), candidate_polarity{i}, candidate_scores(i))]; %#ok<AGROW>
end
if isempty(candStr), candStr = 'None'; end
title(sprintf('4.6: Candidates (score > anchor)\n%s', strtrim(candStr)),'FontSize',9);

sgtitle(sprintf('%s - STEP 4.6: imfill Candidate Detection', baseName),'Interpreter','none','FontSize',12);
saveFig(fig, showFigures, debugFolder, baseName, '_step4_6_imfill.png');
end