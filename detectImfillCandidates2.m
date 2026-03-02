function [lumen_candidates, candidate_polarity, candidate_scores, imfill_cache, ...
          lumen_ref_score, I_fill, I_fill_from_inv, diff_gray_full, diff_inv_full] = ...
    detectImfillCandidates2(Igray_cropped_u8, allMasksExclusive, maskAreas, ...
                           candidate_pool)
%DETECTIMFILLCANDIDATES  Identify enclosed voids using grayscale imfill.
%
% Uses mask 1 (known lumen) as the reference. Any candidate with imfill
% response >= 50% of mask 1's response is considered a lumen.

% --- Grayscale imfill: fills dark enclosed regions from borders inward ---
I_fill          = imfill(Igray_cropped_u8);

% --- Invert, fill, re-invert: reveals bright enclosed voids ---
I_inv           = imcomplement(Igray_cropped_u8);
I_inv_fill      = imfill(I_inv);
I_fill_from_inv = imcomplement(I_inv_fill);

% --- Difference maps ---
diff_gray_full = abs(double(I_fill)          - double(Igray_cropped_u8));
diff_inv_full  = abs(double(Igray_cropped_u8) - double(I_fill_from_inv));

% --- Mask 1 (known lumen) as reference ---
mask1           = squeeze(allMasksExclusive(1, :, :));
mask1_area      = sum(mask1(:));
ref_score_gray  = sum(diff_gray_full(mask1)) / mask1_area;
ref_score_inv   = sum(diff_inv_full(mask1))  / mask1_area;
lumen_ref_score = max(ref_score_gray, ref_score_inv);

LUMEN_IMFILL_FRAC = 0.50;  % candidate must have >= 50% of mask-1's score

% --- Score each candidate ---
imfill_cache = struct();

lumen_candidates   = [];
candidate_polarity = {};
candidate_scores   = [];

for i = 1:numel(candidate_pool)
    m = candidate_pool(i);

    if m == 1, continue; end  % skip known lumen

    thisMask = squeeze(allMasksExclusive(m, :, :));
    if maskAreas(m) < 100
        continue;
    end

    score_gray = sum(diff_gray_full(thisMask)) / maskAreas(m);
    score_inv  = sum(diff_inv_full(thisMask))  / maskAreas(m);

    if score_inv > score_gray
        polarity      = 'bright';
        winning_score = score_inv;
    else
        polarity      = 'dark';
        winning_score = score_gray;
    end

    % Cache for debug
    imfill_cache(m).score_gray = score_gray;
    imfill_cache(m).score_inv  = score_inv;
    imfill_cache(m).score      = winning_score;
    imfill_cache(m).polarity   = polarity;

    % Keep if imfill response is at least 50% of the known lumen
    if winning_score >= lumen_ref_score * LUMEN_IMFILL_FRAC
        lumen_candidates(end+1)   = m;             
        candidate_polarity{end+1} = polarity;      
        candidate_scores(end+1)   = winning_score; 
    end
end
end