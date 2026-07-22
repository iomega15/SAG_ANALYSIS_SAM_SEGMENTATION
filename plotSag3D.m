function plotSag3D(T, resultsFolder, sagCol, labelStr, fileSuffix)
%PLOTSAG3D  Honest 3D bar (skyline) of membrane sag over the Width x Roof grid.
%
% Uses bar3, NOT surf. surf draws a continuous sheet and interpolates across
% the empty cells of this sparse grid, inventing spurious spikes/triangles.
% bar3 draws one discrete bar per cell — no interpolation, no invented
% geometry.
%
% Sag per cell uses the SAME channel-state classification as the qualitative
% heatmap (computeChannelStateMatrix), so the two figures agree:
%   Touchdown  -> 100%  (roof collapsed to the floor = full-height sag; there
%                        is no open lumen left to measure, but the sag IS 100%)
%   Open       -> median measured sag over the open (bright) replicates
%   Occluded / Not-Formed -> gap (no membrane sag defined)
% Bars are flat-colored by height (tall = yellow), matching the earlier
% surface look. Several view angles are written so a preferred one can be
% picked.

if nargin < 3 || isempty(sagCol),   sagCol = 'SagPct_ofMeasuredHeight'; end
if nargin < 4 || isempty(labelStr), labelStr = 'Sag (% of measured height)'; end
if nargin < 5,                      fileSuffix = ''; end

TOUCHDOWN_PCT = 100;   % a touchdown = the roof sagged its full height
% First row is the CANONICAL published view (az -45: staircase rises
% left->right, towers do not occlude the smaller bars). The rest are saved
% as _alt_az* alternates.
views = [ -45 30;
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
                    case 4                      % Touchdown -> full-height sag
                        M(ri, wi) = TOUCHDOWN_PCT;
                    case 3                      % Open -> measured median
                        sel  = subT.Width_px == widths(wi) & subT.Roof_layers == roofs(ri) ...
                             & strcmp(subT.LumenStatus, 'bright');
                        vals = subT.(sagCol)(sel);
                        vals = vals(~isnan(vals));
                        if ~isempty(vals), M(ri, wi) = max(0, median(vals)); end
                    otherwise                   % Occluded / Not-Formed -> gap
                        M(ri, wi) = NaN;
                end
            end
        end

        for v = 1:size(views, 1)
            fig = figure('Position', [100 100 1300 850], 'Color', 'w', 'Visible', 'off');
            ax  = axes(fig);
            b   = bar3(ax, M, 1);               % NaN bars are not drawn (gaps)

            % Flat-color every bar by its own height (tall -> yellow)
            for k = 1:numel(b)
                zd = b(k).ZData;
                cd = nan(size(zd));
                nb = size(zd, 1) / 6;           % bars in this series
                for bi = 1:nb
                    rows = (bi-1)*6 + (1:6);
                    cd(rows, :) = max(zd(rows, :), [], 'all');
                end
                b(k).CData = cd;
                b(k).FaceColor = 'flat';
                b(k).EdgeColor = [0.25 0.25 0.25];
                b(k).LineWidth = 0.25;
            end

            colormap(ax, parula);
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
                out = fullfile(resultsFolder, sprintf('sag_3Dbar_%s_H%d%s.png', ...
                    thisCond, thisH, fileSuffix));
            else          % alternate angles
                out = fullfile(resultsFolder, sprintf('sag_3Dbar_%s_H%d%s_alt_az%d.png', ...
                    thisCond, thisH, fileSuffix, round(views(v,1))));
            end
            exportgraphics(fig, out, 'Resolution', 300);
            fprintf('Saved: %s\n', out);
            close(fig);
        end
    end
end
end
