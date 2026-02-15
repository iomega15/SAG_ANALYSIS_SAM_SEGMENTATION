function [leftCornerIdx, rightCornerIdx, cornerType] = findCornersUnified(topSmooth)
% FINDCORNERSUNIFIED Detect corners using slope transition
% Works for both peaked (sag) and plateau (flat) roof cases
%
% Inputs:
%   topSmooth - Smoothed top edge profile (Y values)
%
% Outputs:
%   leftCornerIdx  - Index of left corner in profile
%   rightCornerIdx - Index of right corner in profile
%   cornerType     - 'peaked', 'plateau', or 'fallback'

    n = length(topSmooth);
    
    %% 1. Compute slope (derivative)
    slope = gradient(topSmooth);
    
    % Smooth to reduce noise
    windowSize = max(5, round(n / 15));
    slopeSmooth = movmean(slope, windowSize);
    
    %% 2. Find where slope is "shallow" vs "steep"
    absSlope = abs(slopeSmooth);
    maxAbsSlope = max(absSlope);
    
    % Threshold: shallow = less than 25% of max slope
    shallowThreshold = maxAbsSlope * 0.25;
    
    %% 3. Find the "roof region" - contiguous shallow slope region
    isShallow = absSlope < shallowThreshold;
    
    % Must be in the middle portion (not at edges)
    edgeBuffer = round(n * 0.08);
    isShallow(1:edgeBuffer) = false;
    isShallow(end-edgeBuffer+1:end) = false;
    
    % Find connected components
    CC = bwconncomp(isShallow);
    
    if CC.NumObjects > 0
        % Find largest shallow region (this is the roof)
        lengths = cellfun(@length, CC.PixelIdxList);
        [maxLen, maxIdx] = max(lengths);
        
        % Only use if it spans a reasonable portion
        if maxLen > n * 0.2
            roofIndices = CC.PixelIdxList{maxIdx};
            leftCornerIdx = roofIndices(1);
            rightCornerIdx = roofIndices(end);
        else
            % Region too small, use fallback
            leftCornerIdx = round(n * 0.15);
            rightCornerIdx = round(n * 0.85);
        end
    else
        % No shallow region found, use fallback
        leftCornerIdx = round(n * 0.15);
        rightCornerIdx = round(n * 0.85);
    end
    
    %% 4. Refine using curvature (second derivative)
    % The corner is at maximum curvature (sharpest bend)
    curvature = gradient(slopeSmooth);
    
    % Search window around detected points
    searchRadius = round(n * 0.08);
    
    % Left corner: max positive curvature (slope going from negative to ~0)
    searchLeft = max(1, leftCornerIdx - searchRadius):min(n, leftCornerIdx + searchRadius);
    if ~isempty(searchLeft)
        [~, refinedIdx] = max(curvature(searchLeft));
        leftCornerIdx = searchLeft(refinedIdx);
    end
    
    % Right corner: max negative curvature (slope going from ~0 to positive)
    searchRight = max(1, rightCornerIdx - searchRadius):min(n, rightCornerIdx + searchRadius);
    if ~isempty(searchRight)
        [~, refinedIdx] = min(curvature(searchRight));
        rightCornerIdx = searchRight(refinedIdx);
    end
    
    %% 5. Validate and classify
    % Ensure left < right with minimum span
    minSpan = round(n * 0.3);
    if rightCornerIdx - leftCornerIdx < minSpan
        leftCornerIdx = round(n * 0.15);
        rightCornerIdx = round(n * 0.85);
        cornerType = 'fallback';
    else
        % Classify based on roof flatness
        roofRegion = topSmooth(leftCornerIdx:rightCornerIdx);
        roofRange = max(roofRegion) - min(roofRegion);
        roofSpan = rightCornerIdx - leftCornerIdx;
        
        % If roof variation is small relative to span, it's a plateau
        if roofRange / roofSpan < 0.1  % Less than 0.1 px variation per px span
            cornerType = 'plateau';
        else
            cornerType = 'peaked';
        end
    end
    
    %% 6. Final bounds check
    leftCornerIdx = max(1, min(leftCornerIdx, round(n * 0.45)));
    rightCornerIdx = max(round(n * 0.55), min(rightCornerIdx, n));
end