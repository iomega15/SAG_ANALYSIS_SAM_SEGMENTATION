function [BWlumen, quality] = segmentLumenSAM(I, roi, debugFolder, baseName)
% SEGMENTLUMENSAM: Center-based SAM + Texture Clustering Validation
%
% Uses center-point SAM to find lumen candidate, then validates it
% belongs to the non-textured cluster (not 3D-printed material).
% Also detects polarity (bright/dark lumen).
%
% Inputs:
%   I           - Input image (RGB or grayscale)
%   roi         - Struct with roi.bottomFrac field
%   debugFolder - (Optional) Path to save debug figures
%   baseName    - (Optional) Base filename for debug images
%
% Outputs:
%   BWlumen     - Binary lumen mask (full image size)
%   quality     - Struct with quality metrics including:
%                 .status, .lumen_valid, .confidence, .polarity,
%                 .diff_gray, .diff_inv, .is_textured, etc.

%% ====================================================================
% DEBUG DISPLAY OPTION
% Set to true to display figures on screen instead of saving to files
% =====================================================================
SHOW_DEBUG_FIGURES = false;

%% ====================================================================
% INITIALIZE
% =====================================================================
quality = struct();
quality.status = 'unknown';
quality.lumen_valid = false;
quality.confidence = 0;
quality.polarity = 'unknown';
quality.diff_gray = 0;
quality.diff_inv = 0;
quality.is_textured = false;
quality.num_masks = 0;
quality.num_textured_masks = 0;
quality.num_nontextured_masks = 0;
quality.rejection_reason = '';

% Handle optional arguments
if nargin < 3
    debugFolder = '';
end
if nargin < 4
    baseName = 'image';
end

saveDebug = ~isempty(debugFolder) && exist(debugFolder, 'dir');

%% ====================================================================
% STEP 0: INPUT PREPARATION: Converts the image to grayscale and crops out the bottom strip (scale bar region).
% The center point is calculated as the center of the valid region only (i.e. after accounting for the strip height),
% so SAM is correctly prompted at the center of the actual image content, not the full image including the ruler.
% =====================================================================
if ismatrix(I)
    Irgb = repmat(I, [1 1 3]);
else
    Irgb = I;
end
[H, W, ~] = size(Irgb);
Igray = rgb2gray(Irgb);
Igray_u8 = im2uint8(Igray);
Igray_dbl = im2double(Igray);

% Calculate center point (ignoring bottom ROI)
h_roi = round(H * roi.bottomFrac);
h_valid = H - h_roi;
target_x = round(W / 2);
target_y = round(h_valid / 2);

% Crop out bottom band for processing
I_cropped = Irgb(1:h_valid, :, :);
Igray_cropped_u8 = Igray_u8(1:h_valid, :);
Igray_cropped_dbl = Igray_dbl(1:h_valid, :);
[Hc, Wc] = size(Igray_cropped_u8);

% Initialize output
BWlumen = false(H, W);
%BW_lumen_cropped = false(Hc, Wc);

% --- DEBUG 0: Input Image and Target Point ---
if saveDebug || SHOW_DEBUG_FIGURES
    saveStep0Debug(Irgb, I_cropped, H, W, h_valid, h_roi, target_x, target_y, ...
        debugFolder, baseName, SHOW_DEBUG_FIGURES);
end

%% ====================================================================
% STEP 1: SETUP SAM. Saves the cropped image to a temp file and checks that the SAM model checkpoint exists before running.
% =====================================================================
tempFile = fullfile(tempdir, 'temp_sam_input.png');
imwrite(I_cropped, tempFile);  % Save cropped image

checkpointFile = fullfile(fileparts(pwd), 'sam_vit_b_01ec64.pth');
if ~exist(checkpointFile, 'file')
    if exist(fullfile(pwd, 'sam_vit_b_01ec64.pth'), 'file')
        checkpointFile = fullfile(pwd, 'sam_vit_b_01ec64.pth');
    else
        quality.status = 'checkpoint_not_found';
        quality.rejection_reason = 'SAM checkpoint not found';
        warning('SAM checkpoint not found');
        if exist(tempFile, 'file'), delete(tempFile); end
        return;
    end
end

