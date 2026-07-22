function plotSagHeatmap(T, resultsFolder, sagCol, labelStr, fileSuffix)
%PLOTSAGHEATMAP  2D heatmap of mean membrane sag over the Width x Roof grid.
%
% Each cell = mean over the TRUSTWORTHY replicates of sagCol (a percentage;
% NaN replicates are excluded). Cells with no trustworthy measurement are
% drawn gray. This replaces the 3D sag surface, which (a) was hard to read
% off exact values, (b) interpolated a surface between sparse points, and
% (c) fabricated 100% sag at missing wide-width groups (plotComparativeSag's
% override). Here nothing is invented: a cell is either a real mean or gray.

if nargin < 3 || isempty(sagCol),    sagCol = 'SagBB_Pct_ofMeasuredHeight'; end
if nargin < 4 || isempty(labelStr),  labelStr = 'Sag (% of measured height)'; end
if nargin < 5,                       fileSuffix = ''; end

conditions = unique(T.Condition);
heights    = unique(T.H_layers(~isnan(T.H_layers)));

for h = 1:numel(heights)
    for c = 1:numel(conditions)
        thisH = heights(h); thisCond = conditions{c};
        mask = (T.H_layers == thisH) & strcmp(T.Condition, thisCond);
        subT = T(mask, :);
        if height(subT) < 2, continue; end

        % Same channel-state classification as the qualitative heatmap, so the
        % figures agree: Touchdown -> 100% (full-height collapse), Open ->
        % measured median sag, Occluded/Not-Formed -> gray (no sag defined).
        [codeMatrix, widths, roofs] = computeChannelStateMatrix(subT);
        M = nan(numel(roofs), numel(widths));
        for wi = 1:numel(widths)
            for ri = 1:numel(roofs)
                switch codeMatrix(ri, wi)
                    case 4
                        M(ri, wi) = 100;   % touchdown = full-height sag
                    case 3
                        sel  = subT.Width_px == widths(wi) & subT.Roof_layers == roofs(ri) ...
                             & strcmp(subT.LumenStatus, 'bright');
                        vals = subT.(sagCol)(sel);
                        vals = vals(~isnan(vals));
                        if ~isempty(vals), M(ri, wi) = max(0, median(vals)); end
                end
            end
        end

        fig = figure('Position', [100 100 1150 650], 'Color', 'w', 'Visible', 'off');
        ax  = axes(fig);
        im  = imagesc(ax, 1:numel(widths), 1:numel(roofs), M);
        set(im, 'AlphaData', ~isnan(M));      % NaN -> transparent
        set(ax, 'Color', [0.82 0.82 0.82]);   % ...showing the gray axes bg
        colormap(ax, parula);
        cmax = max([1, ceil(max(M(~isnan(M))))]);
        caxis(ax, [0 cmax]);

        cb = colorbar(ax); cb.Label.String = labelStr;
        cb.FontWeight = 'bold'; cb.FontSize = 11;

        set(ax, 'XTick', 1:numel(widths), 'XTickLabel', arrayfun(@num2str, widths, 'Uni', 0));
        set(ax, 'YTick', 1:numel(roofs),  'YTickLabel', arrayfun(@num2str, roofs, 'Uni', 0));
        set(ax, 'YDir', 'normal', 'FontWeight', 'bold', 'FontSize', 11, 'LineWidth', 1.2);
        if numel(widths) > 15, xtickangle(ax, 45); end
        xlabel(ax, 'Width (printer px, 1 px = 32 \mum)', 'FontSize', 13, 'FontWeight', 'bold');
        ylabel(ax, 'Roof thickness (layers, 1 layer = 50 \mum)', 'FontSize', 13, 'FontWeight', 'bold');

        for ri = 1:numel(roofs)
            for wi = 1:numel(widths)
                if ~isnan(M(ri, wi))
                    text(ax, wi, ri, sprintf('%.0f', M(ri, wi)), ...
                        'HorizontalAlignment', 'center', 'FontSize', 8, ...
                        'FontWeight', 'bold', 'Color', 'k');
                end
            end
        end

        if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end
        out = fullfile(resultsFolder, sprintf('sag_heatmap_%s_H%d%s.png', thisCond, thisH, fileSuffix));
        exportgraphics(fig, out, 'Resolution', 300);
        fprintf('Saved: %s\n', out);
        close(fig);
    end
end
end
