function fig = plotLumenQualityDebug(I, BWlumen, qualityMetrics, fileName)
% PLOTLUMENQUALITYDEBUG Generate debug figure for lumen quality analysis
%
% Returns figure handle for saving

    fig = figure('Position', [100 100 1400 500], 'Visible', 'off');
    
    % Ensure RGB for display
    if ndims(I) == 2
        Irgb = repmat(im2uint8(mat2gray(I)), [1 1 3]);
    else
        Irgb = im2uint8(I);
    end
    
    [H, W, ~] = size(Irgb);
    
    %% Panel 1: Original
    subplot(1,3,1);
    imshow(Irgb);
    title('Original', 'FontSize', 10);
    
    %% Panel 2: Lumen (green) + Convex Hull (yellow)
    subplot(1,3,2);
    imshow(labeloverlay(Irgb, BWlumen, 'Colormap', [0 1 0], 'Transparency', 0.3));
    hold on;
    
    % Draw convex hull perimeter
    if isfield(qualityMetrics, 'masks') && isfield(qualityMetrics.masks, 'hull')
        [B, ~] = bwboundaries(qualityMetrics.masks.hull, 'noholes');
        if ~isempty(B)
            plot(B{1}(:,2), B{1}(:,1), 'y-', 'LineWidth', 2);
        end
    end
    hold off;
    
    title(sprintf('Lumen + Hull (yellow)\nBright=%.2f [%s], Solidity=%.3f', ...
        qualityMetrics.brightness, qualityMetrics.status, qualityMetrics.solidity), ...
        'FontSize', 9);
    
    %% Panel 3: Anomaly breakdown (red=sag, magenta=debris)
    subplot(1,3,3);
    
    % Create RGB overlay
    anomalyDisplay = zeros(H, W, 3);
    
    if isfield(qualityMetrics, 'masks')
        if isfield(qualityMetrics.masks, 'sag')
            % Red for sag
            anomalyDisplay(:,:,1) = anomalyDisplay(:,:,1) + double(qualityMetrics.masks.sag) * 1.0;
        end
        if isfield(qualityMetrics.masks, 'debris')
            % Magenta for debris
            anomalyDisplay(:,:,1) = anomalyDisplay(:,:,1) + double(qualityMetrics.masks.debris) * 1.0;
            anomalyDisplay(:,:,3) = anomalyDisplay(:,:,3) + double(qualityMetrics.masks.debris) * 1.0;
        end
    end
    
    % Blend with grayscale original
    Igray = im2double(rgb2gray(Irgb));
    imgBlend = repmat(Igray * 0.5, [1 1 3]) + anomalyDisplay * 0.5;
    imgBlend = min(imgBlend, 1);
    imshow(imgBlend);
    
    hold on;
    % Hull outline (yellow)
    if isfield(qualityMetrics, 'masks') && isfield(qualityMetrics.masks, 'hull')
        [B, ~] = bwboundaries(qualityMetrics.masks.hull, 'noholes');
        if ~isempty(B)
            plot(B{1}(:,2), B{1}(:,1), 'y-', 'LineWidth', 1.5);
        end
    end
    % Lumen outline (green)
    [B2, ~] = bwboundaries(BWlumen, 'noholes');
    if ~isempty(B2)
        plot(B2{1}(:,2), B2{1}(:,1), 'g-', 'LineWidth', 1.5);
    end
    hold off;
    
    title(sprintf('Anomaly: RED=sag (%d px), MAGENTA=debris (%d px)\nDebris=%.1f%% of lumen', ...
        qualityMetrics.sagArea_px, qualityMetrics.debrisArea_px, qualityMetrics.debrisPct_ofLumen), ...
        'FontSize', 9);
    
    %% Main title
    sgtitle(sprintf('%s | Brightness=%.2f [%s] | Solidity=%.3f | Debris=%.1f%%', ...
        fileName, qualityMetrics.brightness, qualityMetrics.status, ...
        qualityMetrics.solidity, qualityMetrics.debrisPct_ofLumen), ...
        'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'none');
end