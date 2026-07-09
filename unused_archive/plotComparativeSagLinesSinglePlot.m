function plotComparativeSagLinesSinglePlot(T, resultsFolder, metricColumn, baselineType, outputSuffix, errorType)
% PLOTCOMPARATIVESAGLINESSINGLEPLOT
% Single 2D plot of mean sag vs width with error bars.
% One line is drawn for each Condition x Roof_layers combination.
%
% Visual encoding:
%   x-axis   = Width_px
%   y-axis   = mean sag metric
%   color    = Condition
%   linestyle/marker = Roof_layers
%
% Inputs:
%   T             - data table
%   resultsFolder - output folder
%   metricColumn  - metric column name, default 'SagPct_ofMeasuredHeight'
%   baselineType  - title label, default 'Corner'
%   outputSuffix  - output filename suffix, default ''
%   errorType     - 'std' or 'sem', default 'std'
%
% Example:
%   plotComparativeSagLinesSinglePlot(T, resultsFolder)
%   plotComparativeSagLinesSinglePlot(T, resultsFolder, ...
%       'SagBB_Pct_ofMeasuredHeight', 'BoundingBox', '_BB', 'sem')

    % ----------------------------
    % Default arguments
    % ----------------------------
    if nargin < 3 || isempty(metricColumn)
        metricColumn = 'SagPct_ofMeasuredHeight';
    end
    if nargin < 4 || isempty(baselineType)
        baselineType = 'Corner';
    end
    if nargin < 5 || isempty(outputSuffix)
        outputSuffix = '';
    end
    if nargin < 6 || isempty(errorType)
        errorType = 'std';
    end

    % ----------------------------
    % Check required columns
    % ----------------------------
    requiredVars = {'LumenStatus','IsVertexBetween','IsVertexLowerLeft', ...
                    'IsVertexLowerRight','ParabolaR2','Width_px', ...
                    'Roof_layers','Condition', metricColumn};

    missingVars = requiredVars(~ismember(requiredVars, T.Properties.VariableNames));
    if ~isempty(missingVars)
        error('Missing required columns: %s', strjoin(missingVars, ', '));
    end

    % ----------------------------
    % Filtering logic
    % ----------------------------
    isOpen = strcmp(T.LumenStatus, 'bright');
    isGeometricallyValid = T.IsVertexBetween & T.IsVertexLowerLeft & T.IsVertexLowerRight;
    r2_threshold = 0.5;
    isGoodFit = T.ParabolaR2 >= r2_threshold;

    keepIdx = isOpen & isGeometricallyValid & isGoodFit;

    fprintf('\n=== VISUALIZATION FILTER SUMMARY (%s Baseline) ===\n', baselineType);
    fprintf('Total images analyzed:    %d\n', height(T));
    fprintf('  - Excluded (Occluded):  %d\n', sum(~isOpen));
    fprintf('  - Excluded (Bad Geom):  %d (Vertex outside walls or above corners)\n', ...
            sum(isOpen & ~isGeometricallyValid));
    fprintf('  - Excluded (Poor Fit):  %d (R^2 < %.2f)\n', ...
            sum(isOpen & isGeometricallyValid & ~isGoodFit), r2_threshold);
    fprintf('Final points retained:    %d\n', sum(keepIdx));

    T_clean = T(keepIdx, :);

    if isempty(T_clean) || height(T_clean) == 0
        warning('No valid data points found after filtering. Skipping plot.');
        return;
    end

    % ----------------------------
    % Group statistics
    % ----------------------------
    T_stats = groupsummary(T_clean, {'Width_px','Roof_layers','Condition'}, ...
                           {'mean','std','numel'}, metricColumn);

    meanColName = ['mean_' metricColumn];
    stdColName  = ['std_' metricColumn];

    if ismember('GroupCount', T_stats.Properties.VariableNames)
        nColName = 'GroupCount';
    elseif ismember(['numel_' metricColumn], T_stats.Properties.VariableNames)
        nColName = ['numel_' metricColumn];
    else
        error('Could not determine replicate-count column from groupsummary output.');
    end

    validRows = ~isnan(T_stats.(meanColName));
    T_stats = T_stats(validRows, :);

    if isempty(T_stats) || height(T_stats) == 0
        warning('No valid grouped statistics after filtering. Skipping plot.');
        return;
    end

    % ----------------------------
    % Choose error bars
    % ----------------------------
    switch lower(errorType)
        case 'std'
            T_stats.ErrorBar = T_stats.(stdColName);
            errorLabel = 'Std Dev';
        case 'sem'
            T_stats.ErrorBar = T_stats.(stdColName) ./ sqrt(T_stats.(nColName));
            errorLabel = 'SEM';
        otherwise
            error('errorType must be ''std'' or ''sem''.');
    end

    % ----------------------------
    % Prepare style maps
    % ----------------------------
    conditions = unique(T_stats.Condition, 'stable');
    roofVals   = unique(T_stats.Roof_layers, 'stable');

    nCond = numel(conditions);
    nRoof = numel(roofVals);

    condColors = lines(max(nCond, 3));  % built-in, readable default colors
    lineStyles = {'-','--',':','-.'};
    markers    = {'o','s','^','d','v','>','<','p','h','x','+'};

    % ----------------------------
    % Create figure
    % ----------------------------
    fig = figure('Position', [100 100 1200 750], 'Color', 'w');
    hold on;

    legendHandles = gobjects(0);
    legendLabels  = {};

    % ----------------------------
    % Plot one line per Condition x Roof_layers
    % ----------------------------
    for c = 1:nCond
        condName = conditions{c};
        condMask = strcmp(T_stats.Condition, condName);

        for r = 1:nRoof
            roofVal = roofVals(r);
            mask = condMask & (T_stats.Roof_layers == roofVal);
            subT = T_stats(mask, :);

            if isempty(subT) || height(subT) == 0
                continue;
            end

            % sort by width so line connects correctly
            [xData, sortIdx] = sort(subT.Width_px);
            yData = subT.(meanColName)(sortIdx);
            eData = subT.ErrorBar(sortIdx);

            thisColor  = condColors(c, :);
            thisStyle  = lineStyles{mod(r-1, numel(lineStyles)) + 1};
            thisMarker = markers{mod(r-1, numel(markers)) + 1};

            h = errorbar(xData, yData, eData, ...
                'LineStyle', thisStyle, ...
                'Marker', thisMarker, ...
                'LineWidth', 1.8, ...
                'MarkerSize', 7, ...
                'CapSize', 8, ...
                'Color', thisColor, ...
                'MarkerFaceColor', thisColor);

            legendHandles(end+1) = h; %#ok<AGROW>
            legendLabels{end+1} = sprintf('%s | %d layers', condName, roofVal); %#ok<AGROW>
        end
    end

    % ----------------------------
    % Formatting
    % ----------------------------
    xlabel('Width (printer px)', 'FontSize', 12);
    ylabel('Sag (% of Measured Height)', 'FontSize', 12);
    title({sprintf('Comparative Sag Depth (%s Baseline)', baselineType), ...
           sprintf('Mean over replicates with %s error bars', errorLabel), ...
           sprintf('Filtered for bright lumen, valid parabola geometry, R^2 \\geq %.2f', r2_threshold)}, ...
           'FontSize', 13);

    grid on;
    box on;
    set(gca, 'FontSize', 11, 'LineWidth', 1);

    if ~isempty(legendHandles)
        legend(legendHandles, legendLabels, ...
            'Location', 'bestoutside', ...
            'Interpreter', 'none');
    end

    % Optional symmetric range if your metric is signed
    yAll = T_stats.(meanColName);
    eAll = T_stats.ErrorBar;
    yMin = min(yAll - eAll, [], 'omitnan');
    yMax = max(yAll + eAll, [], 'omitnan');

    if isfinite(yMin) && isfinite(yMax)
        pad = 0.08 * max(1, yMax - yMin);
        ylim([yMin - pad, yMax + pad]);
    end

    % ----------------------------
    % Save
    % ----------------------------
    if ~exist(resultsFolder, 'dir')
        mkdir(resultsFolder);
    end

    outFile = fullfile(resultsFolder, ...
        ['sag_depth_lines_singleplot' outputSuffix '_filtered.png']);

    exportgraphics(fig, outFile, 'Resolution', 300);
    fprintf('Figure saved: %s\n', outFile);

    % close(fig);
end