function T = classifyLumenFormation(T)
%CLASSIFYLUMENFORMATION  Cluster lumens into bright/dark/not_formed.

% --- Compute derived features ---
T.PolarityScore = (T.SAM_ScoreInv - T.SAM_ScoreGray) ./ ...
                  (T.SAM_ScoreInv + T.SAM_ScoreGray + 1e-6);
T.AreaRatio     = T.SAM_LumenAreaPx ./ (T.SAM_AnchorAreaPx + 1);

% --- Identify rows with complete data ---
has_data = T.SAM_LumenValid & ...
           ~isnan(T.SAM_TextureRatio) & ...
           ~isnan(T.SAM_ImfillScore) & ...
           ~isnan(T.PolarityScore) & ...
           ~isnan(T.AreaRatio);

n_valid = sum(has_data);
fprintf('Classifying %d lumens into bright/dark/not_formed\n', n_valid);

% --- Initialize output ---
if ~ismember('LumenClass', T.Properties.VariableNames)
    T.LumenClass = repmat({'no_data'}, height(T), 1);
end
if ~ismember('ClusterID', T.Properties.VariableNames)
    T.ClusterID = nan(height(T), 1);
end

if n_valid < 6
    warning('Too few valid lumens (%d) for clustering — skipping', n_valid);
    return;
end

% --- Build feature matrix ---
X = [ T.SAM_TextureRatio(has_data), ...
      T.SAM_ImfillScore(has_data), ...
      T.PolarityScore(has_data), ...
      T.AreaRatio(has_data) ];

% --- Normalize to [0, 1] ---
X_min   = min(X, [], 1);
X_max   = max(X, [], 1);
X_range = X_max - X_min;
X_range(X_range == 0) = 1;
X_norm  = (X - X_min) ./ X_range;

% --- Cluster ---
rng(42);
[idx, C] = kmedoids(X_norm, 3, 'Replicates', 10);

% --- Recover centroids in original scale ---
C_orig = C .* X_range + X_min;

% --- Label clusters ---
[~, not_formed_cluster] = max(C_orig(:, 1));  % highest texture ratio
formed_clusters         = setdiff(1:3, not_formed_cluster);
polarity_of_formed      = C_orig(formed_clusters, 3);
[~, bright_local]       = max(polarity_of_formed);
[~, dark_local]         = min(polarity_of_formed);
bright_cluster          = formed_clusters(bright_local);
dark_cluster            = formed_clusters(dark_local);

label_map = containers.Map('KeyType', 'int32', 'ValueType', 'char');
label_map(int32(not_formed_cluster)) = 'not_formed';
label_map(int32(bright_cluster))     = 'bright';
label_map(int32(dark_cluster))       = 'dark';

% --- Assign ---
valid_idx = find(has_data);
for j = 1:n_valid
    T.ClusterID(valid_idx(j))  = idx(j);
    T.LumenClass{valid_idx(j)} = label_map(int32(idx(j)));
end

% --- Print summary ---
fprintf('\nCluster centroids (original scale):\n');
fprintf('  %-12s  TexRatio  ImfillScore  Polarity  AreaRatio\n', 'Class');
for k = [bright_cluster, dark_cluster, not_formed_cluster]
    fprintf('  %-12s  %8.3f  %11.3f  %8.3f  %9.3f\n', ...
        label_map(int32(k)), C_orig(k,1), C_orig(k,2), C_orig(k,3), C_orig(k,4));
end

cats   = categories(categorical(T.LumenClass));
counts = countcats(categorical(T.LumenClass));
fprintf('\nClassification counts:\n');
for j = 1:numel(cats)
    fprintf('  %-12s: %d\n', cats{j}, counts(j));
end
end