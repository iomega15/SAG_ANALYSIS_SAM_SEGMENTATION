function plotSag3Dsurf(T, resultsFolder, sagCol, labelStr, fileSuffix)
%PLOTSAG3DSURF  3D SURFACE of membrane sag over the Width x Roof grid.
%
% Companion to plotSag3D (bar3). Same data and classification
% (computeChannelStateMatrix): Touchdown -> 100%, Open -> measured median,
% Occluded/Not-Formed -> NaN gap. Rendered as a semi-transparent surf with
% the measured grid points overlaid as scatter3 markers, using the jet
% colormap (blue 0 -> red 100).
%
% CAVEAT: surf INTERPOLATES between grid points, so the surface implies sag
% values that were not measured (e.g. a smooth ramp across the discrete
% Open->Touchdown collapse). Prefer plotSag3D (bar3) for the quantitative
% figure; this surface is the "smooth" alternative for illustration.

if nargin < 3 || isempty(sagCol),   sagCol = 'SagPct_ofMeasuredHeight'; end
if nargin < 4 || isempty(labelStr), labelStr = 'Sag (% of measured height)'; end
if nargin < 5,                      fileSuffix = ''; end

TOUCHDOWN_PCT = 100;
views = [ -45 30;      % canonical view first, then alternates
          130 30;
           45 30;
         -135 30;
           90 25 ];

conditions = unique(T.Condition);
heights    = unique(T.H_layers(~isnan(T.H_layers)));

for h = 1:numel(heights)
    for c = 1:numel(conditions)
        thisH = heights(h); thisCond = conditions{c};
        mask = (T.H_layers == thisH) & strcmp(T.Condition, thisCond);
        subT = T(mask, :);
        if height(subT) < 2, continue; end

        [codeMatrix, widths, roofs] = computeChannelStateMatrix(subT);
        M = nan(numel(roofs), numel(widths));
        for wi = 1:numel(widths)
            for ri = 1:numel(roofs)
                switch codeMatrix(ri, wi)
                    case 4
                        M(ri, wi) = TOUCHDOWN_PCT;
                    case 3
                        sel  = subT.Width_px == widths(wi) & subT.Roof_layers == roofs(ri) ...
                             & strcmp(subT.LumenStatus, 'bright');
                        vals = subT.(sagCol)(sel);
                        vals = vals(~isnan(vals));
                        if ~isempty(vals), M(ri, wi) = max(0, median(vals)); end
                end
            end
        end

        [WW, RR] = meshgrid(1:numel(widths), 1:numel(roofs));
        for v = 1:size(views, 1)
            fig = figure('Position', [100 100 1300 850], 'Color', 'w', 'Visible', 'off');
            ax  = axes(fig);
            surf(ax, WW, RR, M, 'FaceColor', 'interp', 'EdgeColor', [0.3 0.3 0.3], ...
                'FaceAlpha', 0.6);   % semi-transparent, matching the reference
            hold(ax, 'on');
            good = ~isnan(M);
            scatter3(ax, WW(good), RR(good), M(good), 22, [0.1 0.35 0.9], 'filled', ...
                'MarkerEdgeColor', [0.05 0.15 0.4]);
            hold(ax, 'off');

            colormap(ax, jet);
            caxis(ax, [0 TOUCHDOWN_PCT]); zlim(ax, [0 TOUCHDOWN_PCT]);
            cb = colorbar(ax); cb.Label.String = labelStr; cb.FontWeight = 'bold'; cb.FontSize = 11;

            set(ax, 'XTick', 1:numel(widths), 'XTickLabel', arrayfun(@num2str, widths, 'Uni', 0));
            set(ax, 'YTick', 1:numel(roofs),  'YTickLabel', arrayfun(@num2str, roofs, 'Uni', 0));
            if numel(widths) > 15, xtickangle(ax, 45); end
            xlabel(ax, 'Width (printer px, 1 px = 32 \mum)', 'FontSize', 12, 'FontWeight', 'bold');
            ylabel(ax, 'Roof thickness (# layers, 1 = 50 \mum)', 'FontSize', 12, 'FontWeight', 'bold');
            zlabel(ax, labelStr, 'FontSize', 12, 'FontWeight', 'bold');
            set(ax, 'FontWeight', 'bold', 'FontSize', 11);
            view(ax, views(v, 1), views(v, 2));
            grid(ax, 'on');

            if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end
            if v == 1     % canonical published view
                out = fullfile(resultsFolder, sprintf('sag_3Dsurf_%s_H%d%s.png', ...
                    thisCond, thisH, fileSuffix));
            else          % alternate angles
                out = fullfile(resultsFolder, sprintf('sag_3Dsurf_%s_H%d%s_alt_az%d.png', ...
                    thisCond, thisH, fileSuffix, round(views(v,1))));
            end
            exportgraphics(fig, out, 'Resolution', 300);
            fprintf('Saved: %s\n', out);
            close(fig);
        end
    end
end
end