try
    %% ================================================================
    % STEP 2: RUN SAM - Get lumen mask AND all other masks. Runs the Segment Anything Model using the image center as a prompt point.
    % Returns the lumen candidate mask (the region SAM thinks contains the center point) plus all other masks it finds across the image.
    % ================================================================
    fprintf('Running SAM...\n');
    tic;

    % Adjust target_y for cropped image (it's already relative to top)
    target_y_cropped = target_y;  % Same since we cropped from top

    [lumen_mask_out, confidence_score, all_masks_out, num_masks] = pyrunfile( ...
        "sam_segment_all.py", ...
        ["lumen_mask_out", "confidence_score", "all_masks_out", "num_masks"], ...
        image_path=tempFile, ...
        checkpoint_path=checkpointFile, ...
        target_x=int32(target_x), ...
        target_y=int32(target_y_cropped));

    elapsed = toc;
    fprintf('SAM completed in %.1f seconds\n', elapsed);

    BW_center_raw = logical(lumen_mask_out);
    quality.confidence = double(confidence_score);

    allMasks = logical(all_masks_out);
    numMasks = double(num_masks);
    quality.num_masks = numMasks;

    % --- DEBUG 1: Raw SAM Output ---
    if saveDebug || SHOW_DEBUG_FIGURES
        saveStep1Debug(I_cropped, BW_center_raw, allMasks, numMasks, ...
            target_x, target_y_cropped, quality.confidence, ...
            Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
    end


    %% ================================================================
    % STEP 2.5: PREPARE NON-OVERLAPPING 'EXCLUSIVE' MASKS
    % Resolves overlapping SAM masks by assigning each pixel to only the smallest mask that contains it, so every pixel belongs to exactly one mask
    % Done once here so all subsequent steps use consistent masks
    % ================================================================
    if numMasks > 0
        allMasksExclusive = prepareExclusiveMasks(allMasks, numMasks, Hc, Wc);
    else
        allMasksExclusive = allMasks;
    end

    %% ================================================================
    % STEP 3: ADAPTIVE CLUSTER CLEANUP (Log-Area 3-Class Otsu)
    % Removes small disconnected specks from the SAM center mask using log-area clustering, keeping only the meaningful region(s).
    % ================================================================
    if any(BW_center_raw(:))
        rp = regionprops(BW_center_raw, 'Area', 'PixelIdxList', 'BoundingBox', 'Centroid');
        allAreas = [rp.Area];
        nRegions = numel(rp);

        if nRegions > 2
            logAreas = log10(allAreas + 1);

            try
                levels = multithresh(logAreas, 2);

                % Classify regions
                %class1_idx = find(logAreas < levels(1));          % Noise (smallest)
                class2_idx = find(logAreas >= levels(1) & logAreas < levels(2));  % Intermediate
                class3_idx = find(logAreas >= levels(2));         % Largest (keep)

                % Keep Class 3 (Largest)
                keepIdx = class3_idx;

                % Strategically keep Class 2 if closer to Class 3 threshold
                for k = class2_idx
                    if (levels(2) - logAreas(k)) < (logAreas(k) - levels(1))
                        keepIdx = [keepIdx, k];
                    end
                end

                removeIdx = setdiff(1:nRegions, keepIdx);

                % Build cleaned mask
                BW_center_cleaned = false(size(BW_center_raw));
                for idx = keepIdx
                    BW_center_cleaned(rp(idx).PixelIdxList) = true;
                end

            catch ME
                % Fallback: keep largest only
                [~, maxIdx] = max(allAreas);
                BW_center_cleaned = false(size(BW_center_raw));
                BW_center_cleaned(rp(maxIdx).PixelIdxList) = true;
                keepIdx = maxIdx;
                removeIdx = setdiff(1:nRegions, maxIdx);
            end
        else
            % Only 1-2 regions: keep the largest
            [~, maxIdx] = max(allAreas);
            BW_center_cleaned = false(size(BW_center_raw));
            BW_center_cleaned(rp(maxIdx).PixelIdxList) = true;
            keepIdx = maxIdx;
            removeIdx = setdiff(1:nRegions, maxIdx);
        end

        % --- DEBUG 2: Cluster Cleanup ---
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep2Debug(I_cropped, BW_center_raw, BW_center_cleaned, rp, ...
                allAreas, nRegions, keepIdx, removeIdx, ...
                debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
    else
        BW_center_cleaned = BW_center_raw;
        %nRegions = 0;
    end

    %% ================================================================
    % STEP 4: TEXTURE ANALYSIS - Classify all masks. Computes edge density for each exclusive mask.
    % Identifies and excludes the background mask (largest and brightest), then compares the lumen candidate's edge
    % density against the mean of the remaining masks. If the lumen is at least 2× smoother than the reference, it passes as genuine lumen.
    % ================================================================
    if numMasks > 0

        % Compute Canny edge density for each exclusive mask
        textureFeatures = zeros(numMasks, 1);
        for m = 1:numMasks
            thisMaskExclusive = squeeze(allMasksExclusive(m, :, :));
            textureFeatures(m) = computeHorizontalLayerTexture(Igray_cropped_dbl, thisMaskExclusive);
        end

        % Find background mask: largest-brightest non-lumen mask
        candidate_scores = zeros(numMasks-1, 1);
        candidate_idx    = 2:numMasks;
        for i = 1:numel(candidate_idx)
            m = candidate_idx(i);
            thisMask = squeeze(allMasksExclusive(m, :, :));
            if sum(thisMask(:)) > 0
                candidate_scores(i) = sum(thisMask(:)) * mean(Igray_cropped_dbl(thisMask));
            end
        end
        [~, bg_local] = max(candidate_scores);
        bg_mask_idx   = candidate_idx(bg_local);

        % Reference: only masks scoring above lumen (excludes background,
        % smooth outliers, anything clearly not 3D-printed)
        lumen_density = textureFeatures(1);
        reference_idx = setdiff(2:numMasks, bg_mask_idx);
        valid_ref_idx = reference_idx(textureFeatures(reference_idx) > lumen_density);

        % Area-weighted reference density
        reference_edges_total  = 0;
        reference_pixels_total = 0;
        for i = 1:numel(valid_ref_idx)
            m         = valid_ref_idx(i);
            thisMask  = squeeze(allMasksExclusive(m, :, :));
            mask_area = sum(thisMask(:));
            if mask_area > 0
                reference_edges_total  = reference_edges_total  + textureFeatures(m) * mask_area;
                reference_pixels_total = reference_pixels_total + mask_area;
            end
        end

        if reference_pixels_total > 0
            reference_density = reference_edges_total / reference_pixels_total;
        else
            reference_density = 0;
        end

        % Z-score: how many std below the reference is the lumen?
        ref_scores = textureFeatures(valid_ref_idx);
        if numel(ref_scores) >= 2
            ref_mean = mean(ref_scores);
            ref_std  = std(ref_scores);
            z_score  = (ref_mean - lumen_density) / (ref_std + 1e-6);
        elseif isscalar(ref_scores)
            z_score  = (ref_scores(1) - lumen_density) / (ref_scores(1) + 1e-6);
        else
            z_score  = 0;
        end

        quality.lumen_z_score         = z_score;
        quality.lumen_density         = lumen_density;
        quality.reference_density     = reference_density;

        if reference_density > 0 && z_score > 1.0
            isTextured    = textureFeatures > lumen_density * 2;
            isNonTextured = ~isTextured;
            quality.is_textured           = false;
            quality.num_textured_masks    = sum(isTextured);
            quality.num_nontextured_masks = sum(isNonTextured);
        else
            isTextured    = true(numMasks, 1);
            isNonTextured = false(numMasks, 1);
            quality.is_textured           = true;
            quality.num_textured_masks    = numMasks;
            quality.num_nontextured_masks = 0;
        end

        % --- DEBUG 4: Texture Classification ---
        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4TextureDebug(I_cropped, allMasksExclusive, textureFeatures, ...
                isTextured, isNonTextured, ...
                Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end
        %% ================================================================
        % STEP 5: SET LUMEN MASK
        % ================================================================
        if any(BW_center_cleaned(:))
            if ~quality.is_textured
                BW_lumen_cropped = BW_center_cleaned;
            else
                quality.status = 'no_lumen_formed';
                quality.lumen_valid = false;
                quality.rejection_reason = sprintf('Center mask edge density %.3f not distinct from 3D-printed reference %.3f', ...
                    lumen_density, reference_density);
                BW_lumen_cropped = false(Hc, Wc);
            end
        else
            quality.status = 'empty_mask';
            quality.lumen_valid = false;
            quality.rejection_reason = 'SAM returned empty mask at center';
            BW_lumen_cropped = false(Hc, Wc);
        end

        %% ================================================================
        % STEP 6: POLARITY DETECTION (only if valid lumen)
        % Determines whether the lumen is bright or dark by comparing grayscale hole-filling on the original vs inverted image.
        % ================================================================
        if any(BW_lumen_cropped(:)) && ~quality.is_textured
            % Grayscale hole-filling
            I_fill = imfill(Igray_cropped_u8);
            diff_gray = abs(double(I_fill) - double(Igray_cropped_u8));

            % Inverse hole-filling
            I_inv = imcomplement(Igray_cropped_u8);
            I_inv_fill = imfill(I_inv);
            I_fill_from_inv = imcomplement(I_inv_fill);
            diff_inv = abs(double(Igray_cropped_u8) - double(I_fill_from_inv));

            % Calculate masked differences
            total_diff_gray = sum(diff_gray(BW_lumen_cropped));
            total_diff_inv = sum(diff_inv(BW_lumen_cropped));

            quality.diff_gray = total_diff_gray;
            quality.diff_inv = total_diff_inv;

            % Determine polarity
            if total_diff_inv > total_diff_gray
                quality.polarity = 'bright';
            else
                quality.polarity = 'dark';
            end

            quality.status = 'good';
            quality.lumen_valid = true;
            quality.lumen_area_px = sum(BW_lumen_cropped(:));

            % --- DEBUG 6: Polarity Detection ---
            if saveDebug || SHOW_DEBUG_FIGURES
                saveStep6PolarityDebug(I_cropped, Igray_cropped_u8, BW_lumen_cropped, ...
                    I_fill, I_inv, I_fill_from_inv, diff_gray, diff_inv, ...
                    total_diff_gray, total_diff_inv, quality.polarity, ...
                    debugFolder, baseName, SHOW_DEBUG_FIGURES);
            end
        end

        %% ================================================================
        % STEP 7: FINAL SUMMARY: Saves a combined debug figure showing all intermediate results and the final outcome.
        % ================================================================
        if saveDebug || SHOW_DEBUG_FIGURES
            % Create 3D-printed mask for visualization
            BW_3d_printed = false(Hc, Wc);
            if numMasks > 0
                for m = find(isTextured)'
                    BW_3d_printed = BW_3d_printed | squeeze(allMasksExclusive(m, :, :));
                end
            end

            saveFinalSummaryDebug(I_cropped, Irgb, BW_center_raw, BW_lumen_cropped, ...
                BW_3d_printed, allMasksExclusive, numMasks, quality, ...
                target_x, target_y_cropped, h_valid, H, W, ...
                debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end % saveDebug || SHOW_DEBUG_FIGURES
    end %numMasks > 0
catch ME
    warning(['SAM Error: %s', ME.message]);
    quality.status = 'SAM_error';
    quality.lumen_valid = false;
    quality.rejection_reason = ME.message;
    BW_lumen_cropped = false(Hc, Wc);

    if saveDebug || SHOW_DEBUG_FIGURES
        saveErrorDebug(ME, debugFolder, baseName, SHOW_DEBUG_FIGURES);
    end
end

% Cleanup temp file
if exist(tempFile, 'file')
    delete(tempFile);
end

% Pad back to original size
BWlumen = false(H, W);
BWlumen(1:h_valid, :) = BW_lumen_cropped;

end

%% ========================================================================
% LOCAL FUNCTION: Compute horizontal layer texture
% ========================================================================
% function [h_layer_score, h_periodicity, edge_density] = computeHorizontalLayerTexture(Igray, mask)
%     if sum(mask(:)) < 100
%         h_layer_score = 0;
%         h_periodicity = 0;
%         edge_density = 0;
%         return;
%     end
%
%     % Get bounding box
%     [rows, cols] = find(mask);
%     y_min = max(1, min(rows) - 2);
%     y_max = min(size(Igray,1), max(rows) + 2);
%     x_min = max(1, min(cols) - 2);
%     x_max = min(size(Igray,2), max(cols) + 2);
%
%     roi_gray = Igray(y_min:y_max, x_min:x_max);
%     roi_mask = mask(y_min:y_max, x_min:x_max);
%
%     % Sobel gradients
%     [Gx, Gy] = imgradientxy(roi_gray, 'sobel');
%
%     Gx_masked = Gx(roi_mask);
%     Gy_masked = Gy(roi_mask);
%
%     sum_horiz_edges = sum(abs(Gy_masked));
%     sum_vert_edges = sum(abs(Gx_masked));
%     total_edges = sum_horiz_edges + sum_vert_edges;
%
%     if total_edges < 1e-6
%         h_layer_score = 0;
%         h_periodicity = 0;
%         edge_density = 0;
%         return;
%     end
%
%     h_layer_score = sum_horiz_edges / total_edges;
%
%     % Periodicity
%     Gy_masked_img = abs(Gy) .* double(roi_mask);
%     rowProfile = mean(Gy_masked_img, 2);
%
%     if length(rowProfile) > 10
%         rowProfile = rowProfile - mean(rowProfile);
%         autocorr_result = xcorr(rowProfile, 'coeff');
%         autocorr_result = autocorr_result(ceil(length(autocorr_result)/2):end);
%
%         if length(autocorr_result) > 5
%             [pks, ~] = findpeaks(autocorr_result(2:end), 'MinPeakProminence', 0.1);
%             if ~isempty(pks)
%                 h_periodicity = max(pks);
%             else
%                 h_periodicity = 0;
%             end
%         else
%             h_periodicity = 0;
%         end
%     else
%         h_periodicity = 0;
%     end
%
%     edge_density = total_edges / sum(roi_mask(:));
% end

%% ========================================================================
% DEBUG FUNCTIONS
% ========================================================================

function saveStep0Debug(Irgb, I_cropped, H, W, h_valid, h_roi, target_x, target_y, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 1400 500]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1400 500]);
end

subplot(1,4,1);
imshow(Irgb);
title(sprintf('Original Image\n%d x %d', H, W), 'FontSize', 10);

subplot(1,4,2);
imshow(Irgb);
hold on;
rectangle('Position', [1, h_valid, W-1, h_roi], 'EdgeColor', 'r', 'LineWidth', 2);
line([1 W], [h_valid h_valid], 'Color', 'b', 'LineStyle', '--', 'LineWidth', 2);
hold off;
title(sprintf('ROI Excluded\nBottom %.0f%%', (h_roi/H)*100), 'FontSize', 10);

subplot(1,4,3);
imshow(I_cropped);
hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 30, 'LineWidth', 4);
hold off;
title(sprintf('Cropped + Target\n(%d, %d)', target_x, target_y), 'FontSize', 10);

subplot(1,4,4);
imshow(I_cropped);
hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 30, 'LineWidth', 4);
line([target_x-50 target_x+50], [target_y target_y], 'Color', 'r', 'LineWidth', 1);
line([target_x target_x], [target_y-50 target_y+50], 'Color', 'r', 'LineWidth', 1);
hold off;
title('Center Crosshairs', 'FontSize', 10);

sgtitle(sprintf('%s - STEP 0: Input Preparation', baseName), 'Interpreter', 'none', 'FontSize', 12);

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_step0_input.png']));
    close(fig);
end
end

function saveStep1Debug(I_cropped, BW_center_raw, allMasks, numMasks, target_x, target_y, confidence, Hc, Wc, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 1600 500]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1600 500]);
end

