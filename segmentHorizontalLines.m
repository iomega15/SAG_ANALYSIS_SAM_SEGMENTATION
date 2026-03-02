function segmentHorizontalLines(BW)
% SEGMENTHORIZONTALLINES Segments regions with horizontal lines from a BW mask
%   segmentHorizontalLines(BW) takes a binary or grayscale mask as input
%   and displays an overlay visualization where:
%       Green = Horizontal line regions
%       Red   = Non-horizontal regions
%
%   Input:
%       BW - Binary mask (logical, uint8, or RGB image)
%
%   Example:
%       BW = imread('mask.png');
%       segmentHorizontalLines(BW);

    %% Preprocess input
    if size(BW, 3) == 3
        BW = rgb2gray(BW);
    end
    if ~islogical(BW)
        BW = imbinarize(BW);
    end

    %% Step 1: Extract horizontal lines using morphological opening
    horzLen = round(size(BW, 2) * 0.15);   % 15% of image width
    se_horz = strel('line', horzLen, 0);    % horizontal line SE
    horizontalLines = imopen(BW, se_horz);

    %% Step 2: Dilate detected lines vertically to merge nearby lines
    se_dilate = strel('rectangle', [15, 1]);
    horizontalRegions = imdilate(horizontalLines, se_dilate);

    %% Step 3: Filter connected components by aspect ratio and area
    CC = bwconncomp(horizontalRegions);
    horizontalMask = false(size(BW));

    stats = regionprops(CC, 'BoundingBox', 'Area');
    for i = 1:CC.NumObjects
        bb = stats(i).BoundingBox;
        aspectRatio = bb(3) / bb(4);
        if aspectRatio > 3 && stats(i).Area > 500
            horizontalMask(CC.PixelIdxList{i}) = true;
        end
    end

    %% Step 4: Expand mask to capture full horizontal-line zones
    se_expand = strel('rectangle', [25, 5]);
    horizontalZone = imdilate(horizontalMask, se_expand);
    horizontalZone = imfill(horizontalZone, 'holes');

    %% Step 5: Segment into horizontal-line and non-horizontal regions
    BW_horizontalLines = BW & horizontalZone;
    BW_other = BW & ~horizontalZone;

    %% Display overlay visualization
    overlay = cat(3, ...
        uint8(BW_other) * 255, ...          % Red channel
        uint8(BW_horizontalLines) * 255, ... % Green channel
        zeros(size(BW), 'uint8'));            % Blue channel

    figure('Name', 'Horizontal Line Segmentation');
    imshow(overlay);
    title('Red = Non-Horizontal Regions | Green = Horizontal Line Regions');

endsegmentHorizontalLines(BW)