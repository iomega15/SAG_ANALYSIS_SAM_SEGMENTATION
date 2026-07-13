function [lumen_candidates, candidate_imfill_polarity, candidate_imfill_scores, selected_mask_idx, selected_polarity] = ...
    selectCentralLumenCandidate(allMasksExclusive, lumen_candidates, candidate_imfill_polarity, candidate_imfill_scores, Hc, Wc, target_x, target_y)
%SELECTCENTRALLUMENCANDIDATE  Pick the candidate at (or nearest) the target point.
%
% Selection order:
%   1. Candidates whose mask CONTAINS the target point beat all others
%      (the target marks where the lumen must be; an off-center neighbor
%      should never win over a mask sitting on the target).
%   2. Within that tier, higher imfill score wins (a stronger enclosed-basin
%      response is a better lumen candidate than a marginal one).
%   3. If no mask contains the target, fall back to smallest
%      centroid-to-target distance, imfill score as tie-break.
%
% Backward compatible: if target_x/target_y are omitted, the image center is
% used (the old behavior).

if nargin < 7 || isempty(target_x), target_x = Wc / 2; end
if nargin < 8 || isempty(target_y), target_y = Hc / 2; end

selected_mask_idx = [];
selected_polarity = 'unknown';

if isempty(lumen_candidates)
    return;
end

tx = round(target_x);
ty = round(target_y);
tx = min(max(tx, 1), Wc);
ty = min(max(ty, 1), Hc);

n         = numel(lumen_candidates);
contains  = false(n, 1);
dist      = inf(n, 1);
scores    = zeros(n, 1);

for i = 1:n
    m        = lumen_candidates(i);
    thisMask = squeeze(allMasksExclusive(m, :, :));

    contains(i) = thisMask(ty, tx);

    rp_cand = regionprops(thisMask, 'Centroid');
    if ~isempty(rp_cand)
        dist(i) = sqrt((rp_cand(1).Centroid(1) - tx)^2 + ...
                       (rp_cand(1).Centroid(2) - ty)^2);
    end

    if ~isempty(candidate_imfill_scores) && numel(candidate_imfill_scores) >= i
        s = candidate_imfill_scores(i);
        if iscell(s), s = s{1}; end
        if ~isempty(s) && isnumeric(s) && isfinite(s)
            scores(i) = s;
        end
    end
end

if any(contains)
    tier = find(contains);
    [~, k] = max(scores(tier));   % containing tier: best imfill score wins
    best_i = tier(k);
else
    minDist = min(dist);
    if ~isfinite(minDist)
        return;
    end
    % near-tie band: anything within 10% of the closest distance competes,
    % then imfill score decides (avoids a coin-flip between two masks that
    % straddle the target almost symmetrically)
    tier = find(dist <= minDist * 1.10 + 1);
    [~, k] = max(scores(tier));
    best_i = tier(k);
end

selected_mask_idx = lumen_candidates(best_i);
selected_polarity = candidate_imfill_polarity{best_i};
% Reduce candidate list to just the winner
lumen_candidates          = lumen_candidates(best_i);
candidate_imfill_polarity = candidate_imfill_polarity(best_i);
candidate_imfill_scores   = candidate_imfill_scores(best_i);
end