subplot(1,4,1);
imshow(I_cropped);
hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 25, 'LineWidth', 3);
hold off;
title('Input + Target', 'FontSize', 10);

subplot(1,4,2);
imshow(BW_center_raw);
title(sprintf('Center Mask (raw)\n%d pixels, conf=%.2f', sum(BW_center_raw(:)), confidence), 'FontSize', 10);

subplot(1,4,3);
imshow(labeloverlay(I_cropped, BW_center_raw, 'Colormap', [1 1 0], 'Transparency', 0.4));
title('Center Mask Overlay', 'FontSize', 10);

subplot(1,4,4);
% All masks overlay
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
title(sprintf('All %d SAM Masks', numMasks), 'FontSize', 10);

sgtitle(sprintf('%s - STEP 1: SAM Output', baseName), 'Interpreter', 'none', 'FontSize', 12);

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_step1_sam_output.png']));
    close(fig);
end
end

function saveStep2Debug(I_cropped, BW_raw, BW_cleaned, rp, allAreas, nRegions, keepIdx, removeIdx, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 1600 600]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1600 600]);
end

subplot(2,3,1);
[L, ~] = bwlabel(BW_raw);
imshow(label2rgb(L, 'jet', 'k', 'shuffle'));
hold on;
for k = 1:nRegions
    centroid = rp(k).Centroid;
    text(centroid(1), centroid(2), sprintf('%d', k), 'Color', 'w', 'FontSize', 10, 'FontWeight', 'bold');
