function [lumen_candidates, candidate_imfill_polarity, candidate_scores, imfill_cache, ...
          anchor_score, I_fill, I_fill_from_inv, diff_gray_full, diff_inv_full] = ...
    detectImfillCandidates(Igray_cropped_u8, allMasksExclusive, maskAreas, ...
                           candidate_pool, anchor_mask, target_x, target_y)

% target_x/target_y (optional): the expected lumen location. A candidate whose
% mask CONTAINS the target is never eliminated by the imfill-vs-anchor test
% below — bright lumens embedded in bright surroundings produce a weak fill
% response and used to lose to the anchor baseline here (root cause of the
% reproducible W14-W16 bright-lumen misses, e.g. H5_W14_ML10_R2). Retained
% target candidates still face the texture and size gates downstream.
if nargin < 6, target_x = []; end
if nargin < 7, target_y = []; end
haveTarget = ~isempty(target_x) && ~isempty(target_y);
if haveTarget
    [Hc_, Wc_] = size(Igray_cropped_u8);
    tx = min(max(round(target_x), 1), Wc_);
    ty = min(max(round(target_y), 1), Hc_);
end

% Grayscale imfill: fills dark enclosed regions from image borders inward
I_fill          = imfill(Igray_cropped_u8);

% Invert so dark voids become bright, then fill, then re-invert
I_inv           = imcomplement(Igray_cropped_u8);
I_inv_fill      = imfill(I_inv);
I_fill_from_inv = imcomplement(I_inv_fill);

% Pixels that changed reveal dark enclosed voids (bright lumen polarity)
diff_gray_full = abs(double(I_fill) - double(Igray_cropped_u8));

% Pixels that changed reveal bright enclosed voids (dark lumen polarity)
diff_inv_full  = abs(double(Igray_cropped_u8) - double(I_fill_from_inv));

% Anchor scores per polarity
anchor_area       = sum(anchor_mask(:));
anchor_score_gray = sum(diff_gray_full(anchor_mask)) / anchor_area;
anchor_score_inv  = sum(diff_inv_full(anchor_mask))  / anchor_area;

% anchor_score output = max of both (for debug display only)
anchor_score = max(anchor_score_gray, anchor_score_inv);

% imfill_cache stores per-candidate scores only
imfill_cache = struct();

lumen_candidates   = [];
candidate_imfill_polarity = {};
candidate_scores   = [];

for i = 1:numel(candidate_pool)
    m = candidate_pool(i);

    thisMask = squeeze(allMasksExclusive(m, :, :));
    if maskAreas(m) < 100
        continue;
    end

    % Mean imfill response per pixel for each polarity
    score_gray = sum(diff_gray_full(thisMask)) / maskAreas(m);
    score_inv  = sum(diff_inv_full(thisMask))  / maskAreas(m);

    % Polarity: whichever direction responds more strongly
    if score_inv > score_gray
        polarity                   = 'bright';
        winning_score              = score_inv;
        anchor_score_same_polarity = anchor_score_inv;
    else
        polarity                   = 'dark';
        winning_score              = score_gray;
        anchor_score_same_polarity = anchor_score_gray;
    end

    % Cache per-candidate scores for debug visualization
    imfill_cache(m).score_gray = score_gray;
    imfill_cache(m).score_inv  = score_inv;
    imfill_cache(m).score      = winning_score;
    imfill_cache(m).polarity   = polarity;

    % Keep candidates with stronger imfill response than anchor, OR any
    % candidate sitting on the target point (see header note).
    contains_target = haveTarget && thisMask(ty, tx);
    if winning_score > anchor_score_same_polarity || contains_target
        lumen_candidates(end+1)   = m;             %#ok<AGROW>
        candidate_imfill_polarity{end+1} = polarity;      %#ok<AGROW>
        candidate_scores(end+1)   = winning_score; %#ok<AGROW>
    end
end
end