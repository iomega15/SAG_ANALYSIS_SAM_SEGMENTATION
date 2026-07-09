function surrounding_masks = findSurroundingMasks(allMasksExclusive, numMasks, Hc, Wc)

    % Build label matrix
    labelMatrix = zeros(Hc, Wc);
    for m = 1:numMasks
        thisMask = squeeze(allMasksExclusive(m,:,:));
        labelMatrix(thisMask) = m;
    end

    mask1 = squeeze(allMasksExclusive(1,:,:));
    hit_set = false(1, numMasks);

    % --- Rays UP from top perimeter ---
    % For each column, find topmost mask-1 pixel, then walk upward
    for col = 1:Wc
        row = find(mask1(:, col), 1, 'first');
        if isempty(row), continue; end
        for r = row-1 : -1 : 1
            lbl = labelMatrix(r, col);
            if lbl > 0 && lbl ~= 1
                hit_set(lbl) = true;
                break;
            end
        end
    end

    % --- Rays DOWN from bottom perimeter ---
    for col = 1:Wc
        row = find(mask1(:, col), 1, 'last');
        if isempty(row), continue; end
        for r = row+1 : Hc
            lbl = labelMatrix(r, col);
            if lbl > 0 && lbl ~= 1
                hit_set(lbl) = true;
                break;
            end
        end
    end

    % --- Rays LEFT from left perimeter ---
    for row = 1:Hc
        col = find(mask1(row, :), 1, 'first');
        if isempty(col), continue; end
        for c = col-1 : -1 : 1
            lbl = labelMatrix(row, c);
            if lbl > 0 && lbl ~= 1
                hit_set(lbl) = true;
                break;
            end
        end
    end

    % --- Rays RIGHT from right perimeter ---
    for row = 1:Hc
        col = find(mask1(row, :), 1, 'last');
        if isempty(col), continue; end
        for c = col+1 : Wc
            lbl = labelMatrix(row, c);
            if lbl > 0 && lbl ~= 1
                hit_set(lbl) = true;
                break;
            end
        end
    end

    surrounding_masks = find(hit_set);
    surrounding_masks = setdiff(surrounding_masks, 1);
end