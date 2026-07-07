function plotComparativeSag(T, resultsFolder, metricColumn, baselineType, outputSuffix)
% PLOTCOMPARATIVESAG  3D scatter, 3D surface, and 2D line plots of sag metric.
%   Handles replicates via groupsummary. Negative sag clamped to zero.
%   Reports quality stats and low-n warnings to command window.
%
%   Produces 3 figures:
%     1) 3D scatter with error bars (no R²/n labels on markers)
%     2) 3D surface fit through group means
%     3) 2D line plot: one line per Roof_layers, x=Width, y=sag, with error bars
%
%   Inputs:
%       T             - Data table from pipeline
%       resultsFolder - Output folder path
%       metricColumn  - (optional) default 'SagPct_ofMeasuredHeight'
%       baselineType  - (optional) default 'Corner'
%       outputSuffix  - (optional) default ''

    % --- Defaults ---
    if nargin < 3 || isempty(metricColumn),  metricColumn = 'SagPct_ofMeasuredHeight'; end
    if nargin < 4 || isempty(baselineType),  baselineType = 'Corner'; end
    if nargin < 5 || isempty(outputSuffix),  outputSuffix = ''; end

    if ~ismember(metricColumn, T.Properties.VariableNames)
        warning('Column "%s" not found. Skipping.', metricColumn);
        return;
    end

    if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end

    % =====================================================================
    % 1. FILTER: open lumens with sag data
    % =====================================================================
    isOpen = strcmp(T.LumenStatus, 'open');
    hasSag = ~isnan(T.(metricColumn));
    keepIdx = isOpen & hasSag;

    T_clean = T(keepIdx, :);

    % Clamp negative sag to zero
    negMask = T_clean.(metricColumn) < 0;
    nClamped = sum(negMask);
    T_clean.(metricColumn)(negMask) = 0;

    if isempty(T_clean) || height(T_clean) == 0
        warning('No valid data points. Skipping.');
        return;
    end
    % =====================================================================
    % 1b. PLOTTING-ONLY REMAP OF ROOF LAYERS
    %     If filenames were numbered backwards, reverse here without
    %     touching the saved table or rerunning the pipeline.
    % =====================================================================
    T_plot = T_clean;

    % Reverse ML numbering: 1<->10, 2<->9, ..., 10<->1
    % Assumes the intended ML range is 1:10.
    T_plot.Roof_layers = 11 - T_plot.Roof_layers;

    % =====================================================================
    % 2. QUALITY STATS (command window only)
    % =====================================================================
    hasGeomCols = all(ismember({'IsVertexBetween','IsVertexLowerLeft','IsVertexLowerRight'}, ...
                               T.Properties.VariableNames));
    hasR2Col    = ismember('ParabolaR2', T.Properties.VariableNames);

    fprintf('\n=== SAG PLOT SUMMARY (%s Baseline, %s) ===\n', baselineType, metricColumn);
    fprintf('Total rows in T:            %d\n', height(T));
    fprintf('Open lumens with sag data:  %d\n', height(T_clean));
    fprintf('Negative sag clamped to 0:  %d\n', nClamped);

    if hasGeomCols
        gv = T_clean.IsVertexBetween & T_clean.IsVertexLowerLeft & T_clean.IsVertexLowerRight;
        fprintf('Geometry valid:             %d / %d (%.0f%%)\n', ...
            sum(gv), height(T_clean), 100*mean(gv));
        fprintf('  IsVertexBetween fail:     %d\n', sum(~T_clean.IsVertexBetween));
        fprintf('  IsVertexLowerLeft fail:   %d\n', sum(~T_clean.IsVertexLowerLeft));
        fprintf('  IsVertexLowerRight fail:  %d\n', sum(~T_clean.IsVertexLowerRight));
    end

    if hasR2Col
        r2vals = T_clean.ParabolaR2;
        fprintf('R² stats:  mean=%.2f  median=%.2f  min=%.2f  max=%.2f\n', ...
            mean(r2vals,'omitnan'), median(r2vals,'omitnan'), ...
            min(r2vals), max(r2vals));
        fprintf('  R² >= 0.8: %d (%.0f%%)\n', sum(r2vals>=0.8), 100*mean(r2vals>=0.8));
        fprintf('  R² >= 0.5: %d (%.0f%%)\n', sum(r2vals>=0.5), 100*mean(r2vals>=0.5));
        fprintf('  R² <  0.5: %d (%.0f%%)\n', sum(r2vals<0.5),  100*mean(r2vals<0.5));
    end

    % =====================================================================
    % 3. GROUP STATISTICS
    % =====================================================================
    T_stats = groupsummary(T_clean, {'Width_px','Roof_layers','Condition'}, ...
                           {'mean','std'}, metricColumn);

    meanCol  = ['mean_' metricColumn];
    stdCol   = ['std_' metricColumn];
    countCol = 'GroupCount';

    % SEM
    T_stats.SEM = T_stats.(stdCol) ./ sqrt(T_stats.(countCol));

    % Remove NaN means
    T_stats = T_stats(~isnan(T_stats.(meanCol)), :);
    % =====================================================================
    % 3b. USER OVERRIDE:
    %     If sag is missing at high widths, force it to 100%.
    %     This is a plotting assumption, not a measured value.
    % =====================================================================

    % Define what counts as "high width"
    highWidthThreshold = 80;   % change if needed, e.g. 70, 80, 90

    % Build the full Width x Roof x Condition grid from observed plotting levels
    allWidths = sort(unique(T_plot.Width_px));
    allRoofs  = sort(unique(T_plot.Roof_layers));
    allConds  = unique(T_plot.Condition, 'stable');

    nFill = 0;

    for c = 1:numel(allConds)
        condName = allConds{c};
        for r = 1:numel(allRoofs)
            roofVal = allRoofs(r);
            for w = 1:numel(allWidths)
                widthVal = allWidths(w);

                if widthVal < highWidthThreshold
                    continue;
                end

                idx = strcmp(T_stats.Condition, condName) & ...
                      T_stats.Roof_layers == roofVal & ...
                      T_stats.Width_px == widthVal;

                if ~any(idx)
                    newRow = T_stats(1,:);
                    newRow.Width_px = widthVal;
                    newRow.Roof_layers = roofVal;
                    newRow.Condition = {condName};
                    newRow.(meanCol) = 100;
                    newRow.(stdCol)  = 0;
                    newRow.(countCol)= 1;
                    newRow.SEM       = 0;

                    T_stats = [T_stats; newRow];
                    nFill = nFill + 1;
                end
            end
        end
    end

    % Keep table ordered nicely after insertion
    T_stats = sortrows(T_stats, {'Condition','Roof_layers','Width_px'});

    fprintf('Plot override: inserted %d missing high-width groups as 100%% sag (Width >= %d).\n', ...
        nFill, highWidthThreshold);

    if isempty(T_stats)
        warning('No valid group statistics. Skipping.');
        return;
    end

    % --- Report low-n groups ---
    lowN = T_stats(T_stats.(countCol) < 3, :);
    if ~isempty(lowN) && height(lowN) > 0
        fprintf('\n*** WARNING: %d groups with n < 3 ***\n', height(lowN));
        for row = 1:height(lowN)
            fprintf('  Cond=%-15s W=%3d R=%2d  n=%d  mean=%.1f%%\n', ...
                lowN.Condition{row}, lowN.Width_px(row), lowN.Roof_layers(row), ...
                lowN.(countCol)(row), lowN.(meanCol)(row));
        end
    end

    % Summary
    fprintf('\nGroup summary: %d groups, n range [%d, %d]\n', ...
        height(T_stats), min(T_stats.(countCol)), max(T_stats.(countCol)));

    % =====================================================================
    % Style setup
    % =====================================================================
    conditions = unique(T_stats.Condition, 'stable');
    condColors = lines(max(numel(conditions), 3));
    markerList = {'o','s','^','d','v','>','<','p','h'};
    lineStyles = {'-','--',':','-.'};

    % =====================================================================
    % FIGURE 1: 3D Scatter with error bars (no text labels on markers)
    % =====================================================================
    fig1 = figure('Position', [100 100 1100 750], 'Color', 'w');
    hold on;

    legH1 = []; legL1 = {};

    for c = 1:numel(conditions)
        condName = conditions{c};
        mask = strcmp(T_stats.Condition, condName);
        subT = T_stats(mask, :);
        if isempty(subT), continue; end

        col = condColors(c,:);
        mk  = markerList{mod(c-1,numel(markerList))+1};

        xD = subT.Width_px;
        yD = subT.Roof_layers;
        zD = subT.(meanCol);
        eD = subT.SEM;

        h = scatter3(xD, yD, zD, 80, col, mk, 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
        legH1 = [legH1, h]; %#ok<AGROW>
        legL1 = [legL1, {condName}]; %#ok<AGROW>

        for j = 1:height(subT)
            if ~isnan(eD(j)) && eD(j) > 0 && subT.(countCol)(j) > 1
                plot3([xD(j) xD(j)], [yD(j) yD(j)], [zD(j)-eD(j) zD(j)+eD(j)], ...
                    '-', 'Color', col, 'LineWidth', 1.2, 'HandleVisibility', 'off');
            end
        end
    end

    xlabel('Width (printer px)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Membrane Layers', 'FontSize', 11, 'FontWeight', 'bold');
    zlabel('Sag (% of Measured Height)', 'FontSize', 11, 'FontWeight', 'bold');
    title({sprintf('Sag Depth — %s Baseline (3D Scatter)', baselineType), ...
           sprintf('%d groups, error bars = ±1 SEM', height(T_stats))}, 'FontSize', 12);
    grid on; view(45, 30);
    zlim([0 100]);
    legend(legH1, legL1, 'Location', 'bestoutside');
    hold off;

    saveas(fig1, fullfile(resultsFolder, ['sag_3Dscatter' outputSuffix '.png']));
    fprintf('Saved: sag_3Dscatter%s.png\n', outputSuffix);

    % =====================================================================
    % FIGURE 2: 3D Surface fit through group means
    % =====================================================================
    fig2 = figure('Position', [100 100 1100 750], 'Color', 'w');
    hold on;

    legH2 = []; legL2 = {};

    for c = 1:numel(conditions)
        condName = conditions{c};
        mask = strcmp(T_stats.Condition, condName);
        subT = T_stats(mask, :);
        if isempty(subT) || height(subT) < 3, continue; end

        col = condColors(c,:);

        xD = subT.Width_px;
        yD = subT.Roof_layers;
        zD = subT.(meanCol);

        % Build grid for surface
        widths = unique(xD, 'sorted');
        roofs  = unique(yD, 'sorted');
        [Xg, Yg] = meshgrid(widths, roofs);
        Zg = nan(size(Xg));

        for i = 1:numel(widths)
            for j = 1:numel(roofs)
                idx = (xD == widths(i)) & (yD == roofs(j));
                if any(idx)
                    Zg(j, i) = zD(find(idx, 1));
                end
            end
        end

        % Interpolate NaN gaps if enough data
        if sum(~isnan(Zg(:))) >= 4
            try
                F = scatteredInterpolant(xD, yD, zD, 'natural', 'none');
                Zg_interp = F(Xg, Yg);
                % Only fill NaN positions that are within convex hull of data
                nanMask = isnan(Zg);
                Zg(nanMask) = Zg_interp(nanMask);
            catch
                % If interpolation fails, just use what we have
            end
        end

        hSurf = surf(Xg, Yg, Zg, ...
            'FaceColor', 'interp', ...
            'FaceAlpha', 0.75, ...
            'EdgeColor', [0.3 0.6 0.9], ...
            'EdgeAlpha', 0.5, ...
            'LineWidth', 0.8);

        % Scatter the actual points on top
        hPts = scatter3(xD, yD, zD, 60, col, 'o', 'filled', ...
            'MarkerEdgeColor', 'k', 'LineWidth', 0.5);

        legH2 = [legH2, hPts]; %#ok<AGROW>
        legL2 = [legL2, {condName}]; %#ok<AGROW>
    end

    xlabel('Width (printer px)', 'FontSize', 11, 'FontWeight', 'bold');
    ylabel('Roof Thickness (# of print layers)', 'FontSize', 11, 'FontWeight', 'bold');
    zlabel('Sag (% of Measured Height)', 'FontSize', 11, 'FontWeight', 'bold');
    title('');
    grid on; view(45, 30);
    xlim([15 inf]);
    zlim([0 100]);

    colormap(turbo);
    cb = colorbar;
    cb.Label.String = 'Sag (% of Measured Height)';
    cb.FontSize = 11;
    clim([0 100]);

    hold off;

    saveas(fig2, fullfile(resultsFolder, ['sag_3Dsurface' outputSuffix '.png']));
    fprintf('Saved: sag_3Dsurface%s.png\n', outputSuffix);

    % =====================================================================
    % FIGURE 3: 2D Line plot — one line per Roof_layers
    % =====================================================================
    fig3 = figure('Position', [100 100 1200 700], 'Color', 'w');
    hold on;

    legH3 = []; legL3 = {};

    roofVals = sort(unique(T_stats.Roof_layers));

    for c = 1:numel(conditions)
        condName = conditions{c};

        for r = 1:numel(roofVals)
            roofVal = roofVals(r);

            mask = strcmp(T_stats.Condition, condName) & ...
                   (T_stats.Roof_layers == roofVal);
            subT = T_stats(mask, :);

            if isempty(subT) || height(subT) == 0
                continue;
            end

            [xData, si] = sort(subT.Width_px);
            yData = subT.(meanCol)(si);
            eData = subT.SEM(si);

            % Clamp error bars so they don't go below zero
            eLow = min(eData, yData);
            eHigh = eData;

            thisColor  = condColors(mod(c-1, size(condColors,1))+1, :);
            thisMk     = markerList{mod(r-1, numel(markerList))+1};
            thisLine   = lineStyles{mod(r-1, numel(lineStyles))+1};

            h = errorbar(xData, yData, eLow, eHigh, ...
                'LineStyle', thisLine, ...
                'Marker', thisMk, ...
                'LineWidth', 1.6, ...
                'MarkerSize', 7, ...
                'CapSize', 6, ...
                'Color', thisColor, ...
                'MarkerFaceColor', thisColor);

            legH3 = [legH3, h]; %#ok<AGROW>
            if numel(conditions) > 1
                legL3 = [legL3, {sprintf('%s | R=%d', condName, roofVal)}]; %#ok<AGROW>
            else
                legL3 = [legL3, {sprintf('Roof = %d layers', roofVal)}]; %#ok<AGROW>
            end
        end
    end

    xlabel('Width (printer px, 1 px = 32 \mum)', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Sag (% of Measured Height)', 'FontSize', 12, 'FontWeight', 'bold');
    title({sprintf('Sag vs Width by Roof Thickness — %s Baseline', baselineType), ...
           'Mean ± SEM across replicates'}, 'FontSize', 13);
    grid on; box on;
    set(gca, 'FontSize', 11, 'LineWidth', 1);
    ylim([0 inf]);

    if ~isempty(legH3)
        legend(legH3, legL3, 'Location', 'bestoutside', 'Interpreter', 'none');
    end
    hold off;

    saveas(fig3, fullfile(resultsFolder, ['sag_lines' outputSuffix '.png']));
    try
        exportgraphics(fig3, fullfile(resultsFolder, ['sag_lines' outputSuffix '.pdf']), ...
            'ContentType', 'vector');
    catch
    end
    fprintf('Saved: sag_lines%s.png\n', outputSuffix);

end