end
hold off;
title(sprintf('All %d Components', nRegions), 'FontSize', 10);

subplot(2,3,2);
bar(allAreas);
xlabel('Region'); ylabel('Area (px)');
title('Region Areas', 'FontSize', 10);

subplot(2,3,3);
if nRegions > 2
    logAreas = log10(allAreas + 1);
    histogram(logAreas, 15);
    xlabel('log_{10}(Area)');
    title('Log-Area Distribution', 'FontSize', 10);
else
    text(0.5, 0.5, sprintf('Only %d regions\n(no Otsu needed)', nRegions), ...
        'HorizontalAlignment', 'center', 'FontSize', 12);
    axis off;
end

subplot(2,3,4);
imshow(I_cropped);
hold on;
for idx = removeIdx
    regionMask = false(size(BW_raw));
    regionMask(rp(idx).PixelIdxList) = true;
    visboundaries(regionMask, 'Color', 'r', 'LineWidth', 2);
end
hold off;
title(sprintf('REMOVED: %d regions', numel(removeIdx)), 'FontSize', 10, 'Color', 'r');

subplot(2,3,5);
imshow(I_cropped);
hold on;
for idx = keepIdx
    regionMask = false(size(BW_raw));
    regionMask(rp(idx).PixelIdxList) = true;
    visboundaries(regionMask, 'Color', 'g', 'LineWidth', 2);
