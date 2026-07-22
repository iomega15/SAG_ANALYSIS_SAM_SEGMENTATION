function plotOcclusionHeatmap(T, resultsFolder)
%PLOTOCCLUSIONHEATMAP  Channel-state map: Not-Formed / Occluded / Open / Touchdown.
%
%   plotOcclusionHeatmap(T, resultsFolder)
%
% Per-cell state comes straight from the per-image SAM result
% (SAM_LumenValid + SAM_Polarity): valid+bright -> Open, valid+dark ->
% Occluded, else -> Not-Formed. Membrane Touchdown (wide + thin-membrane
% collapse) is inferred at the map level by the 4-stage monotone banding
% below. One map per (Condition, H). (The former 'sam' vs 'classified'
% sources were removed: the classification stage had degenerated into an
% identical passthrough of the SAM result.)

    statusCol = buildStatusFromSAM(T);

    fprintf('\n=== plotOcclusionHeatmap ===\n');

    %% ================================================================
    %  ASSIGN NUMERIC CODES
    %  ================================================================
    isFailed   = strcmp(statusCol, 'failed');
    isOccluded = strcmp(statusCol, 'occluded') | strcmp(statusCol, 'partial');
    isOpen     = strcmp(statusCol, 'open');
    isUnknown  = ~(isFailed | isOccluded | isOpen);

    channelCode = nan(height(T), 1);
    channelCode(isFailed)   = 1;
    channelCode(isOccluded) = 2;
    channelCode(isOpen)     = 3;
    channelCode(isUnknown)  = 1;   % unrecognized status -> not-formed (never occurs
                                   % in practice; keeps code 4 free for Touchdown)

    %% ================================================================
    %  PRINT SUMMARY
    %  ================================================================
    fprintf('\n=== CHANNEL STATE SUMMARY ===\n');
    fprintf('Total samples:      %d\n', height(T));
    fprintf('  Not Formed:       %d (%.1f%%)\n', sum(isFailed),   100*sum(isFailed)/height(T));
    fprintf('  Occluded:         %d (%.1f%%)\n', sum(isOccluded), 100*sum(isOccluded)/height(T));
    fprintf('  Open:             %d (%.1f%%)\n', sum(isOpen),     100*sum(isOpen)/height(T));
    fprintf('  Unknown:          %d (%.1f%%)\n', sum(isUnknown),  100*sum(isUnknown)/height(T));

    if sum(isUnknown) > 0
        unknownStatuses = unique(statusCol(isUnknown));
        fprintf('  Unknown statuses found:\n');
        for u = 1:numel(unknownStatuses)
            fprintf('    "%s": %d\n', unknownStatuses{u}, ...
                sum(strcmp(statusCol, unknownStatuses{u})));
        end
    end

    %% ================================================================
    %  GENERATE HEATMAPS
    %  ================================================================
    conditions = unique(T.Condition);
    heights    = unique(T.H_layers(~isnan(T.H_layers)));

    for h = 1:numel(heights)
        for c = 1:numel(conditions)
            thisH    = heights(h);
            thisCond = conditions{c};

            mask = (T.H_layers == thisH) & strcmp(T.Condition, thisCond);
            subT = T(mask, :);

            if isempty(subT) || height(subT) < 2
                continue;
            end

            % Banded channel-state grid (Not-Formed/Occluded/Open/Touchdown).
            % Shared with the sag figures so touchdown is classified identically.
            [codeMatrix, widths, roofLayers, countMatrix] = computeChannelStateMatrix(subT);
            nWidths = numel(widths);
            nRoofs  = numel(roofLayers);

            %% --- Draw figure ---
            fig = figure('Position', [100 100 1000 700], 'Color', 'w');

            % Master category table (code = row index). Colorbar shows only
            % the categories present in this particular grid.
            masterCmap = [
                1    0    0        % 1 = Not Formed          → red
                1    1    0        % 2 = Occluded            → yellow
                0    1    0        % 3 = Open                → green
                0.55 0    0.85     % 4 = Membrane Touchdown  → purple
            ];
            masterLabels = {'Not Formed','Occluded','Open','Touchdown'};

            presentCodes = unique(codeMatrix(~isnan(codeMatrix)));

            imagesc(1:nWidths, 1:nRoofs, codeMatrix);
            colormap(masterCmap);
            caxis([1 4]);

            cb = colorbar;
            cb.FontWeight = 'bold';
            cb.FontSize   = 11;
            cb.Ticks      = presentCodes;
            cb.TickLabels = masterLabels(presentCodes);

            set(gca, 'XTick', 1:nWidths, ...
                     'XTickLabel', arrayfun(@num2str, widths, 'Uni', false));
            set(gca, 'YTick', 1:nRoofs, ...
                     'YTickLabel', arrayfun(@num2str, roofLayers, 'Uni', false));
            set(gca, 'YDir', 'normal');
            set(gca, 'FontWeight', 'bold', 'FontSize', 11, 'LineWidth', 1.2);

            if nWidths > 15
                xtickangle(45);
            end

            %% --- Cell annotations ---
            for ri = 1:nRoofs
                for wi = 1:nWidths
                    val = codeMatrix(ri, wi);
                    n   = countMatrix(ri, wi);

                    if isnan(val)
                        txt = '';
                    else
                        switch val
                            case 1, txt = 'F';
                            case 2, txt = 'X';
                            case 3, txt = 'O';
                            case 4, txt = 'T';   % membrane touchdown
                            otherwise, txt = '?';
                        end
                    end

                    if ~isempty(txt)
                        % Outline effect
                        dx = 0.025; dy = 0.025;
                        offsets = [-dx 0; dx 0; 0 -dy; 0 dy; ...
                                   -dx -dy; -dx dy; dx -dy; dx dy];
                        for kk = 1:size(offsets,1)
                            text(wi + offsets(kk,1), ri + offsets(kk,2), txt, ...
                                'HorizontalAlignment', 'center', ...
                                'VerticalAlignment', 'middle', ...
                                'FontWeight', 'bold', 'FontSize', 10, 'Color', 'k');
                        end
                        text(wi, ri, txt, ...
                            'HorizontalAlignment', 'center', ...
                            'VerticalAlignment', 'middle', ...
                            'FontWeight', 'bold', 'FontSize', 10, 'Color', 'w');
                    end

                    if n > 1
                        text(wi, ri - 0.35, sprintf('n=%d', n), ...
                            'HorizontalAlignment', 'center', ...
                            'FontSize', 7, 'FontWeight', 'bold', ...
                            'Color', [0.2 0.2 0.2]);
                    end
                end
            end

            xlabel('Width (printer px, 1 px = 32 \mum)', 'FontSize', 13, 'FontWeight', 'bold');
            ylabel('Roof thickness (layers, 1 layer = 50 \mum)', 'FontSize', 13, 'FontWeight', 'bold');
            % (no title — single-condition, single-height figure; condition/H
            % are stated in the caption. Was 'Default — H=5'.)

            %% --- Save ---
            if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end

            outPng = fullfile(resultsFolder, ...
                sprintf('channel_state_heatmap_%s_H%d.png', thisCond, thisH));
            outPdf = fullfile(resultsFolder, ...
                sprintf('heatmap_%s_H%d.pdf', thisCond, thisH));

            exportgraphics(fig, outPng, 'Resolution', 600);
            exportgraphics(fig, outPdf, 'ContentType', 'vector');
            fprintf('Saved: %s\n', outPng);
            close(fig);
        end
    end
end
