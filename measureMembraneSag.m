function sagMetrics = measureMembraneSag(BW, mmPerPx, debugPlot, H_layers, Width_printer_pixels, layerHeight_mm, pixelWidth_mm)
% MEASUREMEMBRANESAG Quantify membrane sag using two baseline methods:
%   1. Corner-based: min(leftCornerY, rightCornerY) from smoothed top edge
%   2. BoundingBox-based: top of bounding box (bbTop)

    % Defaults
    if nargin < 3 || isempty(debugPlot), debugPlot = false; end
    if nargin < 4, H_layers = NaN; end
    if nargin < 5, Width_printer_pixels = NaN; end
    if nargin < 6 || isempty(layerHeight_mm), layerHeight_mm = 0.05; end
    if nargin < 7 || isempty(pixelWidth_mm), pixelWidth_mm = 0.032; end
    
    sagMetrics = initializeSagMetrics();
    
    %% 1. GET BOUNDING BOX (The Source of Truth for Corners)
    rp = regionprops(BW, 'Area', 'BoundingBox', 'ConvexArea');
    if isempty(rp), warning('No regions found in mask'); return; end
    [~, k] = max([rp.Area]);
    bb = rp(k).BoundingBox;
    
    bbLeft = round(bb(1));
    bbTop = round(bb(2));
    bbWidth = round(bb(3));
    bbHeight = round(bb(4));
    bbRight = bbLeft + bbWidth - 1;
    bbBottom = bbTop + bbHeight - 1;
    
    actualArea_px2 = rp(k).Area;
    bbArea_px2 = bb(3) * bb(4);
    convexArea_px2 = rp(k).ConvexArea;
    
    %% 2. EXTRACT EDGE PROFILES
    [nRows, nCols] = size(BW);
    topEdge = nan(1, nCols);
    bottomEdge = nan(1, nCols);
    
    for col = 1:nCols
        rows = find(BW(:, col));
        if ~isempty(rows)
            topEdge(col) = min(rows);
            bottomEdge(col) = max(rows);
        end
    end
    
    validCols = find(~isnan(topEdge));
    if numel(validCols) < 10, warning('Lumen too small'); return; end
    
    xMin = validCols(1);
    xMax = validCols(end);
    xRange = xMin:xMax;
    
    topProfile = fillmissing(topEdge(xRange), 'linear');
    bottomProfile = fillmissing(bottomEdge(xRange), 'linear');
    
    %% 3. SMOOTH
    windowSize = max(5, round(length(topProfile) / 30));
    topSmooth = movmedian(topProfile, windowSize);
    bottomSmooth = movmedian(bottomProfile, windowSize);
    
    %% 4. DEFINE CORNERS (Using Bounding Box Limits)
    leftCornerIdx = max(1, bbLeft - xRange(1) + 1);
    rightCornerIdx = min(length(topSmooth), bbRight - xRange(1) + 1);
    
    leftCornerY = topSmooth(leftCornerIdx);
    rightCornerY = topSmooth(rightCornerIdx);
    leftCornerX = xRange(leftCornerIdx);
    rightCornerX = xRange(rightCornerIdx);
    
    roofRegion = topSmooth(leftCornerIdx:rightCornerIdx);
    if (max(roofRegion) - min(roofRegion)) / length(roofRegion) < 0.1
        cornerType = 'plateau';
    else
        cornerType = 'peaked';
    end
    
    %% 5. BOTTOM FLOOR
    bottomBetweenCorners = bottomSmooth(leftCornerIdx:rightCornerIdx);
    bottomFloor_Y = median(bottomBetweenCorners);
    
    %% 6. FIT PARABOLA
    xFit = leftCornerIdx:rightCornerIdx;
    yFit = topSmooth(xFit);
    xCentered = xFit - mean(xFit);
    
    try
        p = polyfit(xCentered, yFit, 2);
        xVertexCentered = -p(2) / (2 * p(1));
        yVertex = polyval(p, xVertexCentered);
        
        xVertexIdx = round(xVertexCentered + mean(xFit));
        xVertexIdx = max(1, min(length(topSmooth), xVertexIdx));
        xVertexInImage = xRange(1) + xVertexIdx - 1;
        
        topFitted = polyval(p, (1:length(topSmooth)) - mean(xFit));
        R2 = 1 - sum((yFit - polyval(p, xCentered)).^2) / sum((yFit - mean(yFit)).^2);
        parabolaFitValid = true;
    catch
        parabolaFitValid = false; R2 = NaN; topFitted = nan(size(topSmooth));
        yVertex = NaN; xVertexIdx = NaN; xVertexInImage = NaN;
    end
    
    %% 7. BASELINES (Two Methods)
    % Method 1: Corner-based (original) - uses higher of two corners
    idealTop_Y_corner = min(leftCornerY, rightCornerY);
    baselineCorner = ones(1, length(topSmooth)) * idealTop_Y_corner;
    
    % Method 2: BoundingBox-based (new) - uses absolute top of bounding box
    idealTop_Y_bb = bbTop;
    baselineBB = ones(1, length(topSmooth)) * idealTop_Y_bb;
    
    %% 8. THEORETICAL & MEASURED DIMENSIONS
    theoreticalHeight_px = (H_layers * layerHeight_mm) / mmPerPx;
    theoreticalWidth_px = (Width_printer_pixels * pixelWidth_mm) / mmPerPx;
    measuredHeight_px = bbHeight;
    measuredHeight_mm = bbHeight * mmPerPx;
    measuredWidth_px = bbWidth;
    measuredWidth_mm = bbWidth * mmPerPx;
    spanWidth_px = rightCornerIdx - leftCornerIdx;
    
    %% 9. SAG DEPTH & AREA (Both Methods)
    isVertexBetween = (xVertexIdx >= leftCornerIdx) && (xVertexIdx <= rightCornerIdx);
    isVertexLowerLeft = (yVertex > leftCornerY);
    isVertexLowerRight = (yVertex > rightCornerY);
    
    % === METHOD 1: CORNER-BASED SAG (Original) ===
    if parabolaFitValid
        sagDepth_corner_px = yVertex - idealTop_Y_corner;
    else
        sagDepth_corner_px = max(topSmooth(leftCornerIdx:rightCornerIdx)) - idealTop_Y_corner;
    end
    sagArea_corner_px2 = trapz(max(0, topSmooth(leftCornerIdx:rightCornerIdx) - baselineCorner(leftCornerIdx:rightCornerIdx)));
    
    % === METHOD 2: BOUNDING BOX-BASED SAG (New) ===
    if parabolaFitValid
        sagDepth_bb_px = yVertex - idealTop_Y_bb;
    else
        sagDepth_bb_px = max(topSmooth(leftCornerIdx:rightCornerIdx)) - idealTop_Y_bb;
    end
    sagArea_bb_px2 = trapz(max(0, topSmooth(leftCornerIdx:rightCornerIdx) - baselineBB(leftCornerIdx:rightCornerIdx)));
    
    %% 10. WALL TILT
    leftWallInward_px = leftCornerX - bbLeft;
    rightWallInward_px = bbRight - rightCornerX;
    
    leftWallTiltAngle_deg = atand(leftWallInward_px / max(1, measuredHeight_px));
    rightWallTiltAngle_deg = atand(rightWallInward_px / max(1, measuredHeight_px));
    
    %% 11. PACK OUTPUT
    sagMetrics.valid = true;
    sagMetrics.parabolaR2 = R2;
    
    % --- Corner-Based Sag (Original Method) ---
    sagMetrics.sagDepth_px = sagDepth_corner_px;
    sagMetrics.sagDepth_mm = sagDepth_corner_px * mmPerPx;
    sagMetrics.sagArea_px2 = sagArea_corner_px2;
    sagMetrics.sagArea_mm2 = sagArea_corner_px2 * (mmPerPx^2);
    sagMetrics.sagPct_ofMeasuredHeight = (sagDepth_corner_px / measuredHeight_px) * 100;
    sagMetrics.sagPct_ofTheoreticalHeight = (sagDepth_corner_px / theoreticalHeight_px) * 100;
    sagMetrics.sagPct_ofWidthSpan = (sagDepth_corner_px / max(1, spanWidth_px)) * 100;
    
    % --- BoundingBox-Based Sag (New Method) ---
    sagMetrics.sagDepthBB_px = sagDepth_bb_px;
    sagMetrics.sagDepthBB_mm = sagDepth_bb_px * mmPerPx;
    sagMetrics.sagAreaBB_px2 = sagArea_bb_px2;
    sagMetrics.sagAreaBB_mm2 = sagArea_bb_px2 * (mmPerPx^2);
    sagMetrics.sagBB_Pct_ofMeasuredHeight = (sagDepth_bb_px / measuredHeight_px) * 100;
    sagMetrics.sagBB_Pct_ofTheoreticalHeight = (sagDepth_bb_px / theoreticalHeight_px) * 100;
    sagMetrics.sagBB_Pct_ofWidthSpan = (sagDepth_bb_px / max(1, spanWidth_px)) * 100;
    
    % --- Baseline Reference Values ---
    sagMetrics.baselineCorner_Y = idealTop_Y_corner;
    sagMetrics.baselineBB_Y = idealTop_Y_bb;
    sagMetrics.baselineDiff_px = idealTop_Y_corner - idealTop_Y_bb;  % How much lower corners are vs BB top
    sagMetrics.baselineDiff_mm = (idealTop_Y_corner - idealTop_Y_bb) * mmPerPx;
    
    % Height measurements
    sagMetrics.measuredHeight_px = measuredHeight_px;
    sagMetrics.measuredHeight_mm = measuredHeight_mm;
    sagMetrics.theoreticalHeight_px = theoreticalHeight_px;
    sagMetrics.theoreticalHeight_mm = theoreticalHeight_px * mmPerPx;
    sagMetrics.heightPct_ofTheoretical = (measuredHeight_px / theoreticalHeight_px) * 100;
    
    % Width measurements
    sagMetrics.measuredWidth_px = measuredWidth_px;
    sagMetrics.measuredWidth_mm = measuredWidth_mm;
    sagMetrics.theoreticalWidth_px = theoreticalWidth_px;
    sagMetrics.theoreticalWidth_mm = theoreticalWidth_px * mmPerPx;
    sagMetrics.widthPct_ofTheoretical = (measuredWidth_px / theoreticalWidth_px) * 100;
    
    % Span measurements
    sagMetrics.spanWidth_px = spanWidth_px;
    sagMetrics.spanWidth_mm = spanWidth_px * mmPerPx;
    
    % Wall tilt
    sagMetrics.leftWallTiltAngle_deg = leftWallTiltAngle_deg;
    sagMetrics.rightWallTiltAngle_deg = rightWallTiltAngle_deg;
    sagMetrics.avgWallTiltAngle_deg = mean([leftWallTiltAngle_deg, rightWallTiltAngle_deg], 'omitnan');
    sagMetrics.totalWallInward_mm = (leftWallInward_px + rightWallInward_px) * mmPerPx;
    
    % Area metrics
    sagMetrics.actualArea_mm2 = actualArea_px2 * (mmPerPx^2);
    sagMetrics.theoreticalArea_mm2 = (theoreticalHeight_px * theoreticalWidth_px) * (mmPerPx^2);
    sagMetrics.areaPct_ofTheoretical = (actualArea_px2 / (theoreticalHeight_px * theoreticalWidth_px)) * 100;
    sagMetrics.convexityRatio = actualArea_px2 / convexArea_px2;
    
    % Corner information
    sagMetrics.leftCornerX = leftCornerX;
    sagMetrics.rightCornerX = rightCornerX;
    sagMetrics.leftCornerY = leftCornerY;
    sagMetrics.rightCornerY = rightCornerY;
    sagMetrics.cornerType = cornerType;
    
    % Validation flags
    sagMetrics.isVertexBetween = isVertexBetween;
    sagMetrics.isVertexLowerLeft = isVertexLowerLeft;
    sagMetrics.isVertexLowerRight = isVertexLowerRight;
    
    % Profile data for debug figures
    sagMetrics.profiles.topSmooth = topSmooth;
    sagMetrics.profiles.bottomSmooth = bottomSmooth;
    sagMetrics.profiles.topFitted = topFitted;
    sagMetrics.profiles.baselineCorner = baselineCorner;
    sagMetrics.profiles.baselineBB = baselineBB;
    sagMetrics.profiles.xCoords = xRange;
    sagMetrics.profiles.bottomFloor_Y = bottomFloor_Y;
    sagMetrics.profiles.idealTop_Y = idealTop_Y_corner;  % Keep for backward compatibility
    sagMetrics.profiles.idealTop_Y_corner = idealTop_Y_corner;
    sagMetrics.profiles.idealTop_Y_bb = idealTop_Y_bb;
    sagMetrics.profiles.leftCornerIdx = leftCornerIdx;
    sagMetrics.profiles.rightCornerIdx = rightCornerIdx;

    %% 12. DEBUG VISUALIZATION
    if debugPlot
        plotSagDebug(BW, sagMetrics, bbLeft, bbTop, bbRight, bbBottom, bbWidth, bbHeight, ...
                     xRange, topSmooth, bottomSmooth, topFitted, baselineCorner, baselineBB, ...
                     leftCornerIdx, rightCornerIdx, leftCornerX, rightCornerX, ...
                     leftCornerY, rightCornerY, xVertexInImage, xVertexIdx, yVertex, ...
                     idealTop_Y_corner, idealTop_Y_bb, bottomFloor_Y, parabolaFitValid, ...
                     sagDepth_corner_px, sagDepth_bb_px, ...
                     sagMetrics.sagDepth_mm, sagMetrics.sagDepthBB_mm, ...
                     measuredHeight_px, theoreticalHeight_px, sagMetrics.heightPct_ofTheoretical, ...
                     measuredWidth_px, theoreticalWidth_px, sagMetrics.widthPct_ofTheoretical, ...
                     spanWidth_px, R2, sagMetrics.sagPct_ofMeasuredHeight, ...
                     sagMetrics.sagPct_ofTheoreticalHeight, sagMetrics.sagPct_ofWidthSpan, ...
                     sagMetrics.sagBB_Pct_ofMeasuredHeight, sagMetrics.areaPct_ofTheoretical);
    end
