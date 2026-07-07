function T = spatialSmoothClassification(T)
% For each (Width, Roof) cell with n=3 replicates:
%   If 2/3 agree → override the outlier
% For isolated disagreements with spatial neighbors:
%   If all 4 neighbors agree on a label → override

    conditions = unique(T.Condition);
    heights = unique(T.H_layers(~isnan(T.H_layers)));

    corrections = 0;

    for h = 1:numel(heights)
        for c = 1:numel(conditions)
            mask = (T.H_layers == heights(h)) & strcmp(T.Condition, conditions{c});
            subIdx = find(mask);
            if isempty(subIdx), continue; end

            % --- Replicate voting: majority wins ---
            widths = T.Width_px(subIdx);
            roofs  = T.Roof_layers(subIdx);
            combos = unique([widths, roofs], 'rows');

            for k = 1:size(combos, 1)
                cellMask = (widths == combos(k,1)) & (roofs == combos(k,2));
                cellIdx = subIdx(cellMask);

                if numel(cellIdx) < 2, continue; end

                labels = T.ClassifiedStatus(cellIdx);
                [uniqueLabels, ~, ic] = unique(labels);
                counts = accumarray(ic, 1);
                [maxCount, maxIdx] = max(counts);

                if maxCount > numel(cellIdx)/2
                    majorityLabel = uniqueLabels{maxIdx};
                    for m = 1:numel(cellIdx)
                        if ~strcmp(T.ClassifiedStatus{cellIdx(m)}, majorityLabel)
                            T.ClassifiedStatus{cellIdx(m)} = majorityLabel;
                            corrections = corrections + 1;
                        end
                    end
                end
            end
        end
    end

    fprintf('Spatial smoothing: %d corrections made\n', corrections);
end