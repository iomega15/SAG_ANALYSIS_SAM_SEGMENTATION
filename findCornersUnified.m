function [leftCornerIdx, rightCornerIdx, cornerType] = findCornersUnified(topSmooth)
% FINDCORNERSUNIFIED Detect corners using Bounding-Box Anchored Scoring
% Works for both peaked (sag) and plateau (flat) roof cases, even with sloped walls.

    n = length(topSmooth);
    
    %% 1. Compute Derivatives
    slope = gradient(topSmooth);
    % Absolute curvature helps identify the "bend" regardless of direction
    curvature = abs(gradient(movmean(slope, 5))); 
    
    %% 2. Create a "Height Priority" Map
    % Higher points in the image (smaller Y) get higher weights.
    % This ensures that if walls are sloped, the algorithm prefers the peak.
    yMin = min(topSmooth);
    yMax = max(topSmooth);
    % Weight ranges from 1 to 2 based on vertical position
    heightWeight = 1 + (yMax - topSmooth) ./ max(1, yMax - yMin);
    
    %% 3. Define Bounding Box Anchor Zones
    % We know corners MUST be near the horizontal extents of the mask.
    % We search specifically in the outer 25% of the profile.
    searchWidth = round(n * 0.25);
    leftZone = 1:searchWidth;
    rightZone = (n - searchWidth + 1):n;
    
    %% 4. Scoring: Height * Curvature
    % We look for the point that is both "High" and has a "Sharp Turn"
    score = heightWeight .* curvature;
    
    % Find Left Corner in the left zone
    [~, localIdxL] = max(score(leftZone));
    leftCornerIdx = leftZone(localIdxL);
    
    % Find Right Corner in the right zone
    [~, localIdxR] = max(score(rightZone));
    rightCornerIdx = rightZone(localIdxR);
    
    %% 5. Classification
    % Determine if the roof is a plateau or peaked for your metrics
    roofRegion = topSmooth(leftCornerIdx:rightCornerIdx);
    if isempty(roofRegion)
        leftCornerIdx = round(n * 0.15);
        rightCornerIdx = round(n * 0.85);
        cornerType = 'fallback';
        return;
    end
    
    roofRange = max(roofRegion) - min(roofRegion);
    roofSpan = rightCornerIdx - leftCornerIdx;
    
    % If vertical variation is less than 10% of the span, it's a plateau
    if roofRange / max(1, roofSpan) < 0.1
        cornerType = 'plateau';
    else
        cornerType = 'peaked';
    end
    
    %% 6. Final Bounds Check
    % Ensure corners don't migrate into the center of the channel
    leftCornerIdx = max(1, min(leftCornerIdx, round(n * 0.45)));
    rightCornerIdx = max(round(n * 0.55), min(rightCornerIdx, n));
end