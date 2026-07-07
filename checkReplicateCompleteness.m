function checkReplicateCompleteness(T)
% CHECKREPLICATECOMPLETENESS  Report missing groups, low-n, and data anomalies.
%   Operates on the raw pipeline table T before any plotting.

    fprintf('\n=== REPLICATE COMPLETENESS CHECK ===\n');

    % ----------------------------------------------------------------
    % 1. Expected full grid from the data's own range
    % ----------------------------------------------------------------
    allWidths = sort(unique(T.Width_px));
    allRoofs  = sort(unique(T.Roof_layers));
    allConds  = unique(T.Condition);
    allH      = sort(unique(T.H_layers));

    fprintf('Parameter space detected:\n');
    fprintf('  Conditions:   %s\n', strjoin(allConds, ', '));
    fprintf('  H_layers:     %s\n', mat2str(allH'));
    fprintf('  Width_px:     %s\n', mat2str(allWidths'));
    fprintf('  Roof_layers:  %s\n', mat2str(allRoofs'));
    fprintf('  Expected grid size per Condition x H: %d x %d = %d combinations\n', ...
        numel(allWidths), numel(allRoofs), numel(allWidths)*numel(allRoofs));

    % ----------------------------------------------------------------
    % 2. Group by full key and count replicates
    % ----------------------------------------------------------------
    [G, condG, hG, wG, rG] = findgroups(T.Condition, T.H_layers, T.Width_px, T.Roof_layers);
    nPerGroup = splitapply(@numel, T.Replicate, G);
    maxN = max(nPerGroup);

    fprintf('\nTotal groups found:            %d\n', numel(nPerGroup));
    fprintf('Max replicates per group:      %d\n', maxN);

    % ----------------------------------------------------------------
    % 3. Low-n groups
    % ----------------------------------------------------------------
    lowMask = nPerGroup < maxN;
    if any(lowMask)
        fprintf('\n*** %d groups have fewer than %d replicates:\n', sum(lowMask), maxN);
        idx = find(lowMask);
        for k = 1:numel(idx)
            fprintf('    Cond=%-15s  H=%d  W=%3d  Roof=%2d  n=%d\n', ...
                condG{idx(k)}, hG(idx(k)), wG(idx(k)), rG(idx(k)), nPerGroup(idx(k)));
        end
    else
        fprintf('Replicate counts: all groups have n=%d. OK.\n', maxN);
    end

    % ----------------------------------------------------------------
    % 4. Missing combinations (present in full grid but absent in data)
    % ----------------------------------------------------------------
    fprintf('\n--- Missing grid combinations ---\n');
    nMissing = 0;
    for ci = 1:numel(allConds)
        for hi = 1:numel(allH)
            for wi = 1:numel(allWidths)
                for ri = 1:numel(allRoofs)
                    hasIt = any( ...
                        strcmp(condG, allConds{ci}) & ...
                        hG == allH(hi) & ...
                        wG == allWidths(wi) & ...
                        rG == allRoofs(ri));
                    if ~hasIt
                        fprintf('    MISSING: Cond=%-15s  H=%d  W=%3d  Roof=%2d\n', ...
                            allConds{ci}, allH(hi), allWidths(wi), allRoofs(ri));
                        nMissing = nMissing + 1;
                    end
                end
            end
        end
    end
    if nMissing == 0
        fprintf('    None — grid is complete.\n');
    else
        fprintf('    Total missing combinations: %d\n', nMissing);
    end

    % ----------------------------------------------------------------
    % 5. Anomalous parameter values
    %    Any Width or Roof that appears in fewer (Cond x H) slices
    %    than expected.
    % ----------------------------------------------------------------
    fprintf('\n--- Anomalous parameter values ---\n');

    expectedSlices = numel(allConds) * numel(allH);

    % Width coverage
    fprintf('  Width coverage (should appear in %d Cond x H slices):\n', expectedSlices);
    for wi = 1:numel(allWidths)
        w = allWidths(wi);
        mask = (wG == w);
        pairs = [string(condG(mask)), string(hG(mask))];
        nSlices = size(unique(pairs, 'rows'), 1);
        if nSlices < expectedSlices
            fprintf('    *** W=%3d appears in only %d / %d Cond x H slices\n', ...
                w, nSlices, expectedSlices);
        end
    end

    % Roof coverage
    fprintf('  Roof coverage (should appear in %d Cond x H slices):\n', expectedSlices);
    for ri = 1:numel(allRoofs)
        r = allRoofs(ri);
        mask = (rG == r);
        pairs = [string(condG(mask)), string(hG(mask))];
        nSlices = size(unique(pairs, 'rows'), 1);
        if nSlices < expectedSlices
            fprintf('    *** Roof=%2d appears in only %d / %d Cond x H slices\n', ...
                r, nSlices, expectedSlices);
        end
    end

    % ----------------------------------------------------------------
    % 6. Duplicate rows (same full key AND same replicate index)
    % ----------------------------------------------------------------
    fprintf('\n--- Duplicate rows (same Cond/H/W/Roof/Replicate) ---\n');
    GD = findgroups(T.Condition, T.H_layers, T.Width_px, T.Roof_layers, T.Replicate);
    nPerDup = accumarray(GD, 1);
    dupMask = nPerDup > 1;
    if any(dupMask)
        fprintf('    *** %d exact duplicates found (same key + replicate index)\n', sum(dupMask));
    else
        fprintf('    None found. OK.\n');
    end

    fprintf('=============================================\n\n');
end