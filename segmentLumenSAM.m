function [BWlumen, quality] = segmentLumenSAM(I, roi, debugFolder, baseName)
% SEGMENTLUMENSAM Segment lumen using SAM + texture clustering + hole-fill scoring
%
% Uses texture-based clustering to identify 3D-printed structures,
% then only considers non-textured masks as lumen candidates.
%
% Inputs:
%   I           - Input image (RGB or grayscale)
%   roi         - Struct with roi.bottomFrac field
%   debugFolder - (Optional) Path to save debug figures. If empty, no debug.
%   baseName    - (Optional) Base filename for debug images
%
% Outputs:
%   BWlumen     - Binary lumen mask (full image size)
%   quality     - Struct with quality metrics and debug info

    %% ====================================================================
    % DEBUG DISPLAY OPTION
    % Set to true to display figures on screen instead of saving to files
    % =====================================================================
    SHOW_DEBUG_FIGURES = true;
    
    % Handle optional arguments
    if nargin < 3
        debugFolder = '';
    end
    if nargin < 4
        baseName = 'image';
    end
    
    saveDebug = ~isempty(debugFolder) && exist(debugFolder, 'dir');
    
    % Ensure RGB
    Irgb = I;
    if ndims(Irgb) == 2
        Irgb = repmat(Irgb, [1 1 3]);
    end
    [H, W, ~] = size(Irgb);
    Igray = rgb2gray(Irgb);
    Igray_u8 = im2uint8(Igray);
    Igray_dbl = im2double(Igray);
    
    % Crop out bottom band (scale bar region)
    hEx = max(1, round(H * roi.bottomFrac));
    I_cropped = Irgb(1:H-hEx, :, :);
    Igray_cropped_u8 = Igray_u8(1:H-hEx, :);
    Igray_cropped_dbl = Igray_dbl(1:H-hEx, :);
    [Hc, Wc] = size(Igray_cropped_u8);
    totalPixels = Hc * Wc;
    
    % Initialize outputs
    BWlumen = false(H, W);
    BW_lumen_cropped = false(Hc, Wc);
    
    quality = struct();
    quality.status = 'unknown';
    quality.lumen_valid = false;
    quality.lumen_area_px = 0;
    quality.best_mask_index = -1;
    quality.num_masks = 0;
    quality.num_textured_masks = 0;
    quality.num_nontextured_masks = 0;
    quality.num_valid_masks = 0;
    quality.rejection_reason = '';
    
    % Save temp image for Python
    tempFile = fullfile(tempdir, 'temp_sam_input.png');
    imwrite(I_cropped, tempFile);
    
    % Checkpoint path
    checkpointFile = fullfile(pwd, 'sam_vit_b_01ec64.pth');
    
    % Verify checkpoint exists
    if ~exist(checkpointFile, 'file')
        quality.status = 'checkpoint_not_found';
        quality.rejection_reason = sprintf('SAM checkpoint not found: %s', checkpointFile);
        warning(quality.rejection_reason);
        if exist(tempFile, 'file'), delete(tempFile); end
        return;
    end
    
    try
        %% ================================================================
        % STEP 1: Run SAM to get all masks
        % ================================================================
        disp('running sam...')
        tic
        [all_masks_out, all_masks_out] = pyrunfile( ...
            "sam_segment_simple.py", ...
            ["all_masks_out", "num_masks"], ...
            image_path=tempFile, ...
            checkpoint_path=checkpointFile);
        toc
        
        allMasks = logical(all_masks_out);
        numMasks = double(num_masks);
        quality.num_masks = numMasks;
        
        if numMasks == 0
            quality.status = 'no_masks_generated';
            quality.rejection_reason = 'SAM generated no masks';
            if exist(tempFile, 'file'), delete(tempFile); end
            return;
        end
        
        % Save Step 1 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep1Debug(I_cropped, allMasks, numMasks, Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 1b: Fill holes in each mask before texture analysis
        % This removes speckle-like holes that could be mistaken for texture
        % ================================================================
        allMasksFilled = allMasks;  % Copy original
        holesFilled = zeros(numMasks, 1);
        
        for m = 1:numMasks
            thisMask = squeeze(allMasks(m, :, :));
            filledMask = imfill(thisMask, 'holes');
            holesFilled(m) = sum(filledMask(:)) - sum(thisMask(:));
            allMasksFilled(m, :, :) = filledMask;
        end
        
        % Save Step 1b debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep1bDebug(I_cropped, allMasks, allMasksFilled, numMasks, ...
                holesFilled, Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 2: Compute texture features for each mask (using filled masks)
        % Focus on HORIZONTAL LAYER LINES characteristic of 3D printing
        % ================================================================
        textureFeatures = zeros(numMasks, 3);  % [h_layer_score, h_periodicity, edge_density]
        
        for m = 1:numMasks
            % Use filled mask for texture analysis
            thisMaskFilled = squeeze(allMasksFilled(m, :, :));
            [h_layer_score, h_periodicity, edge_den] = computeHorizontalLayerTexture(Igray_cropped_dbl, thisMaskFilled);
            textureFeatures(m, :) = [h_layer_score, h_periodicity, edge_den];
        end
        
        quality.texture_features = textureFeatures;
        
        % Save Step 2 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep2Debug(textureFeatures, numMasks, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 3: Cluster masks into textured vs non-textured (k=2)
        % Use h_layer_score and h_periodicity (NOT general edge density)
        % ================================================================
        % Use only horizontal layer features for clustering
        clusterFeatures = textureFeatures(:, 1:2);  % h_layer_score, h_periodicity
        
        % Normalize features for clustering
        featuresNorm = clusterFeatures;
        for col = 1:size(clusterFeatures, 2)
            minVal = min(clusterFeatures(:, col));
            maxVal = max(clusterFeatures(:, col));
            if maxVal > minVal
                featuresNorm(:, col) = (clusterFeatures(:, col) - minVal) / (maxVal - minVal);
            else
                featuresNorm(:, col) = 0;
            end
        end
        
        % K-means clustering
        rng(42);  % For reproducibility
        [clusterIdx, centroids] = kmeans(featuresNorm, 2, 'Replicates', 5);
        
        % Determine which cluster is "textured" (higher mean layer score)
        cluster1_mean_layer = mean(textureFeatures(clusterIdx == 1, 1));
        cluster2_mean_layer = mean(textureFeatures(clusterIdx == 2, 1));
        
        if cluster1_mean_layer > cluster2_mean_layer
            texturedCluster = 1;
            nonTexturedCluster = 2;
        else
            texturedCluster = 2;
            nonTexturedCluster = 1;
        end
        
        isTextured = (clusterIdx == texturedCluster);
        isNonTextured = (clusterIdx == nonTexturedCluster);
        
        quality.num_textured_masks = sum(isTextured);
        quality.num_nontextured_masks = sum(isNonTextured);
        quality.cluster_idx = clusterIdx;
        quality.textured_cluster = texturedCluster;
        
        % Save Step 3 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep3Debug(I_cropped, allMasks, numMasks, textureFeatures, ...
                clusterIdx, isTextured, isNonTextured, centroids, ...
                Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 4: Create BW_3d_printed_mask (merge all textured masks)
        % ================================================================
        BW_3d_printed_mask = false(Hc, Wc);
        for m = find(isTextured)'
            thisMask = squeeze(allMasks(m, :, :));
            BW_3d_printed_mask = BW_3d_printed_mask | thisMask;
        end
        
        % Morphological cleanup
        BW_3d_printed_mask = imclose(BW_3d_printed_mask, strel('disk', 3));
        
        quality.structure_area_px = sum(BW_3d_printed_mask(:));
        
        % Save Step 4 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4Debug(I_cropped, BW_3d_printed_mask, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 5: Filter non-textured masks - remove border-touching
        % ================================================================
        edgeMargin = 1;
        
        maskTouchesBorder = false(numMasks, 1);
        
        for m = 1:numMasks
            thisMask = squeeze(allMasks(m, :, :));
            touchesTop = any(thisMask(1:edgeMargin, :), 'all');
            touchesBottom = any(thisMask(end-edgeMargin+1:end, :), 'all');
            touchesLeft = any(thisMask(:, 1:edgeMargin), 'all');
            touchesRight = any(thisMask(:, end-edgeMargin+1:end), 'all');
            maskTouchesBorder(m) = touchesTop || touchesBottom || touchesLeft || touchesRight;
        end
        
        % Valid masks: non-textured AND not touching border
        maskValid = isNonTextured & ~maskTouchesBorder;
        quality.num_valid_masks = sum(maskValid);
        quality.mask_touches_border = maskTouchesBorder;
        quality.is_textured = isTextured;
        quality.mask_valid = maskValid;
        
        % Combine valid non-textured masks for visualization
        BW_non_textured_filtered = false(Hc, Wc);
        for m = find(maskValid)'
            thisMask = squeeze(allMasks(m, :, :));
            BW_non_textured_filtered = BW_non_textured_filtered | thisMask;
        end
        
        % Save Step 5 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep5Debug(I_cropped, allMasks, numMasks, isNonTextured, ...
                maskTouchesBorder, maskValid, BW_non_textured_filtered, ...
                Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        if quality.num_valid_masks == 0
            quality.status = 'no_valid_nontextured_masks';
            quality.rejection_reason = 'All non-textured SAM masks touch image border';
            if exist(tempFile, 'file'), delete(tempFile); end
            
            if saveDebug || SHOW_DEBUG_FIGURES
                saveFailureDebug(I_cropped, allMasks, numMasks, isTextured, ...
                    maskTouchesBorder, BW_3d_printed_mask, ...
                    Hc, Wc, debugFolder, baseName, quality.rejection_reason, SHOW_DEBUG_FIGURES);
            end
            return;
        end
        
        %% ================================================================
        % STEP 6: Grayscale hole-filling (original and inverse)
        % ================================================================
        I_fill = imfill(Igray_cropped_u8);
        I_inv = imcomplement(Igray_cropped_u8);
        I_inv_fill = imfill(I_inv);
        I_fill_from_inv = imcomplement(I_inv_fill);
        
        % BW masks: pixels changed by the grayscale hole-fill
        mask_holes_gray = logical(I_fill ~= Igray_cropped_u8);
        mask_holes_inv = logical(I_fill_from_inv ~= Igray_cropped_u8);
        
        % Save Step 6 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep6Debug(Igray_cropped_u8, I_fill, I_inv, I_inv_fill, ...
                I_fill_from_inv, mask_holes_gray, mask_holes_inv, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 7: Remove 3D-printed region from hole masks
        % ================================================================
        mask_holes_gray_clean = mask_holes_gray;
        mask_holes_gray_clean(BW_3d_printed_mask) = false;
        
        mask_holes_inv_clean = mask_holes_inv;
        mask_holes_inv_clean(BW_3d_printed_mask) = false;
        
        % Save Step 7 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep7Debug(mask_holes_gray, mask_holes_inv, BW_3d_printed_mask, ...
                mask_holes_gray_clean, mask_holes_inv_clean, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 8: Compute combined absolute difference (cleaned)
        % ================================================================
        abs_diff_gray = abs(double(I_fill) - double(Igray_cropped_u8));
        abs_diff_inv = abs(double(Igray_cropped_u8) - double(I_fill_from_inv));
        combined_abs_diff = abs_diff_gray + abs_diff_inv;
        
        % Zero out the 3D-printed region in the difference map
        combined_abs_diff_clean = combined_abs_diff;
        combined_abs_diff_clean(BW_3d_printed_mask) = 0;
        
        totalSignal = sum(combined_abs_diff_clean(:));
        
        % Save Step 8 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep8Debug(I_cropped, combined_abs_diff, combined_abs_diff_clean, ...
                BW_3d_printed_mask, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 9: Score each valid (non-textured, non-border) SAM mask
        % ================================================================
        maskAreas = zeros(numMasks, 1);
        maskSumScores = zeros(numMasks, 1);
        maskMeanScores = zeros(numMasks, 1);
        maskRobustScores = zeros(numMasks, 1);
        maskEnrichment = zeros(numMasks, 1);
        
        for m = 1:numMasks
            thisMask = squeeze(allMasks(m, :, :));
            maskAreas(m) = sum(thisMask(:));
            maskSumScores(m) = sum(combined_abs_diff_clean(thisMask));
            maskMeanScores(m) = maskSumScores(m) / max(maskAreas(m), 1);
            
            % Enrichment calculation
            areaFraction = maskAreas(m) / totalPixels;
            signalFraction = maskSumScores(m) / max(totalSignal, 1);
            maskEnrichment(m) = signalFraction / max(areaFraction, 1e-6);
            
            % Only compute robust score for VALID masks (non-textured, non-border)
            if maskValid(m)
                maskRobustScores(m) = maskMeanScores(m) * sqrt(maskAreas(m));
            else
                maskRobustScores(m) = 0;
            end
        end
        
        % Save Step 9 debug
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep9Debug(I_cropped, allMasks, numMasks, maskAreas, maskMeanScores, ...
                maskRobustScores, maskEnrichment, maskValid, isTextured, ...
                maskTouchesBorder, Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
        %% ================================================================
        % STEP 10: Select best mask from valid candidates
        % ================================================================
        [bestRobustScore, bestIdx] = max(maskRobustScores);
        
        if bestRobustScore == 0
            % Fallback: highest mean among valid masks
            validMeanScores = maskMeanScores;
            validMeanScores(~maskValid) = 0;
            [~, bestIdx] = max(validMeanScores);
        end
        
        %% ================================================================
        % STEP 11: Validate that this is actually a lumen
        % ================================================================
        bestEnrichment = maskEnrichment(bestIdx);
        bestMeanScore = maskMeanScores(bestIdx);
        bestArea = maskAreas(bestIdx);
        
        % Statistics across valid masks
        validMeanScores = maskMeanScores(maskValid);
        
        if sum(maskValid) > 1
            meanOfMeans = mean(validMeanScores);
            stdOfMeans = std(validMeanScores);
            if stdOfMeans > 0
                zScore = (bestMeanScore - meanOfMeans) / stdOfMeans;
            else
                zScore = 0;
            end
        else
            zScore = inf;
        end
        
        % Store metrics
        quality.best_mask_index = bestIdx;
        quality.lumen_area_px = bestArea;
        quality.robust_score = bestRobustScore;
        quality.mean_score = bestMeanScore;
        quality.sum_score = maskSumScores(bestIdx);
        quality.enrichment = bestEnrichment;
        quality.z_score = zScore;
        quality.total_signal = totalSignal;
        quality.all_mask_areas = maskAreas;
        quality.all_robust_scores = maskRobustScores;
        quality.all_mean_scores = maskMeanScores;
        quality.all_enrichments = maskEnrichment;
        
        %% ================================================================
        % STEP 12: Decision - is this a real lumen?
        % ================================================================
        isLumenValid = true;
        rejectionReason = '';
        
        % Check 1: Meaningful signal
        meanSignalPerPixel = totalSignal / totalPixels;
        if meanSignalPerPixel < 1.0
            isLumenValid = false;
            rejectionReason = sprintf('Insufficient hole-fill signal (mean=%.2f per pixel)', meanSignalPerPixel);
        end
        
        % Check 2: Signal concentration
        if isLumenValid && bestEnrichment < 2.0
            isLumenValid = false;
            rejectionReason = sprintf('Low signal enrichment (%.1fx, expected >2x for lumen)', bestEnrichment);
        end
        
        % Check 3: Distinctiveness
        if isLumenValid && sum(maskValid) > 2 && zScore < 1.0
            isLumenValid = false;
            rejectionReason = sprintf('Best mask not distinctive (z=%.1f, expected >1.0)', zScore);
        end
        
        % Check 4: Mean score sanity
        if isLumenValid && bestMeanScore < 5.0
            isLumenValid = false;
            rejectionReason = sprintf('Best mask has very low mean score (%.1f)', bestMeanScore);
        end
        
        %% ================================================================
        % STEP 13: Set final status
        % ================================================================
        if isLumenValid
            quality.status = 'good';
            quality.lumen_valid = true;
            BW_lumen_cropped = squeeze(allMasks(bestIdx, :, :));
        else
            quality.status = 'no_lumen_detected';
            quality.lumen_valid = false;
            quality.rejection_reason = rejectionReason;
            BW_lumen_cropped = false(Hc, Wc);
        end
        
        %% ================================================================
        % STEP 14: Save final debug figures
        % ================================================================
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep10Debug(I_cropped, allMasks, numMasks, maskValid, isTextured, ...
                maskTouchesBorder, maskRobustScores, maskEnrichment, ...
                bestIdx, Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
            
            saveFinalDebug(I_cropped, BW_3d_printed_mask, BW_lumen_cropped, ...
                quality, debugFolder, baseName, SHOW_DEBUG_FIGURES);
            
            saveSummaryDebug(I_cropped, allMasks, allMasksFilled, numMasks, textureFeatures, ...
                clusterIdx, isTextured, BW_3d_printed_mask, maskValid, ...
                combined_abs_diff_clean, maskRobustScores, bestIdx, ...
                BW_lumen_cropped, quality, Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        
    catch ME
        warning(['SAM failed: %s', ME.message]);
        quality.status = 'SAM_error';
        quality.rejection_reason = ME.message;
        BW_lumen_cropped = false(Hc, Wc);
    end
    
    % Cleanup temp file
    if exist(tempFile, 'file')
        delete(tempFile);
    end
    
    % Pad back to original size
    BWlumen = false(H, W);
    BWlumen(1:H-hEx, :) = BW_lumen_cropped;
    
end

%% ========================================================================
% LOCAL FUNCTION: Compute horizontal LAYER texture (3D printing specific)
% ========================================================================
function [h_layer_score, h_periodicity, edge_density] = computeHorizontalLayerTexture(Igray, mask)
    % Compute horizontal layer texture features specific to 3D printing
    %
    % 3D printed structures have characteristic HORIZONTAL STRIATIONS from
    % layer-by-layer deposition. We look for:
    %   1. Strong horizontal edges (layer boundaries)
    %   2. Periodic/regular spacing of these edges
    %
    % A lumen (dark hole) should NOT have these features.
    
    if sum(mask(:)) < 100
        h_layer_score = 0;
        h_periodicity = 0;
        edge_density = 0;
        return;
    end
    
    % Get bounding box
    [rows, cols] = find(mask);
    y_min = max(1, min(rows) - 2);
    y_max = min(size(Igray,1), max(rows) + 2);
    x_min = max(1, min(cols) - 2);
    x_max = min(size(Igray,2), max(cols) + 2);
    
    roi_gray = Igray(y_min:y_max, x_min:x_max);
    roi_mask = mask(y_min:y_max, x_min:x_max);
    
    % === Feature 1: Horizontal vs Vertical edge ratio ===
    % Use Sobel to get directional gradients
    % Horizontal EDGES come from VERTICAL gradients (Gy)
    [Gx, Gy] = imgradientxy(roi_gray, 'sobel');
    
    % Apply mask
    Gx_masked = Gx(roi_mask);
    Gy_masked = Gy(roi_mask);
    
    % We want HORIZONTAL EDGES = strong Gy (vertical gradient)
    % Vertical edges = strong Gx (horizontal gradient)
    sum_horiz_edges = sum(abs(Gy_masked));  % Horizontal edges
    sum_vert_edges = sum(abs(Gx_masked));   % Vertical edges
    total_edges = sum_horiz_edges + sum_vert_edges;
    
    if total_edges < 1e-6
        h_layer_score = 0;
        h_periodicity = 0;
        edge_density = 0;
        return;
    end
    
    % h_layer_score: ratio of horizontal edges to total
    % High value means predominantly horizontal edges (like 3D print layers)
    h_layer_score = sum_horiz_edges / total_edges;
    
    % === Feature 2: Periodicity of horizontal edges ===
    % Project the vertical gradient onto horizontal axis (sum columns)
    % Then look for periodic pattern
    
    % Create a masked version of Gy
    Gy_masked_img = abs(Gy) .* double(roi_mask);
    
    % Average horizontal edge strength per row
    rowProfile = mean(Gy_masked_img, 2);
    
    % Compute autocorrelation to detect periodicity
    if length(rowProfile) > 10
        rowProfile = rowProfile - mean(rowProfile);
        autocorr = xcorr(rowProfile, 'coeff');
        % Take positive lags only
        autocorr = autocorr(ceil(length(autocorr)/2):end);
        
        % Find peaks in autocorrelation (indicates periodic structure)
        if length(autocorr) > 5
            % Look for secondary peaks (not the main peak at lag 0)
            [pks, ~] = findpeaks(autocorr(2:end), 'MinPeakProminence', 0.1);
            if ~isempty(pks)
                h_periodicity = max(pks);  % Strength of strongest periodic component
            else
                h_periodicity = 0;
            end
        else
            h_periodicity = 0;
        end
    else
        h_periodicity = 0;
    end
    
    % === Feature 3: Edge density (for reference, not used in clustering) ===
    edge_density = total_edges / sum(roi_mask(:));
end

%% ========================================================================
% DEBUG FIGURE FUNCTIONS
% ========================================================================

function saveStep1Debug(I_cropped, allMasks, numMasks, Hc, Wc, debugFolder, baseName, showFigures)
% STEP 1: All SAM masks
    if showFigures
        fig = figure('Position', [50 50 1400 500]);
    else
        fig = figure('Visible', 'off', 'Position', [50 50 1400 500]);
    end
    
    subplot(1,3,1);
    imshow(I_cropped);
    title('Original (cropped)', 'FontSize', 12);
    
    % Create colored overlay of all masks
    maskOverlay = zeros(Hc, Wc, 3);
    colors = lines(numMasks);
    for m = 1:numMasks
        thisMask = squeeze(allMasks(m, :, :));
        for c = 1:3
            channel = maskOverlay(:,:,c);
            channel(thisMask) = colors(m, c);
            maskOverlay(:,:,c) = channel;
        end
    end
    
    subplot(1,3,2);
    imshow(maskOverlay);
    title(sprintf('All %d SAM Masks (colored)', numMasks), 'FontSize', 12);
    
    subplot(1,3,3);
    imshow(maskOverlay * 0.5 + im2double(I_cropped) * 0.5);
    title('Overlay on Original', 'FontSize', 12);
    
    sgtitle('STEP 1: SAM Mask Generation', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step01_SAM_masks.png']));
        close(fig);
    end
end

function saveStep1bDebug(I_cropped, allMasks, allMasksFilled, numMasks, holesFilled, Hc, Wc, debugFolder, baseName, showFigures)
% STEP 1b: Hole filling in masks
    if showFigures
        fig = figure('Position', [50 50 1600 600]);
    else
        fig = figure('Visible', 'off', 'Position', [50 50 1600 600]);
    end
    
    % Show masks with most holes filled
    [~, sortIdx] = sort(holesFilled, 'descend');
    nShow = min(8, numMasks);
    
    for k = 1:nShow
        m = sortIdx(k);
        subplot(2, 4, k);
        
        origMask = squeeze(allMasks(m, :, :));
        filledMask = squeeze(allMasksFilled(m, :, :));
        holesMask = filledMask & ~origMask;
        
        % Create RGB: original in green, filled holes in red
        rgb = zeros(Hc, Wc, 3);
        rgb(:,:,2) = double(origMask) * 0.7;
        rgb(:,:,1) = double(holesMask);
        
        imshow(rgb * 0.8 + im2double(I_cropped) * 0.2);
        title(sprintf('M%d: +%d px filled', m, holesFilled(m)), 'FontSize', 10);
    end
    
    sgtitle(sprintf('STEP 1b: Hole Filling in Masks (showing top %d by holes filled)', nShow), 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step01b_hole_filling.png']));
        close(fig);
    end
end

function saveStep2Debug(textureFeatures, numMasks, debugFolder, baseName, showFigures)
% STEP 2: Texture features
    if showFigures
        fig = figure('Position', [100 100 1600 500]);
    else
        fig = figure('Visible', 'off', 'Position', [100 100 1600 500]);
    end
    
    subplot(1,4,1);
    bar(textureFeatures(:,1));
    xlabel('Mask Index');
    ylabel('H-Layer Score');
    title('Horizontal Layer Score', 'FontSize', 12);
    grid on;
    
    subplot(1,4,2);
    bar(textureFeatures(:,2));
    xlabel('Mask Index');
    ylabel('H-Periodicity');
    title('Horizontal Periodicity', 'FontSize', 12);
    grid on;
    
    subplot(1,4,3);
    bar(textureFeatures(:,3));
    xlabel('Mask Index');
    ylabel('Edge Density');
    title('Edge Density (reference)', 'FontSize', 12);
    grid on;
    
    subplot(1,4,4);
    scatter(textureFeatures(:,1), textureFeatures(:,2), 100, 'filled');
    xlabel('H-Layer Score');
    ylabel('H-Periodicity');
    title('Layer Feature Space (for clustering)', 'FontSize', 12);
    grid on;
    for m = 1:numMasks
        text(textureFeatures(m,1)+0.01, textureFeatures(m,2)+0.01, sprintf('M%d', m), 'FontSize', 9);
    end
    
    sgtitle('STEP 2: Horizontal Layer Texture Features (3D Print Specific)', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step02_texture_features.png']));
        close(fig);
    end
end

function saveStep3Debug(I_cropped, allMasks, numMasks, textureFeatures, ...
    clusterIdx, isTextured, isNonTextured, centroids, Hc, Wc, debugFolder, baseName, showFigures)
% STEP 3: Clustering
    if showFigures
        fig = figure('Position', [150 150 1400 500]);
    else
        fig = figure('Visible', 'off', 'Position', [150 150 1400 500]);
    end
    
    subplot(1,3,1);
    % Plot using h_layer_score and h_periodicity (features used for clustering)
    gscatter(textureFeatures(:,1), textureFeatures(:,2), clusterIdx, 'rb', 'ox', 10);
    hold on;
    % Plot centroids in original space
    centroidsOrig = zeros(2,2);
    centroidsOrig(:,1) = centroids(:,1) * (max(textureFeatures(:,1)) - min(textureFeatures(:,1))) + min(textureFeatures(:,1));
    centroidsOrig(:,2) = centroids(:,2) * (max(textureFeatures(:,2)) - min(textureFeatures(:,2))) + min(textureFeatures(:,2));
    plot(centroidsOrig(:,1), centroidsOrig(:,2), 'kp', 'MarkerSize', 15, 'MarkerFaceColor', 'y');
    hold off;
    xlabel('H-Layer Score');
    ylabel('H-Periodicity');
    title('K-Means Clustering (k=2)', 'FontSize', 12);
    legend('Cluster 1', 'Cluster 2', 'Centroids', 'Location', 'best');
    grid on;
    for m = 1:numMasks
        text(textureFeatures(m,1)+0.01, textureFeatures(m,2)+0.01, sprintf('M%d', m), 'FontSize', 8);
    end
    
    subplot(1,3,2);
    % Show textured masks (red)
    texturedOverlay = zeros(Hc, Wc, 3);
    for m = find(isTextured)'
        thisMask = squeeze(allMasks(m, :, :));
        texturedOverlay(:,:,1) = texturedOverlay(:,:,1) + double(thisMask);
    end
    texturedOverlay = min(texturedOverlay, 1);
    imshow(texturedOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('Textured/3D-Printed (%d masks) - RED', sum(isTextured)), 'FontSize', 12);
    
    subplot(1,3,3);
    % Show non-textured masks (green)
    nonTexturedOverlay = zeros(Hc, Wc, 3);
    for m = find(isNonTextured)'
        thisMask = squeeze(allMasks(m, :, :));
        nonTexturedOverlay(:,:,2) = nonTexturedOverlay(:,:,2) + double(thisMask);
    end
    nonTexturedOverlay = min(nonTexturedOverlay, 1);
    imshow(nonTexturedOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('Non-Textured/Candidate (%d masks) - GREEN', sum(isNonTextured)), 'FontSize', 12);
    
    sgtitle('STEP 3: K-Means Clustering (H-Layer Score + Periodicity)', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step03_clustering.png']));
        close(fig);
    end
end

function saveStep4Debug(I_cropped, BW_3d_printed_mask, debugFolder, baseName, showFigures)
% STEP 4: 3D-printed structure mask
    if showFigures
        fig = figure('Position', [200 200 1200 400]);
    else
        fig = figure('Visible', 'off', 'Position', [200 200 1200 400]);
    end
    
    subplot(1,3,1);
    imshow(I_cropped);
    title('Original', 'FontSize', 12);
    
    subplot(1,3,2);
    imshow(BW_3d_printed_mask);
    title(sprintf('BW\\_3d\\_printed\\_mask (%d px)', sum(BW_3d_printed_mask(:))), 'FontSize', 12);
    
    subplot(1,3,3);
    imshow(labeloverlay(I_cropped, BW_3d_printed_mask, 'Colormap', [1 0 0], 'Transparency', 0.5));
    title('Structure Overlay (red)', 'FontSize', 12);
    
    sgtitle('STEP 4: Merged 3D-Printed Structure Mask', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step04_3d_printed_mask.png']));
        close(fig);
    end
end

function saveStep5Debug(I_cropped, allMasks, numMasks, isNonTextured, ...
    maskTouchesBorder, maskValid, BW_non_textured_filtered, Hc, Wc, debugFolder, baseName, showFigures)
% STEP 5: Non-textured mask filtering
    if showFigures
        fig = figure('Position', [250 250 1600 500]);
    else
        fig = figure('Visible', 'off', 'Position', [250 250 1600 500]);
    end
    
    subplot(1,4,1);
    imshow(I_cropped);
    title('Original', 'FontSize', 12);
    
    subplot(1,4,2);
    % Show all non-textured (before filtering)
    allNonTex = false(Hc, Wc);
    for m = find(isNonTextured)'
        allNonTex = allNonTex | squeeze(allMasks(m, :, :));
    end
    imshow(allNonTex);
    title(sprintf('All Non-Textured (%d masks)', sum(isNonTextured)), 'FontSize', 12);
    
    subplot(1,4,3);
    % Show removed (border-touching) in red, kept in green
    removedMask = false(Hc, Wc);
    for m = 1:numMasks
        if isNonTextured(m) && maskTouchesBorder(m)
            removedMask = removedMask | squeeze(allMasks(m, :, :));
        end
    end
    rgb = zeros(Hc, Wc, 3);
    rgb(:,:,1) = double(removedMask);
    rgb(:,:,2) = double(BW_non_textured_filtered);
    imshow(rgb);
    title(sprintf('Removed(red)=%d, Kept(green)=%d', ...
        sum(isNonTextured & maskTouchesBorder), sum(maskValid)), 'FontSize', 11);
    
    subplot(1,4,4);
    imshow(labeloverlay(I_cropped, BW_non_textured_filtered, 'Colormap', [0 1 0], 'Transparency', 0.5));
    title('Valid Non-Textured (green)', 'FontSize', 12);
    
    sgtitle('STEP 5: Filter Non-Textured Masks (Remove Border-Touching)', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step05_nontextured_filtering.png']));
        close(fig);
    end
end

function saveStep6Debug(Igray_cropped_u8, I_fill, I_inv, I_inv_fill, ...
    I_fill_from_inv, mask_holes_gray, mask_holes_inv, debugFolder, baseName, showFigures)
% STEP 6: Grayscale hole-filling
    if showFigures
        fig = figure('Position', [300 300 1600 700]);
    else
        fig = figure('Visible', 'off', 'Position', [300 300 1600 700]);
    end
    
    subplot(2,4,1);
    imshow(Igray_cropped_u8);
    title('Original Grayscale', 'FontSize', 11);
    
    subplot(2,4,2);
    imshow(I_fill);
    title('After imfill (grayscale)', 'FontSize', 11);
    
    subplot(2,4,3);
    imshow(I_fill - Igray_cropped_u8, []);
    title('Difference (holes filled)', 'FontSize', 11);
    colormap(gca, 'jet');
    
    subplot(2,4,4);
    imshow(mask_holes_gray);
    title(sprintf('mask\\_holes\\_gray (%d px)', sum(mask_holes_gray(:))), 'FontSize', 11);
    
    subplot(2,4,5);
    imshow(I_inv);
    title('Inverse Grayscale', 'FontSize', 11);
    
    subplot(2,4,6);
    imshow(I_fill_from_inv);
    title('After imfill (inverse back)', 'FontSize', 11);
    
    subplot(2,4,7);
    imshow(Igray_cropped_u8 - I_fill_from_inv, []);
    title('Difference (inverse holes)', 'FontSize', 11);
    colormap(gca, 'jet');
    
    subplot(2,4,8);
    imshow(mask_holes_inv);
    title(sprintf('mask\\_holes\\_inv (%d px)', sum(mask_holes_inv(:))), 'FontSize', 11);
    
    sgtitle('STEP 6: Grayscale Hole-Filling (Original and Inverse)', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step06_hole_filling.png']));
        close(fig);
    end
end

function saveStep7Debug(mask_holes_gray, mask_holes_inv, BW_3d_printed_mask, ...
    mask_holes_gray_clean, mask_holes_inv_clean, debugFolder, baseName, showFigures)
% STEP 7: Remove 3D-printed region from hole masks
    if showFigures
        fig = figure('Position', [350 350 1400 500]);
    else
        fig = figure('Visible', 'off', 'Position', [350 350 1400 500]);
    end
    
    subplot(2,3,1);
    imshow(mask_holes_gray);
    title(sprintf('mask\\_holes\\_gray (raw)\n%d px', sum(mask_holes_gray(:))), 'FontSize', 11);
    
    subplot(2,3,2);
    imshow(BW_3d_printed_mask);
    title('BW\_3d\_printed\_mask', 'FontSize', 11);
    
    subplot(2,3,3);
    imshow(mask_holes_gray_clean);
    title(sprintf('mask\\_holes\\_gray\\_clean\n%d px', sum(mask_holes_gray_clean(:))), 'FontSize', 11);
    
    subplot(2,3,4);
    imshow(mask_holes_inv);
    title(sprintf('mask\\_holes\\_inv (raw)\n%d px', sum(mask_holes_inv(:))), 'FontSize', 11);
    
    subplot(2,3,5);
    imshow(BW_3d_printed_mask);
    title('BW\_3d\_printed\_mask', 'FontSize', 11);
    
    subplot(2,3,6);
    imshow(mask_holes_inv_clean);
    title(sprintf('mask\\_holes\\_inv\\_clean\n%d px', sum(mask_holes_inv_clean(:))), 'FontSize', 11);
    
    sgtitle('STEP 7: Remove 3D-Printed Region from Hole Masks', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step07_clean_hole_masks.png']));
        close(fig);
    end
end

function saveStep8Debug(I_cropped, combined_abs_diff, combined_abs_diff_clean, ...
    BW_3d_printed_mask, debugFolder, baseName, showFigures)
% STEP 8: Combined absolute difference
    if showFigures
        fig = figure('Position', [400 100 1400 400]);
    else
        fig = figure('Visible', 'off', 'Position', [400 100 1400 400]);
    end
    
    subplot(1,4,1);
    imshow(I_cropped);
    title('Original', 'FontSize', 12);
    
    subplot(1,4,2);
    imagesc(combined_abs_diff); axis image; colorbar;
    title('Combined Abs Diff (raw)', 'FontSize', 12);
    colormap(gca, 'hot');
    
    subplot(1,4,3);
    imagesc(combined_abs_diff_clean); axis image; colorbar;
    title('Combined Abs Diff (clean)', 'FontSize', 12);
    colormap(gca, 'hot');
    
    subplot(1,4,4);
    % Overlay showing what was removed
    rgb = zeros(size(I_cropped));
    maxVal = max(combined_abs_diff(:)) + eps;
    combined_norm = combined_abs_diff / maxVal;
    rgb(:,:,1) = combined_norm;
    rgb(:,:,2) = double(~BW_3d_printed_mask) .* combined_norm;
    rgb(:,:,3) = 0;
    imshow(rgb * 0.7 + im2double(I_cropped) * 0.3);
    title('Red=removed, Yellow=kept', 'FontSize', 12);
    
    sgtitle('STEP 8: Combined Absolute Difference Map', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step08_combined_diff.png']));
        close(fig);
    end
end

function saveStep9Debug(I_cropped, allMasks, numMasks, maskAreas, maskMeanScores, ...
    maskRobustScores, maskEnrichment, maskValid, isTextured, maskTouchesBorder, ...
    Hc, Wc, debugFolder, baseName, showFigures)
% STEP 9: Scoring
    if showFigures
        fig = figure('Position', [100 100 1800 600]);
    else
        fig = figure('Visible', 'off', 'Position', [100 100 1800 600]);
    end
    
    [~, bestIdx] = max(maskRobustScores);
    
    subplot(2,5,1);
    bar(maskAreas);
    xlabel('Mask'); ylabel('Area (px)');
    title('Mask Areas', 'FontSize', 11);
    grid on;
    
    subplot(2,5,2);
    bar(maskMeanScores);
    xlabel('Mask'); ylabel('Mean Score');
    title('Mean Scores', 'FontSize', 11);
    grid on;
    
    subplot(2,5,3);
    bar(maskEnrichment);
    hold on;
    yline(2.0, 'r--', 'LineWidth', 1.5);
    hold off;
    xlabel('Mask'); ylabel('Enrichment');
    title('Signal Enrichment', 'FontSize', 11);
    grid on;
    
    subplot(2,5,4);
    b = bar(maskRobustScores);
    b.FaceColor = 'flat';
    barColors = repmat([0.5 0.5 0.5], numMasks, 1);  % Gray = invalid
    barColors(maskValid, :) = repmat([0 0.5 1], sum(maskValid), 1);  % Blue = valid
    barColors(isTextured, :) = repmat([0.8 0 0], sum(isTextured), 1);  % Red = textured
    if bestIdx > 0 && bestIdx <= numMasks && maskRobustScores(bestIdx) > 0
        barColors(bestIdx, :) = [0 0.8 0];  % Green = best
    end
    b.CData = barColors;
    xlabel('Mask'); ylabel('Robust Score');
    title(sprintf('Robust Scores (best=M%d)', bestIdx), 'FontSize', 11);
    grid on;
    
    subplot(2,5,5);
    % Legend/explanation
    axis off;
    text(0.1, 0.9, 'SCORING:', 'FontSize', 11, 'FontWeight', 'bold');
    text(0.1, 0.75, 'robust = mean × √(area)', 'FontSize', 10);
    text(0.1, 0.55, 'Bar Colors:', 'FontSize', 10, 'FontWeight', 'bold');
    text(0.1, 0.45, '• Green = Best valid', 'FontSize', 9, 'Color', [0 0.6 0]);
    text(0.1, 0.35, '• Blue = Valid candidate', 'FontSize', 9, 'Color', [0 0 0.8]);
    text(0.1, 0.25, '• Red = Textured (excluded)', 'FontSize', 9, 'Color', [0.8 0 0]);
    text(0.1, 0.15, '• Gray = Border-touching', 'FontSize', 9, 'Color', [0.5 0.5 0.5]);
    
    subplot(2,5,6);
    % Textured masks (excluded)
    texturedOverlay = zeros(Hc, Wc, 3);
    for m = find(isTextured)'
        texturedOverlay(:,:,1) = texturedOverlay(:,:,1) | double(squeeze(allMasks(m, :, :)));
    end
    imshow(texturedOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('Textured (excluded): %d', sum(isTextured)), 'FontSize', 10);
    
    subplot(2,5,7);
    % Border-touching non-textured (excluded)
    borderOverlay = zeros(Hc, Wc, 3);
    for m = 1:numMasks
        if ~isTextured(m) && maskTouchesBorder(m)
            thisMask = squeeze(allMasks(m, :, :));
            borderOverlay(:,:,1) = borderOverlay(:,:,1) | double(thisMask);
            borderOverlay(:,:,2) = borderOverlay(:,:,2) | double(thisMask) * 0.5;
        end
    end
    borderOverlay = min(borderOverlay, 1);
    imshow(borderOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('Border-touching: %d', sum(~isTextured & maskTouchesBorder)), 'FontSize', 10);
    
    subplot(2,5,8);
    % Valid candidates
    validOverlay = zeros(Hc, Wc, 3);
    for m = find(maskValid)'
        validOverlay(:,:,2) = validOverlay(:,:,2) | double(squeeze(allMasks(m, :, :)));
    end
    imshow(validOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('Valid candidates: %d', sum(maskValid)), 'FontSize', 10);
    
    subplot(2,5,9);
    % Best mask
    if bestIdx > 0 && maskRobustScores(bestIdx) > 0
        bestMask = squeeze(allMasks(bestIdx, :, :));
        imshow(labeloverlay(I_cropped, bestMask, 'Colormap', [0 1 0], 'Transparency', 0.4));
        title(sprintf('Best: M%d (R=%.0f)', bestIdx, maskRobustScores(bestIdx)), 'FontSize', 10);
    else
        imshow(I_cropped);
        title('No valid best mask', 'FontSize', 10);
    end
    
    subplot(2,5,10);
    % Scatter plot
    if sum(maskValid) > 0
        scatter(maskAreas(maskValid), maskRobustScores(maskValid), 80, 'b', 'filled');
        hold on;
        if bestIdx > 0 && maskRobustScores(bestIdx) > 0
            scatter(maskAreas(bestIdx), maskRobustScores(bestIdx), 150, 'g', 'filled', ...
                'MarkerEdgeColor', 'k', 'LineWidth', 2);
        end
        hold off;
    end
    xlabel('Area'); ylabel('Robust Score');
    title('Valid masks: Area vs Score', 'FontSize', 10);
    grid on;
    
    sgtitle('STEP 9: Mask Scoring (Only Valid Non-Textured Candidates)', 'FontSize', 14);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step09_scoring.png']));
        close(fig);
    end
end

function saveStep10Debug(I_cropped, allMasks, numMasks, maskValid, isTextured, ...
    maskTouchesBorder, maskRobustScores, maskEnrichment, bestIdx, Hc, Wc, debugFolder, baseName, showFigures)
% STEP 10: All masks gallery
    if showFigures
        fig = figure('Position', [50 50 1600 900]);
    else
        fig = figure('Visible', 'off', 'Position', [50 50 1600 900]);
    end
    
    nCols = 4;
    nRows = ceil(numMasks / nCols);
    
    for m = 1:numMasks
        subplot(nRows, nCols, m);
        thisMask = squeeze(allMasks(m, :, :));
        
        if m == bestIdx && maskRobustScores(bestIdx) > 0
            overlay = labeloverlay(I_cropped, thisMask, 'Colormap', [0 1 0], 'Transparency', 0.3);
            titleColor = [0 0.6 0];
            titleStr = sprintf('*M%d* R=%.0f E=%.1f', m, maskRobustScores(m), maskEnrichment(m));
        elseif isTextured(m)
            overlay = labeloverlay(I_cropped, thisMask, 'Colormap', [1 0 0], 'Transparency', 0.5);
            titleColor = [0.8 0 0];
            titleStr = sprintf('M%d [textured]', m);
        elseif maskTouchesBorder(m)
            overlay = labeloverlay(I_cropped, thisMask, 'Colormap', [0.7 0.7 0], 'Transparency', 0.5);
            titleColor = [0.6 0.6 0];
            titleStr = sprintf('M%d [border]', m);
        else
            overlay = labeloverlay(I_cropped, thisMask, 'Colormap', [0 0.5 1], 'Transparency', 0.5);
            titleColor = [0 0 0.8];
            titleStr = sprintf('M%d R=%.0f E=%.1f', m, maskRobustScores(m), maskEnrichment(m));
        end
        
        imshow(overlay);
        title(titleStr, 'FontSize', 9, 'Color', titleColor);
    end
    
    sgtitle('STEP 10: All Masks Gallery (Green=Best, Red=Textured, Yellow=Border, Blue=Valid)', 'FontSize', 13);
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step10_gallery.png']));
        close(fig);
    end
end

function saveFinalDebug(I_cropped, BW_3d_printed_mask, BW_lumen_cropped, quality, debugFolder, baseName, showFigures)
% Final result figure
    if showFigures
        fig = figure('Position', [450 150 1400 500]);
    else
        fig = figure('Visible', 'off', 'Position', [450 150 1400 500]);
    end
    
    [Hc, Wc, ~] = size(I_cropped);
    
    subplot(1,4,1);
    imshow(I_cropped);
    title('Original', 'FontSize', 12);
    
    subplot(1,4,2);
    imshow(BW_3d_printed_mask);
    title('3D-Printed Structure', 'FontSize', 12);
    
    subplot(1,4,3);
    if any(BW_lumen_cropped(:))
        imshow(BW_lumen_cropped);
        title(sprintf('Selected Lumen\n(Area=%d px)', sum(BW_lumen_cropped(:))), 'FontSize', 12);
    else
        imshow(BW_lumen_cropped);
        title('No Lumen Detected', 'FontSize', 12, 'Color', 'r');
    end
    
    subplot(1,4,4);
    % Combined overlay
    overlay = im2double(I_cropped);
    % Structure in red
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 1
            ch(BW_3d_printed_mask) = ch(BW_3d_printed_mask) * 0.5 + 0.5;
        else
            ch(BW_3d_printed_mask) = ch(BW_3d_printed_mask) * 0.5;
        end
        overlay(:,:,c) = ch;
    end
    % Lumen in green
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 2
            ch(BW_lumen_cropped) = ch(BW_lumen_cropped) * 0.5 + 0.5;
        else
            ch(BW_lumen_cropped) = ch(BW_lumen_cropped) * 0.5;
        end
        overlay(:,:,c) = ch;
    end
    imshow(overlay);
    title('Structure(red) + Lumen(green)', 'FontSize', 12);
    
    if quality.lumen_valid
        sgtitle(sprintf('FINAL RESULT: %s (Area=%d px)', quality.status, quality.lumen_area_px), ...
            'FontSize', 14, 'Color', [0 0.6 0]);
    else
        sgtitle(sprintf('FINAL RESULT: %s - %s', quality.status, quality.rejection_reason), ...
            'FontSize', 13, 'Color', [0.8 0 0], 'Interpreter', 'none');
    end
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_step11_final_result.png']));
        close(fig);
    end
end

function saveSummaryDebug(I_cropped, allMasks, allMasksFilled, numMasks, textureFeatures, ...
    clusterIdx, isTextured, BW_3d_printed_mask, maskValid, ...
    combined_abs_diff_clean, maskRobustScores, bestIdx, ...
    BW_lumen_cropped, quality, Hc, Wc, debugFolder, baseName, showFigures)
% Complete pipeline summary
    if showFigures
        fig = figure('Position', [100 50 1800 900]);
    else
        fig = figure('Visible', 'off', 'Position', [100 50 1800 900]);
    end
    
    % Row 1: SAM and texture clustering
    subplot(3,4,1);
    imshow(I_cropped);
    title('1. Original', 'FontSize', 10);
    
    subplot(3,4,2);
    maskOverlay = zeros(Hc, Wc, 3);
    colors = lines(numMasks);
    for m = 1:numMasks
        thisMask = squeeze(allMasks(m, :, :));
                for c = 1:3
            channel = maskOverlay(:,:,c);
            channel(thisMask) = colors(m, c);
            maskOverlay(:,:,c) = channel;
        end
    end
    imshow(maskOverlay * 0.6 + im2double(I_cropped) * 0.4);
    title(sprintf('2. SAM (%d masks)', numMasks), 'FontSize', 10);
    
    subplot(3,4,3);
    % Use h_layer_score and h_periodicity for clustering plot
    gscatter(textureFeatures(:,1), textureFeatures(:,2), clusterIdx, 'rb', 'ox', 8);
    xlabel('H-Layer'); ylabel('Periodicity');
    title('3. Layer Texture Clustering', 'FontSize', 10);
    grid on;
    
    subplot(3,4,4);
    imshow(BW_3d_printed_mask);
    title(sprintf('4. 3D-Printed (%d px)', sum(BW_3d_printed_mask(:))), 'FontSize', 10);
    
    % Row 2: Filtering and hole-filling
    subplot(3,4,5);
    % Textured vs non-textured
    texOverlay = zeros(Hc, Wc, 3);
    for m = find(isTextured)'
        texOverlay(:,:,1) = texOverlay(:,:,1) | double(squeeze(allMasks(m, :, :)));
    end
    for m = find(maskValid)'
        texOverlay(:,:,2) = texOverlay(:,:,2) | double(squeeze(allMasks(m, :, :)));
    end
    imshow(texOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('5. Tex(R)=%d, Valid(G)=%d', sum(isTextured), sum(maskValid)), 'FontSize', 10);
    
    subplot(3,4,6);
    imagesc(combined_abs_diff_clean); axis image;
    colormap(gca, 'hot');
    title('6. Hole-fill Diff (clean)', 'FontSize', 10);
    
    subplot(3,4,7);
    b = bar(maskRobustScores);
    b.FaceColor = 'flat';
    barColors = repmat([0.5 0.5 0.5], numMasks, 1);
    barColors(maskValid, :) = repmat([0.3 0.3 1], sum(maskValid), 1);
    barColors(isTextured, :) = repmat([0.8 0 0], sum(isTextured), 1);
    if bestIdx > 0 && maskRobustScores(bestIdx) > 0
        barColors(bestIdx, :) = [0 0.8 0];
    end
    b.CData = barColors;
    xlabel('Mask');
    title(sprintf('7. Scores (best=M%d)', bestIdx), 'FontSize', 10);
    
    subplot(3,4,8);
    if any(BW_lumen_cropped(:))
        imshow(labeloverlay(I_cropped, BW_lumen_cropped, 'Colormap', [0 1 0], 'Transparency', 0.4));
        title(sprintf('8. Lumen: M%d (%d px)', bestIdx, sum(BW_lumen_cropped(:))), 'FontSize', 10);
    else
        imshow(I_cropped);
        title('8. No Lumen Detected', 'FontSize', 10, 'Color', 'r');
    end
    
    % Row 3: Final results and metrics
    subplot(3,4,9);
    % Combined overlay
    overlay = im2double(I_cropped);
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 1
            ch(BW_3d_printed_mask) = ch(BW_3d_printed_mask) * 0.5 + 0.5;
        else
            ch(BW_3d_printed_mask) = ch(BW_3d_printed_mask) * 0.5;
        end
        overlay(:,:,c) = ch;
    end
    for c = 1:3
        ch = overlay(:,:,c);
        if c == 2
            ch(BW_lumen_cropped) = ch(BW_lumen_cropped) * 0.5 + 0.5;
        else
            ch(BW_lumen_cropped) = ch(BW_lumen_cropped) * 0.5;
        end
        overlay(:,:,c) = ch;
    end
    imshow(overlay);
    title('9. RESULT', 'FontSize', 12, 'FontWeight', 'bold');
    
    subplot(3,4,10);
    axis off;
    text(0.05, 0.95, 'PIPELINE:', 'FontSize', 10, 'FontWeight', 'bold');
    text(0.05, 0.82, '1. SAM segmentation', 'FontSize', 9);
    text(0.05, 0.70, '2. Fill holes in masks', 'FontSize', 9);
    text(0.05, 0.58, '3. H-layer texture features', 'FontSize', 9);
    text(0.05, 0.46, '4. K-means clustering (k=2)', 'FontSize', 9);
    text(0.05, 0.34, '5. Filter: non-textured only', 'FontSize', 9);
    text(0.05, 0.22, '6. Hole-fill scoring', 'FontSize', 9);
    text(0.05, 0.10, '7. Select best candidate', 'FontSize', 9);
    
    subplot(3,4,11);
    axis off;
    text(0.05, 0.95, 'QUALITY METRICS:', 'FontSize', 10, 'FontWeight', 'bold');
    statusColor = 'g';
    if ~quality.lumen_valid
        statusColor = 'r';
    end
    text(0.05, 0.80, sprintf('Status: %s', quality.status), 'FontSize', 9, 'Color', statusColor);
    text(0.05, 0.68, sprintf('Valid: %d', quality.lumen_valid), 'FontSize', 9);
    text(0.05, 0.56, sprintf('Best Mask: M%d', quality.best_mask_index), 'FontSize', 9);
    text(0.05, 0.44, sprintf('Area: %d px', quality.lumen_area_px), 'FontSize', 9);
    text(0.05, 0.32, sprintf('Mean Score: %.1f', quality.mean_score), 'FontSize', 9);
    text(0.05, 0.20, sprintf('Enrichment: %.1fx', quality.enrichment), 'FontSize', 9);
    text(0.05, 0.08, sprintf('Z-Score: %.2f', quality.z_score), 'FontSize', 9);
    
    subplot(3,4,12);
    axis off;
    text(0.05, 0.95, 'MASK COUNTS:', 'FontSize', 10, 'FontWeight', 'bold');
    text(0.05, 0.80, sprintf('Total SAM masks: %d', numMasks), 'FontSize', 9);
    text(0.05, 0.65, sprintf('Textured (3D-printed): %d', quality.num_textured_masks), 'FontSize', 9, 'Color', [0.8 0 0]);
    text(0.05, 0.50, sprintf('Non-textured: %d', quality.num_nontextured_masks), 'FontSize', 9);
    text(0.05, 0.35, sprintf('Valid candidates: %d', quality.num_valid_masks), 'FontSize', 9, 'Color', [0 0 0.8]);
    if ~isempty(quality.rejection_reason)
        text(0.05, 0.15, sprintf('Rejection: %s', quality.rejection_reason), ...
            'FontSize', 8, 'Color', 'r', 'Interpreter', 'none');
    end
    
    sgtitle(sprintf('%s - LAYER-TEXTURE LUMEN DETECTION', baseName), ...
        'FontSize', 14, 'FontWeight', 'bold', 'Interpreter', 'none');
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_SUMMARY.png']));
        close(fig);
    end
end

function saveFailureDebug(I_cropped, allMasks, numMasks, isTextured, ...
    maskTouchesBorder, BW_3d_printed_mask, Hc, Wc, debugFolder, baseName, rejectionReason, showFigures)
% Save debug figure when all masks are rejected early

    if showFigures
        fig = figure('Position', [50 50 1600 500]);
    else
        fig = figure('Visible', 'off', 'Position', [50 50 1600 500]);
    end
    
    subplot(1,4,1);
    imshow(I_cropped);
    title('Original', 'FontSize', 11);
    
    subplot(1,4,2);
    % Show all masks colored by type
    maskOverlay = zeros(Hc, Wc, 3);
    colors = lines(numMasks);
    for m = 1:numMasks
        thisMask = squeeze(allMasks(m, :, :));
        for c = 1:3
            channel = maskOverlay(:,:,c);
            channel(thisMask) = colors(m, c);
            maskOverlay(:,:,c) = channel;
        end
    end
    imshow(maskOverlay * 0.6 + im2double(I_cropped) * 0.4);
    title(sprintf('SAM (%d masks)', numMasks), 'FontSize', 11);
    
    subplot(1,4,3);
    % Show textured (red) vs non-textured that touch border (yellow)
    classOverlay = zeros(Hc, Wc, 3);
    for m = 1:numMasks
        thisMask = squeeze(allMasks(m, :, :));
        if isTextured(m)
            % Red for textured
            classOverlay(:,:,1) = classOverlay(:,:,1) | double(thisMask);
        elseif maskTouchesBorder(m)
            % Yellow for border-touching non-textured
            classOverlay(:,:,1) = classOverlay(:,:,1) | double(thisMask) * 0.8;
            classOverlay(:,:,2) = classOverlay(:,:,2) | double(thisMask) * 0.8;
        end
    end
    classOverlay = min(classOverlay, 1);
    imshow(classOverlay * 0.7 + im2double(I_cropped) * 0.3);
    title(sprintf('Textured(red)=%d, Border(yellow)=%d', ...
        sum(isTextured), sum(~isTextured & maskTouchesBorder)), 'FontSize', 10);
    
    subplot(1,4,4);
    % Show the 3D-printed mask
    imshow(labeloverlay(I_cropped, BW_3d_printed_mask, 'Colormap', [1 0 0], 'Transparency', 0.5));
    title('3D-Printed Structure (red)', 'FontSize', 11);
    
    sgtitle(sprintf('%s - FAILED: %s', baseName, rejectionReason), ...
        'Interpreter', 'none', 'FontSize', 12, 'Color', 'r');
    
    if ~showFigures
        saveas(fig, fullfile(debugFolder, [baseName '_FAILED.png']));
        close(fig);
    end
    
end