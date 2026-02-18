function plotOcclusionHeatmap(T, resultsFolder)
% PLOTOCCLUSIONHEATMAP Heatmap showing channel states:
%   - Open (bright): Score = 1, GREEN
%   - Occluded (dark): Score = 0, RED
%   - Other (unknown/error): Not scored, shown as GRAY with '?' for debugging

    % =====================================================================
    % CLASSIFICATION LOGIC
    % =====================================================================
    
    isBright = strcmp(T.LumenStatus, 'bright');
    isDark = strcmp(T.LumenStatus, 'dark');
    isOther = ~isBright & ~isDark;
    
    % Score: 1 = bright (open), 0 = dark (occluded), NaN = other (unscored)
    channelScore = nan(height(T), 1);
    channelScore(isBright) = 1;
    channelScore(isDark) = 0;
    % isOther stays NaN (will be shown as gray '?' for debugging)
    
    T.ChannelScore = channelScore;
    
    % Log classification summary
    fprintf('\n=== CHANNEL CLASSIFICATION SUMMARY ===\n');
    fprintf('Total samples:     %d\n', height(T));
    fprintf('  Open (bright):   %d (%.1f%%)\n', sum(isBright), 100*sum(isBright)/height(T));
    fprintf('  Occluded (dark): %d (%.1f%%)\n', sum(isDark), 100*sum(isDark)/height(T));
    fprintf('  Other/Unknown:   %d (%.1f%%) <- DEBUG: check these\n', sum(isOther), 100*sum(isOther)/height(T));
    
    if any(isOther)
        fprintf('\n  Other statuses found:\n');
        otherStatuses = unique(T.LumenStatus(isOther));
        for s = 1:numel(otherStatuses)
            cnt = sum(strcmp(T.LumenStatus, otherStatuses{s}));
            fprintf('    "%s": %d\n', otherStatuses{s}, cnt);
        end
    end
    
    % =====================================================================
    % GENERATE HEATMAPS
    % =====================================================================
    
    conditions = unique(T.Condition);
    heights = unique(T.H_layers(~isnan(T.H_layers)));
    
    for h = 1:numel(heights)
        for c = 1:numel(conditions)
            thisH = heights(h);
            thisCond = conditions{c};
            
            % Filter data
            mask = (T.H_layers == thisH) & strcmp(T.Condition, thisCond);
            subT = T(mask, :);
            
            if isempty(subT) || height(subT) < 2
                continue;
            end
            
            % Get unique widths and roof layers (SORTED)
            widths = sort(unique(subT.Width_px));
            roofLayers = sort(unique(subT.Roof_layers));
            
            nWidths = numel(widths);
            nRoofs = numel(roofLayers);
            
            % Create matrices
            scoreMatrix = nan(nRoofs, nWidths);
            countMatrix = zeros(nRoofs, nWidths);
            hasOtherMatrix = false(nRoofs, nWidths);  % Track if any 'other' status
            
            for i = 1:height(subT)
                wIdx = find(widths == subT.Width_px(i), 1);
                rIdx = find(roofLayers == subT.Roof_layers(i), 1);
                
                if ~isempty(wIdx) && ~isempty(rIdx)
                    scoreValue = subT.ChannelScore(i);
                    
                    if isnan(scoreValue)
                        % Mark this cell as having 'other' status
                        hasOtherMatrix(rIdx, wIdx) = true;
                    else
                        if isnan(scoreMatrix(rIdx, wIdx))
                            scoreMatrix(rIdx, wIdx) = scoreValue;
                            countMatrix(rIdx, wIdx) = 1;
                        else
                            % Running average for replicates
                            n = countMatrix(rIdx, wIdx);
                            scoreMatrix(rIdx, wIdx) = (scoreMatrix(rIdx, wIdx) * n + scoreValue) / (n + 1);
                            countMatrix(rIdx, wIdx) = n + 1;
                        end
                    end
                end
            end
            
            % Create display matrix (NaN -> 0.5 for gray display)
            displayMatrix = scoreMatrix;
            displayMatrix(isnan(displayMatrix) & hasOtherMatrix) = 0.5;  % Gray for 'other'
            
            % Create figure
            fig = figure('Position', [100 100 1000 700], 'Color', 'w');
            
            % Custom colormap: Red (0) -> Gray (0.5) -> Green (1)
            nColors = 256;
            cmap = zeros(nColors, 3);
            for i = 1:nColors
                t = (i-1) / (nColors-1);  % 0 to 1
                if t < 0.4
                    % Red (occluded / dark)
                    cmap(i, :) = [0.85, 0.2, 0.2];
                elseif t > 0.6
                    % Green (open / bright)
                    cmap(i, :) = [0.2, 0.75, 0.2];
                else
                    % Gray (other / unknown - for debugging)
                    cmap(i, :) = [0.6, 0.6, 0.6];
                end
            end
            
            % Plot heatmap
            imagesc(1:nWidths, 1:nRoofs, displayMatrix);
            colormap(cmap);
            caxis([0 1]);
            
            % Colorbar
            cb = colorbar;
            cb.Label.String = 'Channel State';
            cb.Ticks = [0, 0.5, 1];
            cb.TickLabels = {'Occluded', 'Unknown', 'Open'};
            
            % Set axis labels
            set(gca, 'XTick', 1:nWidths);
            set(gca, 'XTickLabel', arrayfun(@num2str, widths, 'UniformOutput', false));
            set(gca, 'YTick', 1:nRoofs);
            set(gca, 'YTickLabel', arrayfun(@num2str, roofLayers, 'UniformOutput', false));
            set(gca, 'YDir', 'normal');
            
            if nWidths > 15
                xtickangle(45);
            end
            
            % Add text annotations
            for ri = 1:nRoofs
                for wi = 1:nWidths
                    val = scoreMatrix(ri, wi);
                    n = countMatrix(ri, wi);
                    hasOther = hasOtherMatrix(ri, wi);
                    
                    if ~isnan(val)
                        % Has valid score
                        if val > 0.75
                            txt = 'O';      % Open
                            clr = 'w';
                        elseif val < 0.25
                            txt = 'X';      % Occluded
                            clr = 'w';
                        else
                            % Mixed replicates
                            txt = sprintf('%.0f%%', val * 100);
                            clr = 'k';
                        end
                    elseif hasOther
                        % Only has 'other' status (unknown/error)
                        txt = '?';
                        clr = 'w';
                    else
                        % No data
                        txt = '';
                        clr = 'k';
                    end
                    
                    if ~isempty(txt)
                        text(wi, ri, txt, ...
                             'HorizontalAlignment', 'center', ...
                             'VerticalAlignment', 'middle', ...
                             'FontWeight', 'bold', 'FontSize', 9, 'Color', clr);
                    end
                    
                    % Show replicate count if > 1
                    if n > 1
                        text(wi, ri - 0.35, sprintf('n=%d', n), ...
                             'HorizontalAlignment', 'center', ...
                             'FontSize', 7, 'Color', [0.2 0.2 0.2]);
                    end
                end
            end
            
            xlabel('Width (printer px)', 'FontSize', 12);
            ylabel('Roof Layers', 'FontSize', 12);
            title(sprintf('Channel State Map: %s | H = %d layers\nO=Open, X=Occluded, ?=Unknown (debug)', ...
                  thisCond, thisH), 'FontSize', 12);
            grid on;
            
            % Save
            if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end
            outFile = fullfile(resultsFolder, sprintf('channel_state_heatmap_%s_H%d.png', thisCond, thisH));
            saveas(fig, outFile);
            fprintf('Saved: %s\n', outFile);
            %close(fig);
        end
    end
end