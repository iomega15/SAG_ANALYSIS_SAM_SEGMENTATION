function [BWlumen, quality] = segmentLumenSAM2(I, roi, debugFolder, baseName, rawCacheDir, expectedLumenArea_px)
% SEGMENTLUMENSAM: Center-based SAM + Texture Clustering Validation
%
% rawCacheDir (optional): folder for caching the RAW SAM output (all masks,
%   pre-selection) as <baseName>_samraw.mat. Caching the raw output rather
%   than the final selected lumen means the candidate-selection / validation
%   logic below can be re-tuned and re-run cheaply without re-running SAM
%   inference. Delete the cache only if the input images or roi change.
% expectedLumenArea_px (optional): expected lumen cross-section in image
%   pixels (from nominal W x H and the OCR scale). Used as a physical
%   plausibility gate on the selected candidate; pass NaN/[] to skip.

%% ====================================================================
SHOW_DEBUG_FIGURES = false;

%% ====================================================================
% INITIALIZE
% =====================================================================
quality = struct();
quality.status           = 'unknown';
quality.lumen_valid      = false;
quality.confidence       = 0;
quality.polarity         = 'unknown';
quality.score_gray       = 0;
quality.score_inv        = 0;
quality.imfill_score     = 0;
quality.is_textured      = false;
quality.num_masks        = 0;
quality.rejection_reason = '';
quality.lumen_area_px    = 0;
quality.anchor_area_px   = 0;
quality.texture_ratio    = NaN;
quality.texture_contrast = NaN;
quality.lumen_density    = 0;
quality.anchor_density   = 0;

if nargin < 3, debugFolder = ''; end
if nargin < 4, baseName = 'image'; end
if nargin < 5, rawCacheDir = ''; end
if nargin < 6 || isempty(expectedLumenArea_px), expectedLumenArea_px = NaN; end

quality.expected_lumen_area_px = expectedLumenArea_px;
quality.area_vs_expected       = NaN;

saveDebug = ~isempty(debugFolder) && exist(debugFolder, 'dir');

% The 7-panel per-image summary (`*_FINAL.png`, saveFinalSummaryDebug) goes to
% the top level of the debug folder for quick failure-flagging; every granular
% per-step figure below is routed into a `detailed_steps` subfolder so it stays
% out of the way during that quick review. `debugParent` keeps the top level.
debugParent = debugFolder;
if saveDebug
    debugFolder = fullfile(debugFolder, 'detailed_steps');   % step figs land here
    if ~exist(debugFolder, 'dir'); mkdir(debugFolder); end
end

%% ====================================================================
% STEP 0: INPUT PREPARATION
% =====================================================================
if ismatrix(I)
    Irgb = repmat(I, [1 1 3]);
else
    Irgb = I;
end
[H, W, ~] = size(Irgb);
Igray     = rgb2gray(Irgb);
Igray_u8  = im2uint8(Igray);
Igray_dbl = im2double(Igray);

h_roi    = round(H * roi.bottomFrac);
h_valid  = H - h_roi;
target_x = round(W / 2);
target_y = round(h_valid / 2);

I_cropped         = Irgb(1:h_valid, :, :);
Igray_cropped_u8  = Igray_u8(1:h_valid, :);
Igray_cropped_dbl = Igray_dbl(1:h_valid, :);
[Hc, Wc]          = size(Igray_cropped_u8);

BWlumen          = false(H, W);
BW_lumen_cropped = false(Hc, Wc);

if saveDebug || SHOW_DEBUG_FIGURES
    saveStep0Debug(Irgb, I_cropped, H, W, h_valid, h_roi, target_x, target_y, ...
        debugFolder, baseName, SHOW_DEBUG_FIGURES);
end

%% ====================================================================
% STEP 1: SETUP SAM
% =====================================================================
tempFile = fullfile(tempdir, 'temp_sam_input.png');
imwrite(I_cropped, tempFile);

thisFileDir = fileparts(mfilename('fullpath'));

candidatePaths = { ...
    fullfile(thisFileDir, 'sam_vit_b_01ec64.pth'), ...
    fullfile(fileparts(thisFileDir), 'sam_vit_b_01ec64.pth'), ...
    fullfile(pwd, 'sam_vit_b_01ec64.pth'), ...
    fullfile(fileparts(pwd), 'sam_vit_b_01ec64.pth')};