end

function sagMetrics = initializeSagMetrics()
    sagMetrics.valid = false;
    sagMetrics.parabolaR2 = NaN;
    
    % Corner-based sag measurements (original)
    sagMetrics.sagDepth_px = NaN;
    sagMetrics.sagDepth_mm = NaN;
    sagMetrics.sagArea_px2 = NaN;
    sagMetrics.sagArea_mm2 = NaN;
    sagMetrics.sagPct_ofMeasuredHeight = NaN;
    sagMetrics.sagPct_ofTheoreticalHeight = NaN;
    sagMetrics.sagPct_ofWidthSpan = NaN;
    
    % BoundingBox-based sag measurements (new)
    sagMetrics.sagDepthBB_px = NaN;
    sagMetrics.sagDepthBB_mm = NaN;
    sagMetrics.sagAreaBB_px2 = NaN;
    sagMetrics.sagAreaBB_mm2 = NaN;
    sagMetrics.sagBB_Pct_ofMeasuredHeight = NaN;
    sagMetrics.sagBB_Pct_ofTheoreticalHeight = NaN;
    sagMetrics.sagBB_Pct_ofWidthSpan = NaN;
    
    % Baseline reference values
    sagMetrics.baselineCorner_Y = NaN;
    sagMetrics.baselineBB_Y = NaN;
    sagMetrics.baselineDiff_px = NaN;
    sagMetrics.baselineDiff_mm = NaN;
    
    % Height measurements
    sagMetrics.measuredHeight_px = NaN;
    sagMetrics.measuredHeight_mm = NaN;
    sagMetrics.theoreticalHeight_px = NaN;
    sagMetrics.theoreticalHeight_mm = NaN;
    sagMetrics.heightPct_ofTheoretical = NaN;
    
    % Width measurements
    sagMetrics.measuredWidth_px = NaN;
    sagMetrics.measuredWidth_mm = NaN;
    sagMetrics.theoreticalWidth_px = NaN;
    sagMetrics.theoreticalWidth_mm = NaN;
    sagMetrics.widthPct_ofTheoretical = NaN;
    
    % Span measurements
    sagMetrics.spanWidth_px = NaN;
    sagMetrics.spanWidth_mm = NaN;
    
    % Wall tilt
    sagMetrics.leftWallTiltAngle_deg = NaN;
    sagMetrics.rightWallTiltAngle_deg = NaN;
    sagMetrics.avgWallTiltAngle_deg = NaN;
    sagMetrics.totalWallInward_mm = NaN;
    
    % Area metrics
    sagMetrics.actualArea_mm2 = NaN;
    sagMetrics.theoreticalArea_mm2 = NaN;
    sagMetrics.areaPct_ofTheoretical = NaN;
    sagMetrics.convexityRatio = NaN;
    
    % Corner information
    sagMetrics.leftCornerX = NaN;
    sagMetrics.rightCornerX = NaN;
    sagMetrics.leftCornerY = NaN;
    sagMetrics.rightCornerY = NaN;
    sagMetrics.cornerType = '';
    
    % Validation flags
    sagMetrics.isVertexBetween = false;
    sagMetrics.isVertexLowerLeft = false;
    sagMetrics.isVertexLowerRight = false;
    
    % Profile data
    sagMetrics.profiles = struct();
