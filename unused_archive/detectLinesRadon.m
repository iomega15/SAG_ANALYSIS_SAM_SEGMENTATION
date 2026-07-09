function detectLinesRadon(I, numPeaks)
% DETECTLINESRADON Detect lines using the Radon Transform (corrected)

    if nargin < 2
        numPeaks = 5;
    end

    %% Preprocess input
    if size(I, 3) == 3
        I = rgb2gray(I);
    end
    I = rescale(im2double(I));

    %% Step 1: Display original image
    figure('Name', 'Radon Line Detection', 'NumberTitle', 'off');
    subplot(2, 2, 1);
    imshow(I);
    title('Original Image');

    %% Step 2: Compute binary edge image
    BW = edge(I);

    subplot(2, 2, 2);
    imshow(BW);
    title('Edge Image');

    %% Step 3: Compute the Radon Transform
    theta = 0:179;
    [R, xp] = radon(BW, theta);

    subplot(2, 2, 3);
    imagesc(theta, xp, R);
    colormap(hot);
    xlabel('\theta (degrees)');
    ylabel('x'' (pixels from center)');
    title('Radon Transform R_{\theta}(x'')');
    colorbar;

    %% Step 4: Find the strongest peaks
    % Smooth slightly to avoid picking multiple adjacent pixels as separate peaks
    R_smooth = imgaussfilt(R, 1);
    
    R_sort = sort(R_smooth(:), 'descend');
    
    numPeaks = min(numPeaks, length(R_sort));
    
    % Use a threshold approach to find distinct peaks
    peakThreshold = R_sort(numPeaks);
    peakMask = R_smooth >= peakThreshold;
    
    % Find regional maxima to get distinct peaks
    peakMask = imregionalmax(R_smooth) & (R_smooth >= peakThreshold);
    
    [row_peak, col_peak] = find(peakMask);
    
    % Sort by strength and keep top numPeaks
    peakVals = arrayfun(@(r,c) R_smooth(r,c), row_peak, col_peak);
    [~, sortIdx] = sort(peakVals, 'descend');
    
    if length(sortIdx) > numPeaks
        sortIdx = sortIdx(1:numPeaks);
    end
    
    row_peak = row_peak(sortIdx);
    col_peak = col_peak(sortIdx);
    
    xp_peak_offset = xp(row_peak);
    theta_peak = theta(col_peak);

    %% Step 5: Display detected lines on the original image
    subplot(2, 2, 4);
    imshow(I);
    hold on;

    centerX = ceil(size(I, 2) / 2);
    centerY = ceil(size(I, 1) / 2);

    scatter(centerX, centerY, 50, 'bx', 'LineWidth', 2);

    D = hypot(size(I, 1), size(I, 2));
    colors = lines(numPeaks);

    for i = 1:length(theta_peak)
        t = theta_peak(i);       % theta in degrees
        offset = xp_peak_offset(i);
        c = colors(i, :);

        % CORRECT GEOMETRY for radon():
        % The radon transform at angle theta projects along the direction
        % theta (measured CCW from the x-axis). A peak at (theta, xp) 
        % corresponds to a LINE that is PERPENDICULAR to the projection 
        % direction, at distance xp from the center.
        %
        % The line's normal direction: angle theta from x-axis
        % The line itself runs at angle (theta + 90) from x-axis
        %
        % Normal vector (points from center toward the line):
        %   nx = cosd(theta), ny = sind(theta)
        % Line direction:
        %   lx = -sind(theta), ly = cosd(theta)
        %
        % A point on the line closest to center:
        %   px = centerX + offset * cosd(theta)
        %   py = centerY + offset * sind(theta)  -- BUT y-axis is flipped in images
        
        % Point on the line closest to center (image coords: y increases downward)
        px = centerX + offset * cosd(t);
        py = centerY - offset * sind(t);   % negative because image y is flipped
        
        % Line direction vector (along the line)
        lx = -sind(t);
        ly = -cosd(t);  % negative because image y is flipped
        
        % Draw the line extending far in both directions
        x1 = px - D * lx;
        x2 = px + D * lx;
        y1 = py - D * ly;
        y2 = py + D * ly;
        
        plot([x1, x2], [y1, y2], '-', 'Color', c, 'LineWidth', 2);
    end
    
    % Set axis limits to image bounds
    xlim([1, size(I, 2)]);
    ylim([1, size(I, 1)]);
    hold off;
    title(sprintf('Detected Lines (Top %d Peaks)', length(theta_peak)));

    %% Print summary
    fprintf('\n--- Detected Lines Summary ---\n');
    fprintf('%-6s %-15s %-15s\n', 'Peak', 'Theta (deg)', 'Offset (px)');
    fprintf('%-6s %-15s %-15s\n', '----', '-----------', '-----------');
    for i = 1:length(theta_peak)
        fprintf('%-6d %-15.1f %-15.1f\n', i, theta_peak(i), xp_peak_offset(i));
    end
    fprintf('------------------------------\n');

end