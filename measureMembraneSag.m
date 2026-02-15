function sagMetrics = measureMembraneSag(BW, mmPerPx, debugPlot, H_layers, Width_printer_pixels, layerHeight_mm, pixelWidth_mm)
% MEASUREMEMBRANESAG Quantify membrane sag from binary lumen mask
%
% Inputs:
%   BW                    - Binary mask of lumen
%   mmPerPx               - mm per pixel calibration (from microscope)
%   debugPlot             - true/false for visualization
%   H_layers              - Theoretical height in layers (from filename)
%   Width_printer_pixels  - Theoretical width in printer pixels (from filename)
%   layerHeight_mm        - Layer height in mm (default: 0.05)
%   pixelWidth_mm         - Printer XY pixel size in mm (default: 0.032)

    % Defaults
    if nargin < 3 || isempty(debugPlot), debugPlot = false; end
    if nargin < 4, H_layers = NaN; end
    if nargin < 5, Width_printer_pixels = NaN; end
    if nargin < 6 || isempty(layerHeight_mm), layerHeight_mm = 0.05; end
    if nargin < 7 || isempty(pixelWidth_mm), pixelWidth_mm = 0.032; end
    
    % Initialize output with all NaN
    sagMetrics = initializeSagMetrics();
    
    %% 1. GET BOUNDING BOX
    rp = regionprops(BW, 'Area', 'BoundingBox', 'ConvexArea');
    if isempty(rp)
        warning('No regions found in mask');
        return;
    end
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
    if numel(validCols) < 20
        warning('Insufficient lumen pixels detected');
        return;
    end
    
    xMin = validCols(1);
    xMax = validCols(end);
    xRange = xMin:xMax;
    
    topProfile = topEdge(xRange);
    bottomProfile = bottomEdge(xRange);
    
    topProfile = fillmissing(topProfile, 'linear');
    bottomProfile = fillmissing(bottomProfile, 'linear');
    
    %% 3. SMOOTH
    windowSize = max(5, round(length(topProfile) / 30));
    topSmooth = movmedian(topProfile, windowSize);
    bottomSmooth = movmedian(bottomProfile, windowSize);
    
    %% 4. FIND CORNERS (UNIFIED: works for both peaked and plateau)
    [leftCornerIdx, rightCornerIdx, cornerType] = findCornersUnified(topSmooth);
    % Get Y values at corners
    leftCornerY = topSmooth(leftCornerIdx);
    rightCornerY = topSmooth(rightCornerIdx);
    
    % Get X positions in image coordinates
    leftCornerX = xRange(leftCornerIdx);
    rightCornerX = xRange(rightCornerIdx);
    
    %% 5. BOTTOM FLOOR (median between corners only)
    bottomBetweenCorners = bottomSmooth(leftCornerIdx:rightCornerIdx);
    bottomFloor_Y = median(bottomBetweenCorners);
    
    %% 6. FIT PARABOLA
    xFit = leftCornerIdx:rightCornerIdx;
    yFit = topSmooth(xFit);
    nFitPoints = length(xFit);
    xCentered = xFit - mean(xFit);
    
    try
        p = polyfit(xCentered, yFit, 2);
        a_coeff = p(1);
        b_coeff = p(2);
        
        xVertexCentered = -b_coeff / (2 * a_coeff);
        yVertex = polyval(p, xVertexCentered);
        xVertexIdx = round(xVertexCentered + mean(xFit));
        xVertexIdx = max(1, min(length(topSmooth), xVertexIdx));
        xVertexInImage = xRange(1) + xVertexIdx - 1;
        
        xCenteredFull = (1:length(topSmooth)) - mean(xFit);
        topFitted = polyval(p, xCenteredFull);
        
        yFittedRegion = polyval(p, xCentered);
        SS_res = sum((yFit - yFittedRegion).^2);
        SS_tot = sum((yFit - mean(yFit)).^2);
        R2 = 1 - SS_res / SS_tot;
        
        parabolaFitValid = true;
    catch
        a_coeff = NaN;
        xVertexIdx = NaN; xVertexInImage = NaN; yVertex = NaN;
        topFitted = nan(size(topSmooth));
        R2 = NaN;
        parabolaFitValid = false;
    end
    
    %% 7. BASELINE (horizontal at higher corner)
    idealTop_Y = min(leftCornerY, rightCornerY);
    baselineIdeal = ones(1, length(topSmooth)) * idealTop_Y;
    
    %% 8. THEORETICAL DIMENSIONS
    % Height: layers × layer height → convert to image pixels
    if ~isnan(H_layers) && ~isnan(layerHeight_mm) && ~isnan(mmPerPx)
        theoreticalHeight_mm = H_layers * layerHeight_mm;
        theoreticalHeight_px = theoreticalHeight_mm / mmPerPx;
    else
        theoreticalHeight_mm = NaN;
        theoreticalHeight_px = NaN;
    end
    
    % Width: printer pixels × printer pixel size → convert to image pixels
    if ~isnan(Width_printer_pixels) && ~isnan(pixelWidth_mm) && ~isnan(mmPerPx)
        theoreticalWidth_mm = Width_printer_pixels * pixelWidth_mm;
        theoreticalWidth_px = theoreticalWidth_mm / mmPerPx;
    else
        theoreticalWidth_mm = NaN;
        theoreticalWidth_px = NaN;
    end
    
    %% 9. MEASURED DIMENSIONS (USE BOUNDING BOX for comparison with theoretical)
    % Bounding box represents the full extent of the lumen
    measuredHeight_px = bbHeight;
    measuredHeight_mm = bbHeight * mmPerPx;
    
    measuredWidth_px = bbWidth;
    measuredWidth_mm = bbWidth * mmPerPx;
    
    % Span width between corners (for sag analysis only)
    spanWidth_px = rightCornerIdx - leftCornerIdx;
    spanWidth_mm = spanWidth_px * mmPerPx;
    
    %% 10. SAG DEPTH
    if parabolaFitValid
        sagDepth_px = yVertex - idealTop_Y;
    else
        [troughY, ~] = max(topSmooth(leftCornerIdx:rightCornerIdx));
        sagDepth_px = troughY - idealTop_Y;
    end
    sagDepth_mm = sagDepth_px * mmPerPx;
    
    % Sag area
    sagRegion = topSmooth(leftCornerIdx:rightCornerIdx);
    baselineRegion = baselineIdeal(leftCornerIdx:rightCornerIdx);
    sagArea_px2 = trapz(max(0, sagRegion - baselineRegion));
    sagArea_mm2 = sagArea_px2 * mmPerPx^2;
    
    %% 11. WALL TILT (relative to bounding box)
    leftWallInward_px = leftCornerX - bbLeft;
    rightWallInward_px = bbRight - rightCornerX;
    totalWallInward_px = leftWallInward_px + rightWallInward_px;
    
    leftWallInward_mm = leftWallInward_px * mmPerPx;
    rightWallInward_mm = rightWallInward_px * mmPerPx;
    
    if measuredHeight_px > 0
        leftWallTiltAngle_deg = atand(leftWallInward_px / measuredHeight_px);
        rightWallTiltAngle_deg = atand(rightWallInward_px / measuredHeight_px);
    else
        leftWallTiltAngle_deg = NaN;
        rightWallTiltAngle_deg = NaN;
    end
    
    %% 12. NORMALIZED METRICS
    
    % Sag relative to measured (bounding box) height
    sagPct_ofMeasuredHeight = (sagDepth_px / measuredHeight_px) * 100;
    
    % Sag relative to theoretical height
    if ~isnan(theoreticalHeight_px) && theoreticalHeight_px > 0
        sagPct_ofTheoreticalHeight = (sagDepth_px / theoreticalHeight_px) * 100;
    else
        sagPct_ofTheoreticalHeight = NaN;
    end
    
    % Sag relative to span width (width between corners)
    sagPct_ofWidthSpan = (sagDepth_px / spanWidth_px) * 100;
    
    % Height: measured (BB) vs theoretical
    if ~isnan(theoreticalHeight_px) && theoreticalHeight_px > 0
        heightRatio = measuredHeight_px / theoreticalHeight_px;
        heightPct_ofTheoretical = heightRatio * 100;
    else
        heightRatio = NaN;
        heightPct_ofTheoretical = NaN;
    end
    
    % Width: measured (BB) vs theoretical
    if ~isnan(theoreticalWidth_px) && theoreticalWidth_px > 0
        widthRatio = measuredWidth_px / theoreticalWidth_px;
        widthPct_ofTheoretical = widthRatio * 100;
    else
        widthRatio = NaN;
        widthPct_ofTheoretical = NaN;
    end
    
    % Wall tilt as % of theoretical width
    if ~isnan(theoreticalWidth_px)
        totalTiltPct_ofTheoWidth = (totalWallInward_px / theoreticalWidth_px) * 100;
    else
        totalTiltPct_ofTheoWidth = NaN;
    end
    
    % Area
    areaRatio_actual_vs_BB = actualArea_px2 / bbArea_px2;
    convexityRatio = actualArea_px2 / convexArea_px2;
    
    if ~isnan(theoreticalHeight_px) && ~isnan(theoreticalWidth_px)
        theoreticalArea_px2 = theoreticalHeight_px * theoreticalWidth_px;
        theoreticalArea_mm2 = theoreticalHeight_mm * theoreticalWidth_mm;
        areaRatio_actual_vs_theo = actualArea_px2 / theoreticalArea_px2;
        areaPct_ofTheoretical = areaRatio_actual_vs_theo * 100;
    else
        theoreticalArea_px2 = NaN;
        theoreticalArea_mm2 = NaN;
        areaRatio_actual_vs_theo = NaN;
        areaPct_ofTheoretical = NaN;
    end
    
    actualArea_mm2 = actualArea_px2 * mmPerPx^2;
    bbArea_mm2 = bbArea_px2 * mmPerPx^2;
    
    %% 13. PACK OUTPUT
    sagMetrics.valid = true;
    
    % Parabola
    sagMetrics.parabolaR2 = R2;
    sagMetrics.parabolaCoeff_a = a_coeff;
    sagMetrics.parabolaFitPoints = nFitPoints;
    
    % Sag depth
    sagMetrics.sagDepth_px = sagDepth_px;
    sagMetrics.sagDepth_mm = sagDepth_mm;
    sagMetrics.sagArea_px2 = sagArea_px2;
    sagMetrics.sagArea_mm2 = sagArea_mm2;
    
    % Sag normalized
    sagMetrics.sagPct_ofMeasuredHeight = sagPct_ofMeasuredHeight;
    sagMetrics.sagPct_ofTheoreticalHeight = sagPct_ofTheoreticalHeight;
    sagMetrics.sagPct_ofWidthSpan = sagPct_ofWidthSpan;
    
    % Height (using bounding box as measured)
    sagMetrics.measuredHeight_px = measuredHeight_px;
    sagMetrics.measuredHeight_mm = measuredHeight_mm;
    sagMetrics.theoreticalHeight_px = theoreticalHeight_px;
    sagMetrics.theoreticalHeight_mm = theoreticalHeight_mm;
    sagMetrics.heightPct_ofTheoretical = heightPct_ofTheoretical;
    
    % Width (using bounding box as measured)
    sagMetrics.measuredWidth_px = measuredWidth_px;
    sagMetrics.measuredWidth_mm = measuredWidth_mm;
    sagMetrics.theoreticalWidth_px = theoreticalWidth_px;
    sagMetrics.theoreticalWidth_mm = theoreticalWidth_mm;
    sagMetrics.widthPct_ofTheoretical = widthPct_ofTheoretical;
    
    % Span width (between corners, for sag analysis)
    sagMetrics.spanWidth_px = spanWidth_px;
    sagMetrics.spanWidth_mm = spanWidth_mm;
    
    % Wall tilt
    sagMetrics.leftWallInward_px = leftWallInward_px;
    sagMetrics.leftWallInward_mm = leftWallInward_mm;
    sagMetrics.rightWallInward_px = rightWallInward_px;
    sagMetrics.rightWallInward_mm = rightWallInward_mm;
    sagMetrics.totalWallInward_px = totalWallInward_px;
    sagMetrics.totalWallInward_mm = totalWallInward_px * mmPerPx;
    sagMetrics.leftWallTiltAngle_deg = leftWallTiltAngle_deg;
    sagMetrics.rightWallTiltAngle_deg = rightWallTiltAngle_deg;
    sagMetrics.avgWallTiltAngle_deg = mean([leftWallTiltAngle_deg, rightWallTiltAngle_deg]);
    sagMetrics.totalTiltPct_ofTheoWidth = totalTiltPct_ofTheoWidth;
    
    % Area
    sagMetrics.actualArea_px2 = actualArea_px2;
    sagMetrics.actualArea_mm2 = actualArea_mm2;
    sagMetrics.theoreticalArea_px2 = theoreticalArea_px2;
    sagMetrics.theoreticalArea_mm2 = theoreticalArea_mm2;
    sagMetrics.areaPct_ofTheoretical = areaPct_ofTheoretical;
    sagMetrics.areaRatio_actual_vs_BB = areaRatio_actual_vs_BB;
    sagMetrics.convexityRatio = convexityRatio;
    
    % Corner positions
    sagMetrics.leftCornerX = leftCornerX;
    sagMetrics.rightCornerX = rightCornerX;
    sagMetrics.leftCornerY = leftCornerY;
    sagMetrics.rightCornerY = rightCornerY;

    sagMetrics.cornerType = cornerType;
    
    % Profiles
    sagMetrics.profiles.topSmooth = topSmooth;
    sagMetrics.profiles.bottomSmooth = bottomSmooth;
    sagMetrics.profiles.topFitted = topFitted;
    sagMetrics.profiles.baselineIdeal = baselineIdeal;
    sagMetrics.profiles.xCoords = xRange;
    sagMetrics.profiles.bottomFloor_Y = bottomFloor_Y;
    sagMetrics.profiles.idealTop_Y = idealTop_Y;
    sagMetrics.profiles.leftCornerIdx = leftCornerIdx;
    sagMetrics.profiles.rightCornerIdx = rightCornerIdx;
    
    %% 14. DEBUG VISUALIZATION
    if debugPlot
        plotSagDebug(BW, sagMetrics, bbLeft, bbTop, bbRight, bbBottom, bbWidth, bbHeight, ...
                     xRange, topSmooth, bottomSmooth, topFitted, baselineIdeal, ...
                     leftCornerIdx, rightCornerIdx, leftCornerX, rightCornerX, ...
                     leftCornerY, rightCornerY, xVertexInImage, xVertexIdx, yVertex, ...
                     idealTop_Y, bottomFloor_Y, parabolaFitValid, ...
                     sagDepth_px, sagDepth_mm, ...
                     measuredHeight_px, theoreticalHeight_px, heightPct_ofTheoretical, ...
                     measuredWidth_px, theoreticalWidth_px, widthPct_ofTheoretical, ...
                     spanWidth_px, R2, sagPct_ofMeasuredHeight, sagPct_ofTheoreticalHeight, ...
                     sagPct_ofWidthSpan, areaPct_ofTheoretical);
    end
