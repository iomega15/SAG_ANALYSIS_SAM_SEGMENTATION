function plotSag3D(T, resultsFolder, sagCol, labelStr, fileSuffix)
%PLOTSAG3D  Honest 3D surface of mean membrane sag over the Width x Roof grid.
%
% Same real grid as plotSagHeatmap (mean over the trustworthy replicates of
% sagCol). NO fabricated values (unlike the retired plotComparativeSag, which
% inserted 100% sag at missing wide-width groups) and NO extrapolation: cells
% with no valid lumen are left as NaN gaps in the surface. Gives the 3D
% "impact" look without inventing data.

if nargin < 3 || isempty(sagCol),   sagCol = 'SagBB_Pct_ofMeasuredHeight'; end
if nargin < 4 || isempty(labelStr), labelStr = 'Sag (% of measured height)'; end
if nargin < 5,                      fileSuffix = ''; end

conditions = unique(T.Condition);
heights    = unique(T.H_layers(~isnan(T.H_layers)));

for h = 1:numel(heights)
    for c = 1:numel(conditions)
        thisH = heights(h); thisCond = conditions{c};
        mask = (T.H_layers == thisH) & strcmp(T.Condition, thisCond);
        subT = T(mask, :);
        if height(subT) < 2, continue; end

        widths = sort(unique(subT.Width_px));
        roofs  = sort(unique(subT.Roof_layers));
        M = nan(numel(roofs), numel(widths));
        for wi = 1:numel(widths)
            for ri = 1:numel(roofs)
                sel  = subT.Width_px == widths(wi) & subT.Roof_layers == roofs(ri);
                vals = subT.(sagCol)(sel);
                vals = vals(~isnan(vals));
                if ~isempty(vals), M(ri, wi) = median(vals); end
            end
        end
        M = max(M, 0);

        [WW, RR] = meshgrid(widths, roofs);
        fig = figure('Position', [100 100 1200 800], 'Color', 'w', 'Visible', 'off');
        ax  = axes(fig);
        surf(ax, WW, RR, M, 'EdgeColor', [0.35 0.35 0.35], 'FaceAlpha', 0.92);
        hold(ax, 'on');
        good = ~isnan(M);
        scatter3(ax, WW(good), RR(good), M(good), 28, M(good), 'filled', ...
            'MarkerEdgeColor', [0.15 0.15 0.15]);
        hold(ax, 'off');

        colormap(ax, parula);
        cmax = max([1, ceil(max(M(good)))]);
        caxis(ax, [0 cmax]); zlim(ax, [0 cmax]);
        cb = colorbar(ax); cb.Label.String = labelStr; cb.FontWeight = 'bold';

        xlabel(ax, 'Width (printer px, 1 px = 32 \mum)', 'FontSize', 12, 'FontWeight', 'bold');
        ylabel(ax, 'Roof thickness (# layers, 1 = 50 \mum)', 'FontSize', 12, 'FontWeight', 'bold');
        zlabel(ax, labelStr, 'FontSize', 12, 'FontWeight', 'bold');
        set(ax, 'FontWeight', 'bold', 'FontSize', 11);
        view(ax, 45, 28);
        grid(ax, 'on');

        if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end
        out = fullfile(resultsFolder, sprintf('sag_3Dsurface_%s_H%d%s.png', thisCond, thisH, fileSuffix));
        exportgraphics(fig, out, 'Resolution', 300);
        fprintf('Saved: %s\n', out);
        close(fig);
    end
end
end