end

function plotSagDebug(BW, sagMetrics, bbLeft, bbTop, bbRight, bbBottom, bbWidth, bbHeight, ...
                      xRange, topSmooth, bottomSmooth, topFitted, baselineCorner, baselineBB, ...
                      leftCornerIdx, rightCornerIdx, leftCornerX, rightCornerX, ...
                      leftCornerY, rightCornerY, xVertexInImage, xVertexIdx, yVertex, ...
                      idealTop_Y_corner, idealTop_Y_bb, bottomFloor_Y, parabolaFitValid, ...
                      sagDepth_corner_px, sagDepth_bb_px, ...
                      sagDepth_corner_mm, sagDepth_bb_mm, ...
                      measHeight_px, theoHeight_px, heightPct, ...
                      measWidth_px, theoWidth_px, widthPct, ...
                      spanWidth_px, R2, sagPct_H_corner, ...
                      sagPct_Htheo_corner, sagPct_span_corner, ...
                      sagPct_H_bb, areaPct)
    
    [nRows, nCols] = size(BW);
    figure('Position', [50 50 1600 700]);
    
    pad = 30;
    zoomLeft = max(1, bbLeft - pad); zoomRight = min(nCols, bbRight + pad);
    zoomTop = max(1, bbTop - pad); zoomBottom = min(nRows, bbBottom + pad);
    
    BWcropped = BW(zoomTop:zoomBottom, zoomLeft:zoomRight);
    offsetX = zoomLeft - 1; offsetY = zoomTop - 1;
    
    %% Panel 1: Mask with both baselines
    subplot(1, 2, 1);
    imshow(BWcropped); hold on;
    
    % Bounding box
    rectangle('Position', [bbLeft-offsetX, bbTop-offsetY, bbWidth, bbHeight], ...
              'EdgeColor', 'y', 'LineWidth', 2, 'LineStyle', '--');
    
    % Top edge profile
    plot(xRange - offsetX, topSmooth - offsetY, 'b-', 'LineWidth', 2);
    
    % Corner-based baseline (green)
    plot(xRange - offsetX, baselineCorner - offsetY, 'g-', 'LineWidth', 2);
    
    % BB-based baseline (cyan)
    plot(xRange - offsetX, baselineBB - offsetY, 'c-', 'LineWidth', 2);
    
    % Bottom edge
    xBetween = xRange(leftCornerIdx:rightCornerIdx);
    bottomBetween = bottomSmooth(leftCornerIdx:rightCornerIdx);
    plot(xBetween - offsetX, bottomBetween - offsetY, 'm-', 'LineWidth', 1.5);
    plot([xRange(leftCornerIdx) xRange(rightCornerIdx)] - offsetX, ...
         [bottomFloor_Y bottomFloor_Y] - offsetY, 'm--', 'LineWidth', 2);
    
    % Corner markers
    plot(leftCornerX - offsetX, leftCornerY - offsetY, 'go', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    plot(rightCornerX - offsetX, rightCornerY - offsetY, 'go', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    
    % Vertex and sag lines
    if parabolaFitValid && ~isnan(yVertex)
        plot(xVertexInImage - offsetX, yVertex - offsetY, 'r^', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'r');
        % Sag line to corner baseline (green)
        plot([xVertexInImage xVertexInImage] - offsetX, [idealTop_Y_corner yVertex] - offsetY, 'g-', 'LineWidth', 3);
        % Sag line to BB baseline (cyan)
        plot([xVertexInImage-3 xVertexInImage-3] - offsetX, [idealTop_Y_bb yVertex] - offsetY, 'c-', 'LineWidth', 3);
    end
    
    % Fill sag area (corner-based)
    xFill = xRange(leftCornerIdx:rightCornerIdx) - offsetX;
    yTop = topSmooth(leftCornerIdx:rightCornerIdx) - offsetY;
    yBaseCorner = baselineCorner(leftCornerIdx:rightCornerIdx) - offsetY;
    fill([xFill fliplr(xFill)], [yTop fliplr(yBaseCorner)], 'g', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    
    % Fill sag area (BB-based)
    yBaseBB = baselineBB(leftCornerIdx:rightCornerIdx) - offsetY;
    fill([xFill fliplr(xFill)], [yBaseCorner fliplr(yBaseBB)], 'c', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    
    legend({'BoundingBox', 'Top Edge', 'Baseline (Corner)', 'Baseline (BB)', ...
            'Bottom Edge', 'Bottom Floor', 'Corners', '', 'Vertex', ...
            'Sag (Corner)', 'Sag (BB)'}, ...
           'Location', 'southeast', 'FontSize', 7);
    
    title(sprintf('Corner Sag: %.1f px (%.3f mm) = %.1f%% H\nBB Sag: %.1f px (%.3f mm) = %.1f%% H', ...
                  sagDepth_corner_px, sagDepth_corner_mm, sagPct_H_corner, ...
                  sagDepth_bb_px, sagDepth_bb_mm, sagPct_H_bb), 'FontSize', 10);
    axis tight; hold off;
    
    %% Panel 2: Profile plot with both baselines
    subplot(1, 2, 2);
    xCoords = 1:length(topSmooth);
    
    plot(xCoords, topSmooth, 'b-', 'LineWidth', 2); hold on;
    plot(xCoords, baselineCorner, 'g-', 'LineWidth', 2);
    plot(xCoords, baselineBB, 'c-', 'LineWidth', 2);
    if parabolaFitValid, plot(xCoords, topFitted, 'r:', 'LineWidth', 2); end
    
    % Bottom edge
    plot(leftCornerIdx:rightCornerIdx, bottomSmooth(leftCornerIdx:rightCornerIdx), 'm-', 'LineWidth', 1.5);
    plot([leftCornerIdx rightCornerIdx], [bottomFloor_Y bottomFloor_Y], 'm--', 'LineWidth', 2);
    
    % Corners
    plot(leftCornerIdx, leftCornerY, 'go', 'MarkerSize', 10, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    plot(rightCornerIdx, rightCornerY, 'go', 'MarkerSize', 10, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    
    % Vertex
    if parabolaFitValid && ~isnan(yVertex)
        plot(xVertexIdx, yVertex, 'r^', 'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'r');
        plot([xVertexIdx xVertexIdx], [idealTop_Y_corner yVertex], 'g-', 'LineWidth', 3);
        plot([xVertexIdx+2 xVertexIdx+2], [idealTop_Y_bb yVertex], 'c-', 'LineWidth', 3);
    end
    
    % Height reference line
    midIdx = round((leftCornerIdx + rightCornerIdx) / 2);
    plot([midIdx midIdx], [idealTop_Y_bb bottomFloor_Y], 'k-', 'LineWidth', 2);
    
    % Fill areas
    xFillPlot = leftCornerIdx:rightCornerIdx;
    fill([xFillPlot fliplr(xFillPlot)], [topSmooth(xFillPlot) fliplr(baselineCorner(xFillPlot))], ...
         'g', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    fill([xFillPlot fliplr(xFillPlot)], [baselineCorner(xFillPlot) fliplr(baselineBB(xFillPlot))], ...
         'c', 'FaceAlpha', 0.15, 'EdgeColor', 'none');
    
    set(gca, 'YDir', 'reverse');
    xlabel('Position (px)'); ylabel('Y (px)'); grid on;
    legend({'Top edge', 'Baseline (Corner)', 'Baseline (BB)', sprintf('Parabola (R^2=%.3f)', R2), ...
            'Bottom (between)', 'Bottom floor', 'Corners', '', ...
            'Vertex', sprintf('Sag Corner=%.1fpx', sagDepth_corner_px), ...
            sprintf('Sag BB=%.1fpx', sagDepth_bb_px)}, ...
           'Location', 'southeast', 'FontSize', 7);
    title(sprintf('Profile (R^2 = %.3f)', R2), 'FontSize', 10);
    hold off;
    
    sgtitle(sprintf(['SAG ANALYSIS (Two Baselines)\n' ...
        'Corner-based: %.1f px = %.3f mm | %.1f%% of H_{meas} | %.1f%% of H_{theo}\n' ...
        'BB-based: %.1f px = %.3f mm | %.1f%% of H_{meas}\n' ...
        'Baseline Diff: %.1f px | Height: %.0fpx (%.1f%%) | Width: %.0fpx (%.1f%%)'], ...
        sagDepth_corner_px, sagDepth_corner_mm, sagPct_H_corner, sagPct_Htheo_corner, ...
        sagDepth_bb_px, sagDepth_bb_mm, sagPct_H_bb, ...
        idealTop_Y_corner - idealTop_Y_bb, ...
        measHeight_px, heightPct, measWidth_px, widthPct), ...
        'FontSize', 10, 'FontWeight', 'bold');
end