end

%% HELPER: Initialize all fields with NaN
function sagMetrics = initializeSagMetrics()
    sagMetrics.valid = false;
    
    sagMetrics.parabolaR2 = NaN;
    sagMetrics.parabolaCoeff_a = NaN;
    sagMetrics.parabolaFitPoints = NaN;
    
    sagMetrics.sagDepth_px = NaN;
    sagMetrics.sagDepth_mm = NaN;
    sagMetrics.sagArea_px2 = NaN;
    sagMetrics.sagArea_mm2 = NaN;
    sagMetrics.sagPct_ofMeasuredHeight = NaN;
    sagMetrics.sagPct_ofTheoreticalHeight = NaN;
    sagMetrics.sagPct_ofWidthSpan = NaN;
    
    sagMetrics.measuredHeight_px = NaN;
    sagMetrics.measuredHeight_mm = NaN;
    sagMetrics.theoreticalHeight_px = NaN;
    sagMetrics.theoreticalHeight_mm = NaN;
    sagMetrics.heightPct_ofTheoretical = NaN;
    
    sagMetrics.measuredWidth_px = NaN;
    sagMetrics.measuredWidth_mm = NaN;
    sagMetrics.theoreticalWidth_px = NaN;
    sagMetrics.theoreticalWidth_mm = NaN;
    sagMetrics.widthPct_ofTheoretical = NaN;
    
    sagMetrics.spanWidth_px = NaN;
    sagMetrics.spanWidth_mm = NaN;
    
    sagMetrics.leftWallInward_px = NaN;
    sagMetrics.leftWallInward_mm = NaN;
    sagMetrics.rightWallInward_px = NaN;
    sagMetrics.rightWallInward_mm = NaN;
    sagMetrics.totalWallInward_px = NaN;
    sagMetrics.totalWallInward_mm = NaN;
    sagMetrics.leftWallTiltAngle_deg = NaN;
    sagMetrics.rightWallTiltAngle_deg = NaN;
    sagMetrics.avgWallTiltAngle_deg = NaN;
    sagMetrics.totalTiltPct_ofTheoWidth = NaN;
    
    sagMetrics.actualArea_px2 = NaN;
    sagMetrics.actualArea_mm2 = NaN;
    sagMetrics.theoreticalArea_px2 = NaN;
    sagMetrics.theoreticalArea_mm2 = NaN;
    sagMetrics.areaPct_ofTheoretical = NaN;
    sagMetrics.areaRatio_actual_vs_BB = NaN;
    sagMetrics.convexityRatio = NaN;
    
    sagMetrics.leftCornerX = NaN;
    sagMetrics.rightCornerX = NaN;
    sagMetrics.leftCornerY = NaN;
    sagMetrics.rightCornerY = NaN;

    sagMetrics.cornerType = '';
    
    sagMetrics.profiles = struct();
