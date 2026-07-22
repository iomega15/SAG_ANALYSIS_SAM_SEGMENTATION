function plotLumenClassification(T, resultsFolder)
%PLOTLUMENCLASSIFICATION  3-panel scatter of lumen clustering results.
%
% Rewritten 2026-07-21: replaced gscatter (Statistics & Machine Learning
% Toolbox) with a plain per-class scatter loop, so the pipeline needs only
% Image Processing + Computer Vision toolboxes. The missing toolbox had
% aborted the run right before the classified heatmap and final CSV were
% saved on a machine without Statistics ML installed.

has_data = ~strcmp(T.LumenClass, 'no_data');
Tv = T(has_data, :);

if height(Tv) < 2
    warning('Not enough classified lumens to plot');
    return;
end

classNames = {'bright', 'dark', 'not_formed'};
colors = [0.2 0.8 0.2;    % bright      = green
          0.8 0.4 0.1;    % dark        = orange
          0.6 0.6 0.6];   % not_formed  = gray
markers = 'osd';

% Each panel: {xField, yField, xLabel, yLabel, title}
panels = { ...
    {'SAM_TextureRatio', 'SAM_ImfillScore', 'Texture Ratio (lumen / anchor)', 'Imfill Score', 'Formation vs Texture'}, ...
    {'PolarityScore',    'SAM_ImfillScore', 'Polarity Score (-1=dark, +1=bright)', 'Imfill Score', 'Polarity vs Formation'}, ...
    {'AreaRatio',        'SAM_TextureRatio', 'Area Ratio (lumen / anchor)', 'Texture Ratio', 'Size vs Texture'} };

fig = figure('Position', [100 100 1500 450], 'Visible', 'off');

for p = 1:numel(panels)
    subplot(1, 3, p); hold on;
    xv = Tv.(panels{p}{1});
    yv = Tv.(panels{p}{2});
    for c = 1:numel(classNames)
        sel = strcmp(Tv.LumenClass, classNames{c});
        if any(sel)
            scatter(xv(sel), yv(sel), 40, colors(c,:), markers(c), 'filled', ...
                'DisplayName', classNames{c});
        end
    end
    hold off;
    xlabel(panels{p}{3});
    ylabel(panels{p}{4});
    title(panels{p}{5});
    legend('Location', 'best');
end

sgtitle('Lumen Classification: Bright / Dark / Not Formed', 'FontSize', 13);

if nargin >= 2 && ~isempty(resultsFolder)
    exportgraphics(fig, fullfile(resultsFolder, 'lumen_classification.png'), 'Resolution', 150);
end
close(fig);
end
