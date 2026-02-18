function plotWallTilt(T, resultsDir)
% PLOTWALLTILT Plots the average inward lean of the channel walls.
% Inputs:
%   T          - Data table
%   resultsDir - Path to the results subfolder

    % 1. Filter: Open lumens and reasonable fits
    isOpen = strcmp(T.LumenStatus, 'bright');
    r2_threshold = 0.6;
    isGoodFit = T.ParabolaR2 > r2_threshold;
    
    keepIdx = isOpen & isGoodFit;
    T_plot = T(keepIdx, :);
    
    if isempty(T_plot), return; end

    % 2. Group Stats
    T_stats = groupsummary(T_plot, {'Width_px', 'Roof_layers', 'Condition'}, ...
                           {'mean', 'std'}, 'AvgWallTiltAngle_deg');
    T_stats = T_stats(~isnan(T_stats.mean_AvgWallTiltAngle_deg), :);

    % 3. Plot
    fig = figure('Position', [150 150 1000 700]);
    hold on;
    conditions = unique(T_stats.Condition);
    colors = {'b', 'r', 'g', 'k'}; markers = {'o', 's', '^', 'd'};

    for c = 1:numel(conditions)
        condName = conditions{c};
        mask = strcmp(T_stats.Condition, condName);
        subT = T_stats(mask, :);
        if isempty(subT), continue; end
        
        col = colors{mod(c-1, numel(colors))+1};
        mk  = markers{mod(c-1, numel(markers))+1};
        
        scatter3(subT.Width_px, subT.Roof_layers, subT.mean_AvgWallTiltAngle_deg, ...
                 80, col, mk, 'filled', 'DisplayName', condName);
             
        % Error bars
        for j = 1:height(subT)
            x = subT.Width_px(j); y = subT.Roof_layers(j); z = subT.mean_AvgWallTiltAngle_deg(j);
            err = subT.std_AvgWallTiltAngle_deg(j);
            if ~isnan(err) && err > 0
                plot3([x x], [y y], [z-err z+err], '-', 'Color', col, 'HandleVisibility', 'off');
            end
        end
    end

    xlabel('Width (printer px)'); ylabel('Roof Layers'); zlabel('Wall Tilt (degrees)');
    title('Lumen Integrity: Wall Inward Tilt');
    grid on; view(45, 30); legend('show');
    hold off;

    % 4. Save
    saveas(fig, fullfile(resultsDir, 'wall_tilt_comparison.png'));
end