end
hold off;
title(sprintf('KEPT: %d regions', numel(keepIdx)), 'FontSize', 10, 'Color', [0 0.6 0]);

subplot(2,3,6);
imshowpair(BW_raw, BW_cleaned, 'montage');
title('Before vs After Cleanup', 'FontSize', 10);

sgtitle(sprintf('%s - STEP 2: Adaptive Cluster Cleanup', baseName), 'Interpreter', 'none', 'FontSize', 12);

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_step2_cleanup.png']));
    close(fig);
end
end

function saveStep4TextureDebug(I_cropped, allMasksExclusive, textureFeatures, isTextured, isNonTextured, Hc, Wc, debugFolder, baseName, showFigures)

if showFigures
    fig = figure('Position', [100 100 1200 500]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1200 500]);
end

subplot(1,3,1);
bar(textureFeatures);
xlabel('Mask Index');
ylabel('Edge Density');
title('Edge Density per Mask', 'FontSize', 10);

subplot(1,3,2);
texturedOverlay = zeros(Hc, Wc, 3);
for m = find(isTextured)'
    thisMask = squeeze(allMasksExclusive(m, :, :));
    texturedOverlay(:,:,1) = texturedOverlay(:,:,1) | double(thisMask);
end
imshow(min(texturedOverlay, 1) * 0.7 + im2double(I_cropped) * 0.3);
title(sprintf('TEXTURED: %d masks (red)', sum(isTextured)), 'FontSize', 10);

