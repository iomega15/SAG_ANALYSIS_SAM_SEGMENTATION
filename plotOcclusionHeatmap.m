function plotOcclusionHeatmap(T, resultsFolder, source)
%PLOTOCCLUSIONHEATMAP  Channel-state heatmap from SAM or classified labels.
%
%   plotOcclusionHeatmap(T, resultsFolder)           — auto-detect best source
%   plotOcclusionHeatmap(T, resultsFolder, 'sam')    — use raw SAM polarity
%   plotOcclusionHeatmap(T, resultsFolder, 'classified') — use post-hoc classification
%
% Sources:
%   'sam'        — Uses SAM_Polarity + SAM_LumenValid (per-image SAM output)
%   'classified' — Uses LumenStatus from classifyLumenFormation()
%   'auto'       — Uses 'classified' if available, otherwise falls back to 'sam'

    %% ================================================================
    %  RESOLVE SOURCE
    %  ================================================================
    if nargin < 3 || isempty(source)
        source = 'auto';
    end
    source = lower(source);

    has_classified = ismember('LumenStatus', T.Properties.VariableNames) && ...
                     any(~strcmp(T.LumenStatus, 'no_data'));
    has_sam        = ismember('SAM_Polarity', T.Properties.VariableNames) && ...
                     ismember('SAM_LumenValid', T.Properties.VariableNames);

    switch source
        case 'auto'
            if has_classified
                source = 'classified';
            elseif has_sam
                source = 'sam';
            else
                error('No valid source found. Run segmentLumenSAM2 or classifyLumenFormation first.');
            end
            fprintf('plotOcclusionHeatmap: auto-selected source = "%s"\n', source);

        case 'classified'
            if ~has_classified
                error('Source "classified" requested but LumenStatus column is missing or all no_data.');
            end

        case 'sam'
            if ~has_sam
                error('Source "sam" requested but SAM_Polarity / SAM_LumenValid columns are missing.');
            end

        otherwise
            error('Unknown source "%s". Use "sam", "classified", or "auto".', source);
    end

    %% ================================================================
    %  BUILD CANONICAL STATUS COLUMN
    %  ================================================================
    switch source
        case 'sam'
            statusCol = buildStatusFromSAM(T);
            titleSuffix = '(Raw SAM)';
            fileSuffix  = '_SAM';

        case 'classified'
            statusCol = buildStatusFromClassified(T);
            titleSuffix = '(Classified)';
            fileSuffix  = '_classified';
    end

    fprintf('\n=== plotOcclusionHeatmap [%s] ===\n', source);

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
    channelCode(isUnknown)  = 4;

    %% ================================================================
    %  PRINT SUMMARY
    %  ================================================================
    fprintf('\n=== CHANNEL CLASSIFICATION SUMMARY [%s] ===\n', source);
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
            subCodes = channelCode(mask);

            if isempty(subT) || height(subT) < 2
                continue;
            end

            widths     = sort(unique(subT.Width_px));
            roofLayers = sort(unique(subT.Roof_layers));
            nWidths    = numel(widths);
            nRoofs     = numel(roofLayers);

            codeMatrix  = nan(nRoofs, nWidths);
            countMatrix = zeros(nRoofs, nWidths);

            for i = 1:height(subT)
                wIdx = find(widths == subT.Width_px(i), 1);
                rIdx = find(roofLayers == subT.Roof_layers(i), 1);

                if ~isempty(wIdx) && ~isempty(rIdx)
                    codeMatrix(rIdx, wIdx)  = subCodes(i);
                    countMatrix(rIdx, wIdx) = countMatrix(rIdx, wIdx) + 1;
                end
            end

            %% --- Membrane-touchdown inference (physical, per roof row) ---
            % A "Not Formed" cell to the RIGHT of the last Open cell in the
            % same roof row cannot actually be unformed: at larger widths the
            % lumen is geometrically guaranteed to have formed (it lies beyond
            % the open band), so a non-detection there can only mean the
            % membrane sagged through the full channel height and contacted
            % the floor. Relabel those cells as code 5 = Membrane Touchdown
            % so the map distinguishes the sag-driven upper failure boundary
            % from the narrow-width formation-failure boundary.
            for ri = 1:nRoofs
                openCols = find(codeMatrix(ri, :) == 3);
                if isempty(openCols), continue; end
                for wi = (max(openCols)+1):nWidths
                    if codeMatrix(ri, wi) == 1
                        codeMatrix(ri, wi) = 5;
                    end
                end
            end

            %% --- Island ban (Roman, run-5 review) ---
            % The map should be continuous bands of one color — a connected
            % same-code region FULLY SURROUNDED by other codes is treated as
            % classification noise and recolored to the majority code of its
            % neighboring cells. EXCEPTION: a component touching the grid
            % border is KEPT — e.g. the purple touchdown block in the corner
            % is a real physical finding (membrane collapse), and the
            % top-border red island is ambiguous, so border-touchers are left
            % for the ordering rules below to resolve. Runs BEFORE the
            % monotone banding, per Roman's design.
            nIsland = 0;
            for pass = 1:4     % recoloring can create/merge islands; iterate briefly
                changedAny = false;
                for code = unique(codeMatrix(~isnan(codeMatrix)))'
                    CC = bwconncomp(codeMatrix == code, 4);
                    for k = 1:CC.NumObjects
                        [rr, cc] = ind2sub([nRoofs nWidths], CC.PixelIdxList{k});
                        if any(rr == 1 | rr == nRoofs | cc == 1 | cc == nWidths)
                            continue;   % touches border -> keep
                        end
                        comp = false(nRoofs, nWidths);
                        comp(CC.PixelIdxList{k}) = true;
                        ring = imdilate(comp, ones(3)) & ~comp;
                        ringCodes = codeMatrix(ring);
                        ringCodes = ringCodes(~isnan(ringCodes));
                        if isempty(ringCodes), continue; end
                        maj = mode(ringCodes);
                        if maj ~= code
                            codeMatrix(CC.PixelIdxList{k}) = maj;
                            nIsland = nIsland + numel(rr);
                            changedAny = true;
                        end
                    end
                end
                if ~changedAny, break; end
            end
            if nIsland > 0
                fprintf('  [%s H%d] island ban: recolored %d cell(s)\n', ...
                    thisCond, thisH, nIsland);
            end

            %% --- Monotone formation-stage banding (Roman, run-5 review) ---
            % Physics: as width grows, a channel progresses not-formed ->
            % occluded -> open, MONOTONICALLY, within a roof row. Therefore:
            % no red (F) right of yellow/green, no yellow/green left of the
            % red band, no green inside the yellow band. The two partial
            % rules used previously (no-open-left-of-band; ad-hoc) could not
            % guarantee this, so run 5 still showed F islands right of X and
            % X strays left of F. Enforce the ordering exactly: per row, fit
            % the maximum-agreement monotone partition  F* X* O*  over the
            % cells (touchdown cells, code 5, sit at the extreme right and
            % are excluded/kept; NaN cells skipped), then relabel every cell
            % to its fitted stage. This is the minimal set of relabelings
            % that satisfies the ordering, given the observed cells.
            nBanded = 0;
            for ri = 1:nRoofs
                rowCodes = codeMatrix(ri, :);
                fitIdx = find(~isnan(rowCodes) & rowCodes >= 1 & rowCodes <= 3);
                if numel(fitIdx) < 2, continue; end
                obs = rowCodes(fitIdx);
                n   = numel(obs);
                bestCost = inf;
                bestFit  = obs;
                for b1 = 0:n                    % cells 1..b1 -> F
                    for b2 = b1:n               % cells b1+1..b2 -> X, rest -> O
                        fit = [ones(1,b1), 2*ones(1,b2-b1), 3*ones(1,n-b2)];
                        cost = sum(fit ~= obs);
                        if cost < bestCost
                            bestCost = cost;
                            bestFit  = fit;
                        end
                    end
                end
                nBanded = nBanded + sum(bestFit ~= obs);
                codeMatrix(ri, fitIdx) = bestFit;
            end
            if nBanded > 0
                fprintf('  [%s H%d] monotone-stage banding: relabeled %d cell(s)\n', ...
                    thisCond, thisH, nBanded);
            end

            %% --- Draw figure ---
            fig = figure('Position', [100 100 1000 700], 'Color', 'w');

            % Master category table (code = row index). Colorbar shows only
            % the categories present in this particular grid.
            masterCmap = [
                1    0    0        % 1 = Failed             → red
                1    1    0        % 2 = Occluded           → yellow
                0    1    0        % 3 = Open               → green
                0.80 0.80 0.80     % 4 = Unknown            → gray
                0.55 0    0.85     % 5 = Membrane Touchdown → purple
            ];
            masterLabels = {'Not Formed','Occluded','Open','Unknown','Membrane Touchdown'};

            presentCodes = unique(codeMatrix(~isnan(codeMatrix)));

            imagesc(1:nWidths, 1:nRoofs, codeMatrix);
            colormap(masterCmap);
            caxis([1 5]);

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
                            case 4, txt = '?';
                            case 5, txt = 'T';   % membrane touchdown
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
            title(sprintf('%s — H=%d %s', thisCond, thisH, titleSuffix), ...
                  'FontSize', 14, 'FontWeight', 'bold');

            %% --- Save ---
            if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end

            outPng = fullfile(resultsFolder, ...
                sprintf('channel_state_heatmap_%s_H%d%s.png', thisCond, thisH, fileSuffix));
            outPdf = fullfile(resultsFolder, ...
                sprintf('heatmap_%s_H%d%s.pdf', thisCond, thisH, fileSuffix));

            exportgraphics(fig, outPng, 'Resolution', 600);
            exportgraphics(fig, outPdf, 'ContentType', 'vector');
            fprintf('Saved: %s\n', outPng);
            close(fig);
        end
    end