checkpointFile = '';

for k = 1:numel(candidatePaths)
    if exist(candidatePaths{k}, 'file')
        checkpointFile = candidatePaths{k};
        break;
    end
end

if isempty(checkpointFile)
    quality.status           = 'checkpoint_not_found';
    quality.rejection_reason = 'SAM checkpoint not found';
    warning('SAM checkpoint not found');
    if exist(tempFile, 'file'), delete(tempFile); end
    return;
end

try
    %% ================================================================
    % STEP 2: RUN SAM
    % ================================================================
    target_y_cropped = target_y;

    % --- Raw-SAM cache: skip inference if this image's raw masks are cached ---
    gotRaw = false;
    rawCacheFile = '';
    if ~isempty(rawCacheDir)
        if ~exist(rawCacheDir, 'dir'); mkdir(rawCacheDir); end
        rawCacheFile = fullfile(rawCacheDir, [baseName '_samraw.mat']);
        if exist(rawCacheFile, 'file')
            try
                Sr = load(rawCacheFile, 'BW_center_raw', 'confidence', 'allMasks', 'numMasks');
                BW_center_raw = Sr.BW_center_raw;
                quality.confidence = Sr.confidence;
                allMasks  = Sr.allMasks;
                numMasks  = Sr.numMasks;
                gotRaw = true;
                fprintf('  [raw SAM output cached]\n');
            catch
                gotRaw = false;
            end
        end
    end

    if ~gotRaw
        fprintf('Running SAM...\n');
        tic;
        [lumen_mask_out, confidence_score, all_masks_out, num_masks] = pyrunfile( ...
            "sam_segment_all.py", ...
            ["lumen_mask_out", "confidence_score", "all_masks_out", "num_masks"], ...
            image_path=tempFile, ...
            checkpoint_path=checkpointFile, ...
            target_x=int32(target_x), ...
            target_y=int32(target_y_cropped));

        fprintf('SAM completed in %.1f seconds\n', toc);

        BW_center_raw      = logical(lumen_mask_out);
        quality.confidence = double(confidence_score);
        allMasks           = logical(all_masks_out);
        numMasks           = double(num_masks);

        if ~isempty(rawCacheFile)
            try
                confidence = quality.confidence;
                save(rawCacheFile, 'BW_center_raw', 'confidence', 'allMasks', 'numMasks', '-v7.3');
            catch
            end
        end
    end
    quality.num_masks = numMasks;

    if saveDebug || SHOW_DEBUG_FIGURES
        saveStep1Debug(I_cropped, BW_center_raw, allMasks, numMasks, ...
            target_x, target_y_cropped, quality.confidence, ...
            Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
    end

    %% ================================================================
    % STEP 2.5: PREPARE EXCLUSIVE MASKS
    % ================================================================
    if numMasks > 0
        allMasksExclusive = prepareExclusiveMasks(allMasks, numMasks, Hc, Wc);
    else
        allMasksExclusive = allMasks;
    end

    if saveDebug || SHOW_DEBUG_FIGURES
        saveStep2_5Debug(I_cropped, allMasks, allMasksExclusive, numMasks, ...
            Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
    end

    %% ================================================================
    % STEP 3: ADAPTIVE CLUSTER CLEANUP: Cleanup Center Mask:
    %  Removes small disconnected specks from the SAM center mask using log-area clustering,
    % keeping only the meaningful region(s).
    % ================================================================
    % BW_center_exclusive = squeeze(allMasksExclusive(1, :, :));
    %
    % [BW_center_cleaned, keepIdx, removeIdx, rp, allAreas, nRegions] = ...
    %     cleanCenterMask(BW_center_exclusive);
    %
    % % Overwrite mask 1 in allMasksExclusive with the cleaned version
    % allMasksExclusive(1, :, :) = BW_center_cleaned;

    % --- Clean all exclusive masks to remove stray pixels ---
    for m = 1:numMasks
        thisMask = squeeze(allMasksExclusive(m, :, :));
        [thisMask_cleaned, ~, ~, ~, ~, ~] = cleanCenterMask(thisMask);
        allMasksExclusive(m, :, :) = thisMask_cleaned;
    end

    % BW_center_exclusive = squeeze(allMasksExclusive(1, :, :));
    %
    % if saveDebug || SHOW_DEBUG_FIGURES
    %     saveStep2Debug(I_cropped, BW_center_exclusive, BW_center_cleaned, rp, ...
    %         allAreas, nRegions, keepIdx, removeIdx, ...
    %         debugFolder, baseName, SHOW_DEBUG_FIGURES);
    % end

    %% ================================================================
    % STEP 4: TEXTURE ANALYSIS + LUMEN CANDIDATE SELECTION
    % ================================================================
    if numMasks > 0

        %calculate mask areas so that we woudln't have to recompute them
        %over and over
        maskAreas = computeMaskAreas(allMasksExclusive, numMasks);

        % --- 4.1: Compute texture features for all masks ---
        textureFeatures = computeAllMaskTextures(Igray_cropped_dbl, allMasksExclusive, numMasks, maskAreas);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_1Debug(I_cropped, allMasksExclusive, textureFeatures, maskAreas, ...
                numMasks, Hc, Wc, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end

        lumen_candidates = 1:numMasks;  %each successive filter will remove masks from it that are not lumen

        % --- 4.2: Identify background light mask: largest x brightest (runs first, no anchor needed)
        [bg_mask_idx, bg_mask, lumen_candidates] = identifyBackgroundMask(allMasksExclusive, maskAreas, ...
            Igray_cropped_dbl, lumen_candidates, textureFeatures);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_2Debug(I_cropped, allMasksExclusive, bg_mask_idx, ...
                textureFeatures, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end

        % --- 4.3: Identify anchor mask ---
        [anchor_mask, anchor_texture, material_top_Y, material_bot_Y, lumen_candidates, ...
            top_band_labels, candidateIndices, portion_masks, portion_areas, portion_textures, ...
            lumen_bot_row, top_band] = ...
            identifyAnchorMask(allMasksExclusive, lumen_candidates, Hc, Wc, bg_mask, Igray_cropped_dbl);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_3Debug(I_cropped, allMasksExclusive, anchor_mask, ...
                material_top_Y, material_bot_Y, top_band_labels, candidateIndices , ...
                portion_masks, portion_areas, portion_textures, ...
                textureFeatures, lumen_bot_row, top_band, ...
                debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end

        % --- 4.4: Eliminate border-touching masks before imfill testing ---
        [lumen_candidates, removed_border] = ...
            eliminateBorderCandidates(allMasksExclusive, lumen_candidates);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_4Debug(I_cropped, allMasksExclusive, lumen_candidates, ...
                removed_border, debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end

        % --- 4.5: Eliminate candidates outside  3D-printed anchor vertical bounds ---
        [lumen_candidates, removed_outside_anchor] = ...
            eliminateOutsideMaterialBounds(allMasksExclusive, lumen_candidates, material_top_Y, material_bot_Y);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_5Debug(I_cropped, allMasksExclusive, lumen_candidates, ...
                removed_outside_anchor, material_top_Y, material_bot_Y, ...
                debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end

        % --- 4.6: imfill candidate detection ---
        [lumen_candidates, candidate_imfill_polarity, candidate_imfill_scores, imfill_cache, ...
            anchor_score, ~, ~, diff_gray_full, diff_inv_full] = ...
            detectImfillCandidates(Igray_cropped_u8, allMasksExclusive, maskAreas, ...
            lumen_candidates, anchor_mask);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_6Debug(I_cropped, allMasksExclusive, lumen_candidates, ...
                candidate_imfill_polarity, candidate_imfill_scores, imfill_cache, ...
                anchor_score, diff_gray_full, diff_inv_full, ...
                debugFolder, baseName, SHOW_DEBUG_FIGURES);
        end

        % --- 4.7: Select best candidate: at/nearest the TARGET point ---
        % (was: closest centroid to image center — that picked off-center
        % neighbors over the actual target lumen, e.g. H5_W12_ML3_R1)
        [lumen_candidates, ~, ~, selected_mask_idx, selected_polarity] = ...
            selectCentralLumenCandidate(allMasksExclusive, lumen_candidates, ...
            candidate_imfill_polarity, candidate_imfill_scores, Hc, Wc, ...
            target_x, target_y_cropped);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_7Debug(I_cropped, allMasksExclusive, lumen_candidates, ...
                selected_mask_idx, selected_polarity, debugFolder, baseName, ...
                SHOW_DEBUG_FIGURES);
        end

        % --- 4.7b: Physical plausibility: selected mask vs expected lumen size ---
        % The nominal channel cross-section (W x H at the OCR-measured scale)
        % bounds how big a real lumen can plausibly be. A candidate far below
        % the expected area is a speck/defect, not the lumen (mode-1 false
        % positives at narrow W were 2-4k px acceptances). Gate is skipped
        % when no expected area was provided (NaN).
        MIN_AREA_FRAC = 0.15;
        if ~isempty(selected_mask_idx) && isfinite(expectedLumenArea_px) && expectedLumenArea_px > 0
            selArea = maskAreas(selected_mask_idx);
            quality.area_vs_expected = selArea / expectedLumenArea_px;
            if selArea < MIN_AREA_FRAC * expectedLumenArea_px
                quality.rejection_reason = sprintf( ...
                    'Selected mask (%d px) < %.0f%% of expected lumen area (%.0f px) — speck, not lumen', ...
                    selArea, MIN_AREA_FRAC*100, expectedLumenArea_px);
                selected_mask_idx = [];
                selected_polarity = 'unknown';
            end
        end

        % --- 4.8: Texture validation against anchor ---
        [lumen_valid, quality, RATIO_THRESHOLD] = validateLumenTexture( ...
            anchor_texture, selected_mask_idx, textureFeatures, quality);

        if saveDebug || SHOW_DEBUG_FIGURES
            saveStep4_8Debug(I_cropped, allMasksExclusive, ...
                selected_mask_idx, anchor_mask, ...
                quality.texture_contrast, quality.lumen_density, ...
                quality.anchor_density, lumen_valid, ...
                debugFolder, baseName, RATIO_THRESHOLD, SHOW_DEBUG_FIGURES);
        end

        %% ============================================================
        % STEP 5: FINALIZE RESULT
        %% ============================================================
        if lumen_valid
            selected_lumen_mask    = squeeze(allMasksExclusive(selected_mask_idx, :, :));
            BW_lumen_cropped       = selected_lumen_mask;
            quality.status         = 'good';
            quality.lumen_valid    = true;
            quality.polarity       = selected_polarity;
            quality.score_gray     = imfill_cache(selected_mask_idx).score_gray;
            quality.score_inv      = imfill_cache(selected_mask_idx).score_inv;
            quality.imfill_score   = imfill_cache(selected_mask_idx).score;
            quality.lumen_area_px  = sum(BW_lumen_cropped(:));
            quality.anchor_area_px = sum(anchor_mask(:));  % joined anchor area
        else
            BW_lumen_cropped       = false(Hc, Wc);
            quality.status         = 'no_lumen_formed';
            quality.lumen_valid    = false;
        end

        %% ============================================================
        % STEP 6: FINAL SUMMARY DEBUG
        %% ============================================================
        if saveDebug || SHOW_DEBUG_FIGURES
            saveFinalSummaryDebug(I_cropped, BW_center_raw, BW_lumen_cropped, ...
                anchor_mask, allMasksExclusive, numMasks, quality, ...
                target_x, target_y_cropped, ...
                debugParent, baseName, SHOW_DEBUG_FIGURES);   % *_FINAL.png -> top level
        end
    else
        quality.status           = 'no_masks_generated';
        quality.lumen_valid      = false;
        quality.rejection_reason = 'SAM generated no masks';
        BW_lumen_cropped         = false(Hc, Wc);
    end

catch ME
    warning(['SAM Error: ' ME.message]);
    quality.status           = 'SAM_error';
    quality.lumen_valid      = false;
    quality.rejection_reason = ME.message;
    BW_lumen_cropped         = false(Hc, Wc);
    if saveDebug || SHOW_DEBUG_FIGURES
        saveErrorDebug(ME, debugFolder, baseName, SHOW_DEBUG_FIGURES);
    end
end

if exist(tempFile, 'file'), delete(tempFile); end

BWlumen                = false(H, W);
BWlumen(1:h_valid, :) = BW_lumen_cropped;

end