function plotLumenClassification(T, resultsFolder)
%PLOTLUMENCLASSIFICATION  3-panel scatter of lumen clustering results.

has_data = ~strcmp(T.LumenClass, 'no_data');
Tv = T(has_data, :);

if height(Tv) < 2
    warning('Not enough classified lumens to plot');
    return;
end

colors = [0.2 0.8 0.2;    % bright = green
          0.8 0.4 0.1;    % dark = orange
          0.6 0.6 0.6];   % not_formed = gray
markers = 'osd';

fig = figure('Position', [100 100 1500 450]);

subplot(1,3,1);
gscatter(Tv.SAM_TextureRatio, Tv.SAM_ImfillScore, ...
    Tv.LumenClass, colors, markers, 8);
xlabel('Texture Ratio (lumen / anchor)');
ylabel('Imfill Score');
title('Formation vs Texture');
legend('Location', 'best');

subplot(1,3,2);
gscatter(Tv.PolarityScore, Tv.SAM_ImfillScore, ...
    Tv.LumenClass, colors, markers, 8);
xlabel('Polarity Score (−1=dark, +1=bright)');
ylabel('Imfill Score');
title('Polarity vs Formation');
legend('Location', 'best');

subplot(1,3,3);
gscatter(Tv.AreaRatio, Tv.SAM_TextureRatio, ...
    Tv.LumenClass, colors, markers, 8);
xlabel('Area Ratio (lumen / anchor)');
ylabel('Texture Ratio');
title('Size vs Texture');
legend('Location', 'best');

sgtitle('Lumen Classification: Bright / Dark / Not Formed', 'FontSize', 13);

if nargin >= 2 && ~isempty(resultsFolder)
    saveas(fig, fullfile(resultsFolder, 'lumen_classification.png'));
end
end