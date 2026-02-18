function qualityMetrics = analyzeLumenQuality(BWlumen, sagMetrics, I, mmPerPx)
% ANALYZELUMENQUALITY Compute lumen brightness, status, debris, and solidity
%
% Inputs:
%   BWlumen    - Binary mask of lumen
%   sagMetrics - Output from measureMembraneSag (needs .profiles.topSmooth, 
%                .profiles.baselineIdeal, .profiles.xCoords, .profiles.leftCornerIdx,
%                .profiles.rightCornerIdx)
%   I          - Original image (RGB or grayscale)
%   mmPerPx    - mm per pixel calibration
%
% Outputs:
%   qualityMetrics - Struct with brightness, status, debris, solidity info

    % Initialize output
    qualityMetrics = struct();
    qualityMetrics.valid = false;
    qualityMetrics.brightness = NaN;
    qualityMetrics.status = 'unknown';
    qualityMetrics.solidity = NaN;
    qualityMetrics.debrisArea_px = 0;
    qualityMetrics.debrisArea_mm2 = 0;
    qualityMetrics.debrisPct_ofLumen = 0;
    qualityMetrics.sagArea_px = 0;
    qualityMetrics.totalAnomalyArea_px = 0;
    
    if ~any(BWlumen(:))
        qualityMetrics.status = 'no_lumen';
        return;
    end
    
    % Convert to grayscale if needed
    if ndims(I) == 3
        Ig = im2double(rgb2gray(I));
    else
        Ig = im2double(I);
    end
    
    %% 1. BRIGHTNESS ANALYSIS
    lumenPixels = Ig(BWlumen);
    qualityMetrics.brightness = mean(lumenPixels);
    qualityMetrics.brightnessStd = std(lumenPixels);
    
    % Classify status based on brightness
    % if qualityMetrics.brightness > 0.5
    %     qualityMetrics.status = 'bright';  % Clean, open lumen
    % elseif qualityMetrics.brightness > 0.25
    %     qualityMetrics.status = 'partial'; % Partially occluded
    % else
    %     qualityMetrics.status = 'dark';    % Occluded/clogged
    % end
    
    %% 2. CONVEX HULL AND SOLIDITY
    BW_hull = bwconvhull(BWlumen);
    lumenArea = sum(BWlumen(:));
    hullArea = sum(BW_hull(:));
    
    qualityMetrics.lumenArea_px = lumenArea;
    qualityMetrics.hullArea_px = hullArea;
    qualityMetrics.solidity = lumenArea / hullArea;
    
    % Total anomaly = hull - lumen
    anomalyRegion = BW_hull & ~BWlumen;
    qualityMetrics.totalAnomalyArea_px = sum(anomalyRegion(:));
    
    %% 3. SEPARATE SAG FROM DEBRIS
    % Sag region = area between top edge and baseline (from sagMetrics)
    
    sagMask = false(size(BWlumen));
    
    if ~isempty(sagMetrics) && isfield(sagMetrics, 'valid') && sagMetrics.valid && ...
       isfield(sagMetrics, 'profiles') && ~isempty(sagMetrics.profiles)
        
        p = sagMetrics.profiles;
        
        if isfield(p, 'topSmooth') && isfield(p, 'baselineIdeal') && ...
           isfield(p, 'xCoords') && isfield(p, 'leftCornerIdx') && isfield(p, 'rightCornerIdx')
            
            topSmooth = p.topSmooth;
            baselineIdeal = p.baselineIdeal;
            xCoords = p.xCoords;
            leftIdx = p.leftCornerIdx;
            rightIdx = p.rightCornerIdx;
            
            % Build sag mask: pixels between baseline and top edge (between corners)
            [nRows, nCols] = size(BWlumen);
            
            for colIdx = leftIdx:rightIdx
                x = xCoords(colIdx);
                if x >= 1 && x <= nCols
                    yTop = round(topSmooth(colIdx));
                    yBase = round(baselineIdeal(colIdx));
                    
                    % Sag is where top edge is BELOW baseline (higher Y value)
                    if yTop > yBase
                        yTop = max(1, min(nRows, yTop));
                        yBase = max(1, min(nRows, yBase));
                        sagMask(yBase:yTop, x) = true;
                    end
                end
            end
        end
    end
    
    qualityMetrics.sagArea_px = sum(sagMask(:));
    
    %% 4. DEBRIS = ANOMALY - SAG
    % Debris is any part of (hull - lumen) that is NOT the sag region
    debrisMask = anomalyRegion & ~sagMask;
    qualityMetrics.debrisArea_px = sum(debrisMask(:));
    
    if ~isnan(mmPerPx) && mmPerPx > 0
        qualityMetrics.debrisArea_mm2 = qualityMetrics.debrisArea_px * mmPerPx^2;
        qualityMetrics.sagArea_mm2 = qualityMetrics.sagArea_px * mmPerPx^2;
    else
        qualityMetrics.debrisArea_mm2 = NaN;
        qualityMetrics.sagArea_mm2 = NaN;
    end
    
    % Debris as percentage of lumen
    if lumenArea > 0
        qualityMetrics.debrisPct_ofLumen = 100 * qualityMetrics.debrisArea_px / lumenArea;
    end
    
    %% 5. STORE MASKS FOR DEBUG
    qualityMetrics.masks.hull = BW_hull;
    qualityMetrics.masks.anomaly = anomalyRegion;
    qualityMetrics.masks.sag = sagMask;
    qualityMetrics.masks.debris = debrisMask;
    
    qualityMetrics.valid = true;
end