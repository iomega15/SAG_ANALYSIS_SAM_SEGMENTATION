function T_majority = majorityWinsHeatmap(T, resultsFolder)
% MAJORITYWINSHEITMAP  Majority vote on LumenStatus across replicates.
%   T.LumenStatus must contain canonical labels: open, occluded, failed, no_data
%
%   T_majority = majorityWinsHeatmap(T, resultsFolder)

    if nargin < 2 || isempty(resultsFolder)
        resultsFolder = 'majority_heatmap_results';
    end
    if ~exist(resultsFolder, 'dir'), mkdir(resultsFolder); end

    requiredCols = {'Condition', 'H_layers', 'Width_px', 'Roof_layers', 'LumenStatus'};
    for c = 1:numel(requiredCols)
        if ~ismember(requiredCols{c}, T.Properties.VariableNames)
            error('majorityWinsHeatmap:missingColumn', ...
                'Table T is missing required column "%s".', requiredCols{c});
        end
    end

    [G, condG, hG, wG, rG] = findgroups( ...
        T.Condition, T.H_layers, T.Width_px, T.Roof_layers);

    nGroups = numel(condG);
    fprintf('majorityWinsHeatmap: %d unique groups from %d rows\n', nGroups, height(T));

    votedStatus   = cell(nGroups, 1);
    nRepsPerGroup = zeros(nGroups, 1);

    for g = 1:nGroups
        mask = (G == g);
        statuses = T.LumenStatus(mask);
        nRepsPerGroup(g) = numel(statuses);

        votes = lower(strtrim(string(statuses)));
        votes(ismissing(votes) | votes == "") = "no_data";

        votedStatus{g} = char(majorityVote_MV(votes));
    end

    % Report
    fprintf('\nMajority vote results:\n');
    fprintf('  Groups: %d\n', nGroups);
    fprintf('  Replicates per group: min=%d, max=%d, median=%.0f\n', ...
        min(nRepsPerGroup), max(nRepsPerGroup), median(nRepsPerGroup));
    uStatus = unique(votedStatus);
    for s = 1:numel(uStatus)
        n = sum(strcmp(votedStatus, uStatus{s}));
        fprintf('  %s: %d\n', uStatus{s}, n);
    end

    T_majority = table(condG, hG, wG, rG, votedStatus, ...
        'VariableNames', {'Condition','H_layers','Width_px','Roof_layers','LumenStatus'});

    % Save
    writetable(T_majority, fullfile(resultsFolder, 'majority_vote_table.csv'));
    fprintf('\nSaved: %s\n', fullfile(resultsFolder, 'majority_vote_table.csv'));

    % Grid CSV per condition
    conditions = unique(T_majority.Condition, 'stable');
    for c = 1:numel(conditions)
        cond = conditions{c};
        Tc = T_majority(strcmp(T_majority.Condition, cond), :);
        widths = unique(Tc.Width_px, 'sorted');
        roofs  = unique(Tc.Roof_layers, 'sorted');

        grid = cell(numel(widths)+1, numel(roofs)+1);
        grid{1,1} = 'Width \ Roof';
        for j = 1:numel(roofs), grid{1,j+1} = roofs(j); end
        for i = 1:numel(widths)
            grid{i+1,1} = widths(i);
            for j = 1:numel(roofs)
                idx = (Tc.Width_px == widths(i)) & (Tc.Roof_layers == roofs(j));
                if any(idx)
                    grid{i+1,j+1} = Tc.LumenStatus{find(idx,1)};
                else
                    grid{i+1,j+1} = 'N/A';
                end
            end
        end
        gridFile = fullfile(resultsFolder, ...
            sprintf('majority_vote_grid_%s.csv', matlab.lang.makeValidName(cond)));
        writecell(grid, gridFile);
        fprintf('Saved grid: %s\n', gridFile);
    end

    plotOcclusionHeatmap(T_majority, resultsFolder);
end

% =========================================================================
function out = majorityVote_MV(votes)
    votes = lower(strtrim(votes));
    votes(ismissing(votes) | votes == "") = "no_data";

    cats   = unique(votes, 'stable');
    counts = zeros(size(cats));
    for i = 1:numel(cats)
        counts(i) = sum(votes == cats(i));
    end

    maxCount = max(counts);
    winners  = cats(counts == maxCount);

    if numel(winners) == 1
        out = winners; return;
    end

    % Tie-break: canonical labels
    priority = ["open", "occluded", "partial", "failed", "no_data"];
    for p = 1:numel(priority)
        if any(winners == priority(p))
            out = priority(p); return;
        end
    end
    out = winners(1);
end