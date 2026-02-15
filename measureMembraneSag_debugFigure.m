function fig = measureMembraneSag_debugFigure(BW, sagMetrics, fileName)
% Generate debug figure for sag analysis (without displaying)
% Returns figure handle for saving

    fig = figure('Position', [50 50 1500 700], 'Visible', 'off');
    
    % Get profiles from sagMetrics
    p = sagMetrics.profiles;
    topSmooth = p.topSmooth;
    bottomSmooth = p.bottomSmooth;
    topFitted = p.topFitted;
    baselineIdeal = p.baselineIdeal;
    xRange = p.xCoords;
    bottomFloor_Y = p.bottomFloor_Y;
    idealTop_Y = p.idealTop_Y;
    leftCornerIdx = p.leftCornerIdx;
    rightCornerIdx = p.rightCornerIdx;
    
    % Bounding box
    rp = regionprops(BW, 'BoundingBox');
    [~, k] = max(cellfun(@(x) x(3)*x(4), {rp.BoundingBox}));
    bb = rp(k).BoundingBox;
    bbLeft = round(bb(1));
    bbTop = round(bb(2));
    bbWidth = round(bb(3));
    bbHeight = round(bb(4));
    bbRight = bbLeft + bbWidth - 1;
    bbBottom = bbTop + bbHeight - 1;
    
    [nRows, nCols] = size(BW);
    
    % Zoom region
    pad = 30;
    zoomLeft = max(1, bbLeft - pad);
    zoomRight = min(nCols, bbRight + pad);
    zoomTop = max(1, bbTop - pad);
    zoomBottom = min(nRows, bbBottom + pad);
    
    BWcropped = BW(zoomTop:zoomBottom, zoomLeft:zoomRight);
    offsetX = zoomLeft - 1;
    offsetY = zoomTop - 1;
    
    leftCornerX = sagMetrics.leftCornerX;
    rightCornerX = sagMetrics.rightCornerX;
    leftCornerY = sagMetrics.leftCornerY;
    rightCornerY = sagMetrics.rightCornerY;
    
    % Parabola vertex
    xVertexIdx = round((leftCornerIdx + rightCornerIdx) / 2);  % Approximate
    yVertex = idealTop_Y + sagMetrics.sagDepth_px;
    xVertexInImage = xRange(1) + xVertexIdx - 1;
    
    % ===== SUBPLOT 1: Zoomed mask =====
    subplot(1, 2, 1);
    imshow(BWcropped); hold on;
    
    % Bounding box
    rectangle('Position', [bbLeft-offsetX, bbTop-offsetY, bbWidth, bbHeight], ...
              'EdgeColor', 'y', 'LineWidth', 2, 'LineStyle', '--');
    
    % Top edge
    plot(xRange - offsetX, topSmooth - offsetY, 'b-', 'LineWidth', 2);
    
    % Baseline
    plot(xRange - offsetX, baselineIdeal - offsetY, 'g-', 'LineWidth', 2);
    
    % Bottom edge between corners
    xBetween = xRange(leftCornerIdx:rightCornerIdx);
    bottomBetween = bottomSmooth(leftCornerIdx:rightCornerIdx);
    plot(xBetween - offsetX, bottomBetween - offsetY, 'c-', 'LineWidth', 1.5);
    
    % Bottom floor line
    plot([xRange(leftCornerIdx) xRange(rightCornerIdx)] - offsetX, ...
         [bottomFloor_Y bottomFloor_Y] - offsetY, 'c--', 'LineWidth', 2);
    
    % Corners
    plot(leftCornerX - offsetX, leftCornerY - offsetY, 'go', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    plot(rightCornerX - offsetX, rightCornerY - offsetY, 'go', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    
    % Vertex
    plot(xVertexInImage - offsetX, yVertex - offsetY, 'r^', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'r');
    
    % Sag depth line
    plot([xVertexInImage xVertexInImage] - offsetX, [idealTop_Y yVertex] - offsetY, 'm-', 'LineWidth', 3);
    
    % Sag area fill
    xFill = xRange(leftCornerIdx:rightCornerIdx) - offsetX;
    yTop = topSmooth(leftCornerIdx:rightCornerIdx) - offsetY;
    yBase = baselineIdeal(leftCornerIdx:rightCornerIdx) - offsetY;
    fill([xFill fliplr(xFill)], [yTop fliplr(yBase)], 'r', 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    
    title(sprintf('Sag: %.1f px (%.3f mm)\nH: %.1f%% | W: %.1f%% | Area: %.1f%%', ...
                  sagMetrics.sagDepth_px, sagMetrics.sagDepth_mm, ...
                  sagMetrics.heightPct_ofTheoretical, sagMetrics.widthPct_ofTheoretical, ...
                  sagMetrics.areaPct_ofTheoretical), 'FontSize', 10);
    axis tight;
    hold off;
    
    % ===== SUBPLOT 2: Profile plot =====
    subplot(1, 2, 2);
    xCoords = 1:length(topSmooth);
    
    plot(xCoords, topSmooth, 'b-', 'LineWidth', 2); hold on;
    plot(xCoords, baselineIdeal, 'g-', 'LineWidth', 2);
    
    if ~isempty(topFitted) && ~all(isnan(topFitted))
        plot(xCoords, topFitted, 'r:', 'LineWidth', 2);
    end
    
    plot(leftCornerIdx:rightCornerIdx, bottomSmooth(leftCornerIdx:rightCornerIdx), 'c-', 'LineWidth', 1.5);
    plot([leftCornerIdx rightCornerIdx], [bottomFloor_Y bottomFloor_Y], 'c--', 'LineWidth', 2);
    
    plot(leftCornerIdx, leftCornerY, 'go', 'MarkerSize', 10, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    plot(rightCornerIdx, rightCornerY, 'go', 'MarkerSize', 10, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    
    plot(xVertexIdx, yVertex, 'r^', 'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'r');
    plot([xVertexIdx xVertexIdx], [idealTop_Y yVertex], 'm-', 'LineWidth', 3);
    
    % Sag area fill
    xFillPlot = leftCornerIdx:rightCornerIdx;
    fill([xFillPlot fliplr(xFillPlot)], [topSmooth(xFillPlot) fliplr(baselineIdeal(xFillPlot))], ...
         'r', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    
    set(gca, 'YDir', 'reverse');
    xlabel('Position (px)');
    ylabel('Y (px)');
    grid on;
    
    title(sprintf('Profile (R² = %.3f)', sagMetrics.parabolaR2), 'FontSize', 10);
    hold off;
    
    % Main title
    sgtitle(sprintf(['%s\n' ...
        'Sag: %.1f px = %.3f mm | %.1f%% of H_{meas} | %.1f%% of H_{theo} | %.1f%% of width span\n' ...
        'Height: meas=%.0fpx, theo=%.0fpx (%.1f%%) | Width: meas=%.0fpx, theo=%.0fpx (%.1f%%)'], ...
        fileName, ...
        sagMetrics.sagDepth_px, sagMetrics.sagDepth_mm, ...
        sagMetrics.sagPct_ofMeasuredHeight, sagMetrics.sagPct_ofTheoreticalHeight, sagMetrics.sagPct_ofWidthSpan, ...
        sagMetrics.measuredHeight_px, sagMetrics.theoreticalHeight_px, sagMetrics.heightPct_ofTheoretical, ...
        sagMetrics.measuredWidth_px, sagMetrics.theoreticalWidth_px, sagMetrics.widthPct_ofTheoretical), ...
        'FontSize', 9, 'FontWeight', 'bold', 'Interpreter', 'none');
end