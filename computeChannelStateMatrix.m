function [codeMatrix, widths, roofLayers, countMatrix] = computeChannelStateMatrix(subT)
%COMPUTECHANNELSTATEMATRIX  Banded channel-state grid for one (Condition,H).
%
%   [codeMatrix, widths, roofLayers, countMatrix] = computeChannelStateMatrix(subT)
%
% Returns the FINAL channel-state code per (roof, width) cell:
%   1 = Not-Formed, 2 = Occluded, 3 = Open, 4 = Membrane Touchdown.
% Per-image status comes from SAM (buildStatusFromSAM); membrane touchdown
% is inferred at map level by the island-ban + monotone 4-stage (F->X->O->T)
% banding. This is the SAME logic the qualitative heatmap draws, factored out
% so the sag figures classify touchdown identically (a touchdown cell = the
% roof sagged 100% to the floor, so the sag figure can plot it as 100%).

    statusCol  = buildStatusFromSAM(subT);
    isFailed   = strcmp(statusCol, 'failed');
    isOccluded = strcmp(statusCol, 'occluded') | strcmp(statusCol, 'partial');
    isOpen     = strcmp(statusCol, 'open');

    code = ones(height(subT), 1);   % default -> not-formed (1)
    code(isOccluded) = 2;
    code(isOpen)     = 3;

    widths     = sort(unique(subT.Width_px));
    roofLayers = sort(unique(subT.Roof_layers));
    nWidths    = numel(widths);
    nRoofs     = numel(roofLayers);

    codeMatrix  = nan(nRoofs, nWidths);
    countMatrix = zeros(nRoofs, nWidths);
    for i = 1:height(subT)
        wIdx = find(widths == subT.Width_px(i), 1);
        rIdx = find(roofLayers == subT.Roof_layers(i), 1);
        if ~isempty(wIdx) && ~isempty(rIdx)
            codeMatrix(rIdx, wIdx)  = code(i);
            countMatrix(rIdx, wIdx) = countMatrix(rIdx, wIdx) + 1;
        end
    end

    %% --- Island ban ---
    % A connected same-code region fully surrounded by other codes is
    % classification noise -> recolor to the neighboring majority. Components
    % touching the grid border are kept (e.g. the real corner touchdown block).
    for pass = 1:4
        changedAny = false;
        for cval = unique(codeMatrix(~isnan(codeMatrix)))'
            CC = bwconncomp(codeMatrix == cval, 4);
            for k = 1:CC.NumObjects
                [rr, cc] = ind2sub([nRoofs nWidths], CC.PixelIdxList{k});
                if any(rr == 1 | rr == nRoofs | cc == 1 | cc == nWidths)
                    continue;
                end
                comp = false(nRoofs, nWidths);
                comp(CC.PixelIdxList{k}) = true;
                ring = imdilate(comp, ones(3)) & ~comp;
                ringCodes = codeMatrix(ring);
                ringCodes = ringCodes(~isnan(ringCodes));
                if isempty(ringCodes), continue; end
                maj = mode(ringCodes);
                if maj ~= cval
                    codeMatrix(CC.PixelIdxList{k}) = maj;
                    changedAny = true;
                end
            end
        end
        if ~changedAny, break; end
    end

    %% --- Monotone 4-stage banding: F -> X -> O -> T ---
    % Across increasing width a roof row passes monotonically through up to
    % four ordered stages: Not-Formed -> Occluded -> Open -> Touchdown. Both
    % the narrow Not-Formed band and the wide Touchdown band read as failed
    % (code 1) per-image; they are distinguished ONLY by position. Fit each
    % row to the maximum-agreement partition F* X* O* T* (any band may be
    % empty). Display codes: F=1, X=2, O=3, T=4.
    for ri = 1:nRoofs
        rowCodes = codeMatrix(ri, :);
        fitIdx = find(~isnan(rowCodes) & ismember(rowCodes, [1 2 3 4]));
        if numel(fitIdx) < 2, continue; end
        obs = rowCodes(fitIdx);
        obs(obs == 4) = 1;    % any pre-existing T reads as a failed observation
        n   = numel(obs);
        bestCost = inf;
        bestFit  = obs;
        for b1 = 0:n
            for b2 = b1:n
                for b3 = b2:n
                    fit = [ones(1,b1), 2*ones(1,b2-b1), ...
                           3*ones(1,b3-b2), 4*ones(1,n-b3)];
                    expObs = fit; expObs(expObs == 4) = 1;
                    cost = sum(expObs ~= obs);
                    if cost < bestCost
                        bestCost = cost;
                        bestFit  = fit;
                    end
                end
            end
        end
        codeMatrix(ri, fitIdx) = bestFit;
    end
end