subplot(1,3,3);
nonTexOverlay = zeros(Hc, Wc, 3);
for m = find(isNonTextured)'
    thisMask = squeeze(allMasksExclusive(m, :, :));
    nonTexOverlay(:,:,2) = nonTexOverlay(:,:,2) | double(thisMask);
end
imshow(min(nonTexOverlay, 1) * 0.7 + im2double(I_cropped) * 0.3);
title(sprintf('NON-TEXTURED: %d masks (green)', sum(isNonTextured)), 'FontSize', 10);

sgtitle(sprintf('%s - STEP 3: Texture Classification', baseName), 'Interpreter', 'none', 'FontSize', 12);

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_step3_texture.png']));
    close(fig);
end
end

function saveStep4RejectionDebug(I_cropped, BW_center, BW_textured, overlap_ratio, rejection_reason, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 1400 400]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1400 400]);
end

subplot(1,4,1);
imshow(I_cropped);
title('Original', 'FontSize', 10);

subplot(1,4,2);
imshow(labeloverlay(I_cropped, BW_center, 'Colormap', [1 1 0], 'Transparency', 0.4));
title('Center Mask (yellow)', 'FontSize', 10);

subplot(1,4,3);
imshow(labeloverlay(I_cropped, BW_textured, 'Colormap', [1 0 0], 'Transparency', 0.4));
title('Textured Region (red)', 'FontSize', 10);

