function [lumen_candidates, candidate_polarity, candidate_scores, selected_mask_idx, selected_polarity] = ...
    selectCentralLumenCandidate(allMasksExclusive, lumen_candidates, candidate_polarity, candidate_scores, Hc, Wc)

selected_mask_idx = [];
selected_polarity = 'unknown';

if isempty(lumen_candidates)
    return;
end

cx       = Wc / 2;
cy       = Hc / 2;
min_dist = inf;
best_i   = [];

for i = 1:numel(lumen_candidates)
    m        = lumen_candidates(i);
    thisMask = squeeze(allMasksExclusive(m, :, :));
    rp_cand  = regionprops(thisMask, 'Centroid');
    if ~isempty(rp_cand)
        dist = sqrt((rp_cand(1).Centroid(1) - cx)^2 + ...
            (rp_cand(1).Centroid(2) - cy)^2);
        if dist < min_dist
            min_dist  = dist;
            best_i    = i;
        end
    end
end

if ~isempty(best_i)
    selected_mask_idx = lumen_candidates(best_i);
    selected_polarity = candidate_polarity{best_i};
    % Reduce candidate list to just the winner
    lumen_candidates   = lumen_candidates(best_i);
    candidate_polarity = candidate_polarity(best_i);
    candidate_scores   = candidate_scores(best_i);
end
end