end

%% ====================================================================
%  HELPER: Build status from raw SAM polarity
%  ====================================================================
function statusCol = buildStatusFromSAM(T)
    statusCol = repmat({'failed'}, height(T), 1);
    for i = 1:height(T)
        if ~T.SAM_LumenValid(i)
            statusCol{i} = 'failed';
        else
            pol = T.SAM_Polarity{i};
            switch pol
                case 'bright'
                    statusCol{i} = 'open';
                case 'dark'
                    statusCol{i} = 'occluded';
                otherwise
                    statusCol{i} = 'failed';
            end
        end
    end
end

%% ====================================================================
%  HELPER: Build status from post-hoc classified labels
%  ====================================================================
function statusCol = buildStatusFromClassified(T)
    if ismember('LumenStatus', T.Properties.VariableNames)
        statusCol = T.LumenStatus;
    elseif ismember('LumenClass', T.Properties.VariableNames)
        % Fallback: translate LumenClass
        statusCol = T.LumenClass;
        statusCol = strrep(statusCol, 'bright',     'open');
        statusCol = strrep(statusCol, 'dark',        'occluded');
        statusCol = strrep(statusCol, 'not_formed',  'failed');
        statusCol = strrep(statusCol, 'no_data',     'failed');
    else
        error('No LumenStatus or LumenClass column found.');
    end

    % Normalize any unexpected values
    valid_statuses = {'open', 'occluded', 'failed', 'partial'};
    for i = 1:numel(statusCol)
        if ~ismember(statusCol{i}, valid_statuses)
            statusCol{i} = 'failed';
        end
    end
end