subplot(1,4,4);
% Overlap visualization
overlap = BW_center & BW_textured;
rgb = zeros([size(BW_center) 3]);
rgb(:,:,1) = double(BW_textured) * 0.5;
rgb(:,:,2) = double(BW_center & ~BW_textured);
rgb(:,:,3) = double(overlap);  % Overlap in blue/magenta
imshow(rgb * 0.8 + im2double(I_cropped) * 0.2);
title(sprintf('Overlap: %.0f%%\nREJECTED', overlap_ratio*100), 'FontSize', 10, 'Color', 'r');

sgtitle(sprintf('%s - STEP 4: REJECTED (No Lumen Formed)\n%s', baseName, rejection_reason), ...
    'Interpreter', 'none', 'FontSize', 12, 'Color', 'r');

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_step4_REJECTED.png']));
    close(fig);
end
end

function saveStep6PolarityDebug(I_cropped, Igray_u8, BW_lumen, I_fill, I_inv, I_fill_from_inv, diff_gray, diff_inv, total_diff_gray, total_diff_inv, polarity, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 1800 700]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1800 700]);
end

% Row 1: Grayscale path
subplot(2,5,1);
imshow(Igray_u8);
title('Grayscale', 'FontSize', 10);

subplot(2,5,2);
imshow(I_fill);
title('imfill(gray)', 'FontSize', 10);

subplot(2,5,3);
imshow(diff_gray, []);
colorbar;
title('diff\_gray', 'FontSize', 10);

subplot(2,5,4);
imshow(diff_gray .* double(BW_lumen), []);
colorbar;
title(sprintf('Masked\nSum=%.0f', total_diff_gray), 'FontSize', 10);

% Row 2: Inverse path
subplot(2,5,6);
imshow(I_inv);
title('Inverse', 'FontSize', 10);

subplot(2,5,7);
imshow(I_fill_from_inv);
title('imfill(inv) back', 'FontSize', 10);

subplot(2,5,8);
imshow(diff_inv, []);
colorbar;
title('diff\_inv', 'FontSize', 10);

subplot(2,5,9);
imshow(diff_inv .* double(BW_lumen), []);
colorbar;
title(sprintf('Masked\nSum=%.0f', total_diff_inv), 'FontSize', 10);

% Decision panel
subplot(2,5,[5 10]);
if strcmp(polarity, 'bright')
    bgColor = [0.7 1 0.7];
    txtColor = [0 0.5 0];
else
    bgColor = [1 0.7 0.7];
    txtColor = [0.5 0 0];
end
rectangle('Position', [0 0 1 1], 'FaceColor', bgColor);
text(0.5, 0.7, upper(polarity), 'FontSize', 36, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'Color', txtColor);
text(0.5, 0.4, sprintf('diff\\_gray: %.0f\ndiff\\_inv: %.0f', total_diff_gray, total_diff_inv), ...
    'FontSize', 12, 'HorizontalAlignment', 'center');
text(0.5, 0.15, sprintf('Ratio: %.2f', total_diff_inv / max(total_diff_gray, 1)), ...
    'FontSize', 11, 'HorizontalAlignment', 'center');
axis off;
xlim([0 1]); ylim([0 1]);

sgtitle(sprintf('%s - STEP 5: Polarity Detection', baseName), 'Interpreter', 'none', 'FontSize', 12);

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_step5_polarity.png']));
    close(fig);
end
end

function saveFinalSummaryDebug(I_cropped, Irgb, BW_raw, BW_lumen, BW_3d_printed, allMasksExclusive, numMasks, quality, target_x, target_y, h_valid, H, W, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 1800 600]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 1800 600]);
end

subplot(2,4,1);
imshow(I_cropped);
hold on;
plot(target_x, target_y, 'r+', 'MarkerSize', 20, 'LineWidth', 2);
hold off;
title('1. Input + Target', 'FontSize', 10);

subplot(2,4,2);
imshow(BW_raw);
title('2. Raw Center Mask', 'FontSize', 10);