end

%% HELPER: Debug plot
function plotSagDebug(BW, sagMetrics, bbLeft, bbTop, bbRight, bbBottom, bbWidth, bbHeight, ...
                      xRange, topSmooth, bottomSmooth, topFitted, baselineIdeal, ...
                      leftCornerIdx, rightCornerIdx, leftCornerX, rightCornerX, ...
                      leftCornerY, rightCornerY, xVertexInImage, xVertexIdx, yVertex, ...
                      idealTop_Y, bottomFloor_Y, parabolaFitValid, ...
                      sagDepth_px, sagDepth_mm, ...
                      measHeight_px, theoHeight_px, heightPct, ...
                      measWidth_px, theoWidth_px, widthPct, ...
                      spanWidth_px, R2, sagPct_H, sagPct_Htheo, sagPct_span, areaPct)
    
    [nRows, nCols] = size(BW);
    
    figure('Position', [50 50 1500 700]);
    
    % Zoom region
    pad = 30;
    zoomLeft = max(1, bbLeft - pad);
    zoomRight = min(nCols, bbRight + pad);
    zoomTop = max(1, bbTop - pad);
    zoomBottom = min(nRows, bbBottom + pad);
    
    BWcropped = BW(zoomTop:zoomBottom, zoomLeft:zoomRight);
    offsetX = zoomLeft - 1;
    offsetY = zoomTop - 1;
    
    % ===== SUBPLOT 1: Zoomed mask =====
    subplot(1, 2, 1);
    imshow(BWcropped); hold on;
    
    % Bounding box (yellow dashed)
    rectangle('Position', [bbLeft-offsetX, bbTop-offsetY, bbWidth, bbHeight], ...
              'EdgeColor', 'y', 'LineWidth', 2, 'LineStyle', '--');
    
    % Top edge (blue)
    plot(xRange - offsetX, topSmooth - offsetY, 'b-', 'LineWidth', 2);
    
    % Baseline (green)
    plot(xRange - offsetX, baselineIdeal - offsetY, 'g-', 'LineWidth', 2);
    
    % Bottom edge ONLY between corners (cyan)
    xBetween = xRange(leftCornerIdx:rightCornerIdx);
    bottomBetween = bottomSmooth(leftCornerIdx:rightCornerIdx);
    plot(xBetween - offsetX, bottomBetween - offsetY, 'c-', 'LineWidth', 1.5);
    
    % Bottom floor line (cyan dashed)
    plot([xRange(leftCornerIdx) xRange(rightCornerIdx)] - offsetX, ...
         [bottomFloor_Y bottomFloor_Y] - offsetY, 'c--', 'LineWidth', 2);
    
    % Corners (green circles)
    plot(leftCornerX - offsetX, leftCornerY - offsetY, 'go', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    plot(rightCornerX - offsetX, rightCornerY - offsetY, 'go', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    
    % Parabola vertex (red triangle)
    if parabolaFitValid && ~isnan(yVertex)
        plot(xVertexInImage - offsetX, yVertex - offsetY, 'r^', 'MarkerSize', 12, 'LineWidth', 3, 'MarkerFaceColor', 'r');
        % Sag depth line (magenta)
        plot([xVertexInImage xVertexInImage] - offsetX, [idealTop_Y yVertex] - offsetY, 'm-', 'LineWidth', 3);
    end
    
    % Sag area fill (red transparent)
    xFill = xRange(leftCornerIdx:rightCornerIdx) - offsetX;
    yTop = topSmooth(leftCornerIdx:rightCornerIdx) - offsetY;
    yBase = baselineIdeal(leftCornerIdx:rightCornerIdx) - offsetY;
    fill([xFill fliplr(xFill)], [yTop fliplr(yBase)], 'r', 'FaceAlpha', 0.25, 'EdgeColor', 'none');
    
    % Title with key metrics
    title(sprintf('Sag: %.1f px (%.3f mm)\nH: %.1f%% of theo | W: %.1f%% of theo | Area: %.1f%% of theo', ...
                  sagDepth_px, sagDepth_mm, heightPct, widthPct, areaPct), 'FontSize', 10);
    axis tight;
    hold off;
    
    % ===== SUBPLOT 2: Profile plot =====
    subplot(1, 2, 2);
    xCoords = 1:length(topSmooth);
    
    % Top edge (blue)
    plot(xCoords, topSmooth, 'b-', 'LineWidth', 2); hold on;
    
    % Baseline (green)
    plot(xCoords, baselineIdeal, 'g-', 'LineWidth', 2);
    
    % Parabola fit (red dotted)
    if parabolaFitValid
        plot(xCoords, topFitted, 'r:', 'LineWidth', 2);
    end
    
    % Bottom edge ONLY between corners (cyan)
    plot(leftCornerIdx:rightCornerIdx, bottomSmooth(leftCornerIdx:rightCornerIdx), 'c-', 'LineWidth', 1.5);
    
    % Bottom floor line (cyan dashed)
    plot([leftCornerIdx rightCornerIdx], [bottomFloor_Y bottomFloor_Y], 'c--', 'LineWidth', 2);
    
    % Corners (green)
    plot(leftCornerIdx, leftCornerY, 'go', 'MarkerSize', 10, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    plot(rightCornerIdx, rightCornerY, 'go', 'MarkerSize', 10, 'LineWidth', 3, 'MarkerFaceColor', 'g');
    
    % Vertex (red triangle)
    if parabolaFitValid && ~isnan(yVertex)
        plot(xVertexIdx, yVertex, 'r^', 'MarkerSize', 10, 'LineWidth', 2, 'MarkerFaceColor', 'r');
        % Sag depth line (magenta)
        plot([xVertexIdx xVertexIdx], [idealTop_Y yVertex], 'm-', 'LineWidth', 3);
    end
    
    % Lumen height indicator (black)
    midIdx = round((leftCornerIdx + rightCornerIdx) / 2);
    plot([midIdx midIdx], [idealTop_Y bottomFloor_Y], 'k-', 'LineWidth', 2);
    
    % Sag area fill
    xFillPlot = leftCornerIdx:rightCornerIdx;
    fill([xFillPlot fliplr(xFillPlot)], [topSmooth(xFillPlot) fliplr(baselineIdeal(xFillPlot))], ...
         'r', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
    
    set(gca, 'YDir', 'reverse');
    xlabel('Position (px)');
    ylabel('Y (px)');
    grid on;
    
    % Simplified legend
    legend({'Top edge', 'Ideal baseline', sprintf('Parabola (R²=%.3f)', R2), ...
            'Bottom (between corners)', 'Bottom floor', 'Corners', '', ...
            'Sag vertex', sprintf('Sag=%.1fpx', sagDepth_px)}, ...
           'Location', 'southeast', 'FontSize', 8);
    
    title(sprintf('Profile (R² = %.3f)', R2), 'FontSize', 10);
    hold off;
    
    % ===== MAIN TITLE =====
    sgtitle(sprintf(['SAG ANALYSIS\n' ...
        'Sag: %.1f px = %.3f mm | %.1f%% of H_{meas} | %.1f%% of H_{theo} | %.1f%% of width span\n' ...
        'Height: meas_bb=%.0fpx, theo=%.0fpx (%.1f%%) | Width: meas_bb=%.0fpx, theo=%.0fpx (%.1f%%)'], ...
        sagDepth_px, sagDepth_mm, sagPct_H, sagPct_Htheo, sagPct_span, ...
        measHeight_px, theoHeight_px, heightPct, ...
        measWidth_px, theoWidth_px, widthPct), ...
        'FontSize', 10, 'FontWeight', 'bold');
end