function [I_rotated, BWlumen_rotated, rotationAngle] = autoRotateImage(I, BWlumen, roi, saveSagDebug, debugFolder, baseName)
% AUTOROTATEIMAGE Automatically straightens an image and mask based on detected horizontal lines.
%
%   Inputs:
%       I              - Original image (RGB or grayscale)
%       BWlumen        - Binary lumen mask from SAM
%       roi            - ROI struct with bottomFrac field
%       saveSagDebug   - (optional) Boolean to save debug images (default: false)
%       debugFolder    - (optional) Folder path for debug images
%       baseName       - (optional) Base filename for debug images
%
%   Outputs:
%       I_rotated        - Rotated image with bottom ROI removed
%       BWlumen_rotated  - Rotated binary mask with bottom ROI removed
%       rotationAngle    - Angle (in degrees) the image was rotated by

    % Default arguments
    if nargin < 4 || isempty(saveSagDebug), saveSagDebug = false; end
    if nargin < 5, debugFolder = ''; end
    if nargin < 6, baseName = ''; end

    % 1. Remove bottom ROI from original image
    [H_orig, W_orig, ~] = size(I);
    h_roi = round(H_orig * roi.bottomFrac);
    I_cropped = I(1:(H_orig - h_roi), :, :);
    BWlumen_cropped = BWlumen(1:(H_orig - h_roi), :);

    % 2. Convert to grayscale for line detection
    if ndims(I_cropped) == 3
        grayImage = rgb2gray(I_cropped);
    else
        grayImage = I_cropped;
    end

    % 3. Edge detection
    BW_edges = edge(grayImage, 'canny');

    % 4. Hough Transform
    [H, T, R] = hough(BW_edges);

    % 5. Find peaks in the Hough transform
    P = houghpeaks(H, 10, 'threshold', ceil(0.3 * max(H(:))));

    % 6. Find lines from the peaks
    lines = houghlines(BW_edges, T, R, P, 'FillGap', 20, 'MinLength', 40);

    % 7. Calculate the dominant angle
    rotationAngle = 0;
    
    if isempty(lines)
        % No lines detected - return cropped but unrotated
        I_rotated = I_cropped;
        BWlumen_rotated = BWlumen_cropped;
        return;
    end

    angles = [];
    for k = 1:length(lines)
        angle = lines(k).theta;
        
        % Filter for nearly horizontal lines (theta near ±90)
        if (angle > 60 && angle < 120)
            angles = [angles, angle - 90];
        elseif (angle > -120 && angle < -60)
            angles = [angles, angle + 90];
        end
    end

    if isempty(angles)
        % No horizontal lines detected - return cropped but unrotated
        I_rotated = I_cropped;
        BWlumen_rotated = BWlumen_cropped;
        return;
    end

    % Find the median angle to avoid outliers
    dominantAngle = median(angles);
    rotationAngle = dominantAngle;

    % 8. Apply rotation if meaningful
    if abs(rotationAngle) > 0.05
        % Rotate image with bicubic interpolation
        I_rotated = imrotate(I_cropped, rotationAngle, 'bicubic', 'crop');
        
        % Rotate mask with nearest-neighbor to preserve binary values
        BWlumen_rotated = imrotate(BWlumen_cropped, rotationAngle, 'nearest', 'crop') > 0;
    else
        I_rotated = I_cropped;
        BWlumen_rotated = BWlumen_cropped;
        rotationAngle = 0;
    end

    % 9. Save debug image if requested
    if saveSagDebug && abs(rotationAngle) > 0.1 && ~isempty(debugFolder) && ~isempty(baseName)
        figRot = figure('Visible', 'off', 'Position', [100 100 1600 500]);
        
        subplot(1,3,1);
        imshow(I_cropped);
        title('Original (ROI removed)');
        
        subplot(1,3,2);
        imshow(I_rotated);
        hold on;
        if any(BWlumen_rotated(:))
            visboundaries(BWlumen_rotated, 'Color', 'r', 'LineWidth', 1);
        end
        hold off;
        title(sprintf('Rotated %.2f° + Mask', rotationAngle));
        
        subplot(1,3,3);
        imshowpair(BWlumen_cropped, BWlumen_rotated, 'montage');
        title('Mask: Original vs Rotated');
        
        sgtitle(sprintf('Auto-Rotation: %s', baseName), 'Interpreter', 'none');
        
        saveas(figRot, fullfile(debugFolder, [baseName '_rotation_debug.png']));
        close(figRot);
    end
end