subplot(2,4,3);
% All masks
[Hc, Wc, ~] = size(I_cropped);
maskOverlay = zeros(Hc, Wc, 3);
colors = lines(numMasks);
for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m, :, :));
    for c = 1:3
        channel = maskOverlay(:,:,c);
        channel(thisMask) = colors(m, c);
        maskOverlay(:,:,c) = channel;
    end
end
imshow(maskOverlay * 0.6 + im2double(I_cropped) * 0.4);
title(sprintf('3. All %d Masks', numMasks), 'FontSize', 10);

subplot(2,4,4);
imshow(BW_3d_printed);
title(sprintf('4. Textured (3D-printed)\n%d masks', quality.num_textured_masks), 'FontSize', 10);

subplot(2,4,5);
imshow(BW_lumen);
title(sprintf('5. Final Lumen\n%d px', sum(BW_lumen(:))), 'FontSize', 10);

subplot(2,4,6);
% Overlay
if strcmp(quality.polarity, 'bright')
    overlayColor = [0 1 0];
elseif strcmp(quality.polarity, 'dark')
    overlayColor = [1 0.5 0];
else
    overlayColor = [1 1 0];
end
imshow(labeloverlay(I_cropped, BW_lumen, 'Colormap', overlayColor, 'Transparency', 0.4));
title(sprintf('6. Overlay\nPolarity: %s', upper(quality.polarity)), 'FontSize', 10);

subplot(2,4,7);
% Combined: structure + lumen
overlay = im2double(I_cropped);
% Structure in red
for c = 1:3
    ch = overlay(:,:,c);
    if c == 1
        ch(BW_3d_printed) = ch(BW_3d_printed) * 0.5 + 0.5;
    else
        ch(BW_3d_printed) = ch(BW_3d_printed) * 0.5;
    end
    overlay(:,:,c) = ch;
end
% Lumen in green
for c = 1:3
    ch = overlay(:,:,c);
    if c == 2
        ch(BW_lumen) = ch(BW_lumen) * 0.5 + 0.5;
    else
        ch(BW_lumen) = ch(BW_lumen) * 0.5;
    end
    overlay(:,:,c) = ch;
end
imshow(overlay);
title('7. Structure(R) + Lumen(G)', 'FontSize', 10);

subplot(2,4,8);
axis off;
% Quality summary
if quality.lumen_valid
    statusColor = [0 0.6 0];
else
    statusColor = [0.8 0 0];
end
text(0.1, 0.95, 'QUALITY SUMMARY:', 'FontSize', 11, 'FontWeight', 'bold');
text(0.1, 0.82, sprintf('Status: %s', quality.status), 'FontSize', 10, 'Color', statusColor);
text(0.1, 0.70, sprintf('Valid: %d', quality.lumen_valid), 'FontSize', 10);
text(0.1, 0.58, sprintf('Polarity: %s', upper(quality.polarity)), 'FontSize', 10);
text(0.1, 0.46, sprintf('Confidence: %.2f', quality.confidence), 'FontSize', 10);
text(0.1, 0.34, sprintf('Textured: %d', quality.is_textured), 'FontSize', 10);
text(0.1, 0.22, sprintf('Masks: %d total', quality.num_masks), 'FontSize', 10);
if ~isempty(quality.rejection_reason)
    text(0.1, 0.08, sprintf('Reason: %s', quality.rejection_reason), 'FontSize', 9, 'Color', 'r');
end

if quality.lumen_valid
    titleColor = [0 0.5 0];
    statusStr = sprintf('LUMEN FOUND - %s', upper(quality.polarity));
else
    titleColor = [0.8 0 0];
    statusStr = 'NO LUMEN';
end

sgtitle(sprintf('%s - FINAL: %s', baseName, statusStr), ...
    'Interpreter', 'none', 'FontSize', 14, 'FontWeight', 'bold', 'Color', titleColor);

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_FINAL.png']));
    close(fig);
end
end

function saveErrorDebug(ME, debugFolder, baseName, showFigures)
if showFigures
    fig = figure('Position', [100 100 600 300]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 600 300]);
end

text(0.5, 0.5, sprintf('ERROR:\n%s\n\n%s', ME.message, ME.identifier), ...
    'FontSize', 12, 'HorizontalAlignment', 'center', 'Color', 'r');
axis off;

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName '_ERROR.png']));
    close(fig);
end
end