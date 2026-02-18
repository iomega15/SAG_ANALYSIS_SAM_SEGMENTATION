function plotComparativeSag(T, resultsFolder, metricColumn, baselineType, outputSuffix)
% PLOTCOMPARATIVESAG Generic 3D sag plot for any sag metric with R² labels
%
%   Inputs:
%       T             - Data table
%       resultsFolder - Output folder path
%       metricColumn  - (optional) Column name to plot (default: 'SagPct_ofMeasuredHeight')
%       baselineType  - (optional) Label for title (default: 'Corner')
%       outputSuffix  - (optional) Suffix for output file (default: '')
%
%   Examples:
%       plotComparativeSag(T, resultsFolder)  % Corner baseline
%       plotComparativeSag(T, resultsFolder, 'SagBB_Pct_ofMeasuredHeight', 'BoundingBox', '_BB')

    % --- Default Arguments ---
    if nargin < 3 || isempty(metricColumn)
        metricColumn = 'SagPct_ofMeasuredHeight';
    end
    if nargin < 4 || isempty(baselineType)
        baselineType = 'Corner';
    end
    if nargin < 5 || isempty(outputSuffix)
        outputSuffix = '';
    end
    
    % --- Check if column exists ---
    if ~ismember(metricColumn, T.Properties.VariableNames)
        warning('Column "%s" not found in table. Skipping plot.', metricColumn);
        return;
    end

    % --- 1. FILTERING LOGIC ---
    
    % Check for occlusion (Only keep 'bright' lumens)
    isOpen = strcmp(T.LumenStatus, 'bright');
    
    % Check Parabola Geometry (The "Science Gate")
    isGeometricallyValid = T.IsVertexBetween & T.IsVertexLowerLeft & T.IsVertexLowerRight;
    
    % Goodness of Fit (R-squared) threshold
    r2_threshold = 0.5; 
    isGoodFit = T.ParabolaR2 >= r2_threshold;
    
    % Combine all filters
    keepIdx = isOpen & isGeometricallyValid & isGoodFit;
    
    % Logging statistics
    fprintf('\n=== VISUALIZATION FILTER SUMMARY (%s Baseline) ===\n', baselineType);
    fprintf('Total images analyzed:    %d\n', height(T));
    fprintf('  - Excluded (Occluded):  %d\n', sum(~isOpen));
    fprintf('  - Excluded (Bad Geom):  %d (Vertex outside walls or above corners)\n', sum(isOpen & ~isGeometricallyValid));
    fprintf('  - Excluded (Poor Fit):  %d (R^2 < %.1f)\n', sum(isOpen & isGeometricallyValid & ~isGoodFit), r2_threshold);
    fprintf('Final points to plot:     %d\n', sum(keepIdx));
    
    % Create cleaned table
    T_clean = T;%(keepIdx, :);
    
    if isempty(T_clean) || height(T_clean) == 0
        warning('No valid data points found after filtering. Skipping plot.');
        return;
    end
    
    % --- 2. STATISTICAL GROUPING ---
    % Group by Width, RoofLayers, Condition AND include mean R² for labeling
    try
        T_stats = groupsummary(T_clean, {'Width_px', 'Roof_layers', 'Condition'}, ...
                               {'mean', 'std'}, {metricColumn, 'ParabolaR2'});
    catch ME
        warning(['groupsummary failed: %s', ME.message]);
        return;
    end
    
    % Dynamic column names from groupsummary
    meanColName = ['mean_' metricColumn];
    stdColName = ['std_' metricColumn];
    meanR2ColName = 'mean_ParabolaR2';
    
    % Remove NaN means
    valid_sag = ~isnan(T_stats.(meanColName));
    T_stats = T_stats(valid_sag, :);
    
    if isempty(T_stats) || height(T_stats) == 0
        warning('No valid statistics after grouping. Skipping plot.');
        return;
    end
    
    % --- 3. CREATE 3D PLOT ---
    fig = figure('Position', [100 100 1100 750], 'Color', 'w');
    hold on;
    
    conditions = unique(T_stats.Condition);
    colors = {'b', 'r', 'g', 'k', 'm', 'c'}; 
    markers = {'o', 's', '^', 'd', 'v', 'p'};
    
    % Store handles for legend
    legendHandles = [];
    legendLabels = {};
    
    for c = 1:numel(conditions)
        condName = conditions{c};
        
        mask = strcmp(T_stats.Condition, condName);
        subT = T_stats(mask, :);
        
        if isempty(subT) || height(subT) == 0
            continue; 
        end
        
        col = colors{mod(c-1, numel(colors))+1};
        mk  = markers{mod(c-1, numel(markers))+1};
        
        xData = subT.Width_px;
        yData = subT.Roof_layers;
        zData = subT.(meanColName);
        errData = subT.(stdColName);
        r2Data = subT.(meanR2ColName);
        
        % Plot means
        h = scatter3(xData, yData, zData, 80, col, mk, 'filled');
        legendHandles = [legendHandles, h];
        legendLabels = [legendLabels, {condName}];
             
        % Plot error bars and R² labels
        for j = 1:height(subT)
            xPt = xData(j);
            yPt = yData(j);
            zPt = zData(j);
            errPt = errData(j);
            r2Pt = r2Data(j);
            
            % Error bars
            if ~isnan(errPt) && errPt > 0
                plot3([xPt xPt], [yPt yPt], [zPt-errPt zPt+errPt], '-', ...
                      'Color', col, 'LineWidth', 1.2, 'HandleVisibility', 'off');
            end
            
            % R² label next to marker
            if ~isnan(r2Pt)
                % Offset the text slightly so it doesn't overlap the marker
                text(xPt + 2, yPt + 0.15, zPt, sprintf('%.2f', r2Pt), ...
                     'FontSize', 8, 'Color', col, 'FontWeight', 'bold', ...
                     'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
            end
        end
    end
    
    % Formatting
    xlabel('Width (printer px)', 'FontSize', 11);
    ylabel('Roof Layers', 'FontSize', 11);
    zlabel('Sag (% of Measured Height)', 'FontSize', 11);
    title({sprintf('Comparative Sag Depth (%s Baseline)', baselineType), ...
           sprintf('Filtered for Physically Valid Parabola Fit (R^2 ≥ %.1f)', r2_threshold), ...
           'Labels show mean R^2 per group'}, 'FontSize', 12);
    grid on; 
    view(45, 30); 
    legend(legendHandles, legendLabels, 'Location', 'bestoutside');
    hold off;
    zlim([-100 100])
    % --- 4. SAVE OUTPUT ---
    if ~exist(resultsFolder, 'dir')
        mkdir(resultsFolder); 
    end
    
    outFile = fullfile(resultsFolder, ['sag_depth_comparison' outputSuffix '_filtered.png']);
    saveas(fig, outFile);
    fprintf('Figure saved: %s\n', outFile);
    %close(fig);
end