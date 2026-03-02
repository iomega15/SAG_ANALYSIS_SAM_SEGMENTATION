function testPeriodicityDetection(I_cropped, allMasksExclusive)
%TESTPERIODICITYDETECTION  Visualize periodicity detection for each mask.
%
% For each mask:
%   - Extracts vertical intensity profiles through the interior
%   - Computes autocorrelation
%   - Looks for periodic peaks (layer lines)
%   - Displays results

numMasks = size(allMasksExclusive, 1);
[Hc, Wc, ~] = size(I_cropped);

if size(I_cropped, 3) == 3
    Igray = rgb2gray(I_cropped);
else
    Igray = I_cropped;
end
Igray = double(Igray);

TRIM_FRAC    = 0.25;   % trim edges to stay in interior
NUM_PROFILES = 20;     % number of vertical profiles per mask
MIN_LAG      = 5;      % minimum lag to search (pixels) — below this is noise
MAX_LAG      = 80;     % maximum lag to search — above this is too coarse

% --- Figure setup ---
fig = figure('Position', [50 50 1800 900]);
nRows = ceil(numMasks / 3);

for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m, :, :));
    
    if sum(thisMask(:)) < 500
        continue;
    end
    
    % --- Find interior columns (trim horizontally) ---
    colHasPixels = find(any(thisMask, 1));
    if numel(colHasPixels) < 10, continue; end
    
    colSpan   = colHasPixels(end) - colHasPixels(1);
    colTrim   = round(colSpan * TRIM_FRAC);
    colStart  = colHasPixels(1) + colTrim;
    colEnd    = colHasPixels(end) - colTrim;
    
    if colEnd <= colStart, continue; end
    
    sampleCols = round(linspace(colStart, colEnd, NUM_PROFILES));
    
    % --- Extract vertical profiles and compute autocorrelation ---
    all_acorr     = [];
    valid_profiles = 0;
    profile_lengths = [];
    
    for ci = 1:numel(sampleCols)
        col = sampleCols(ci);
        
        % Find vertical extent in this column, trim top/bottom
        rowPixels = find(thisMask(:, col));
        if numel(rowPixels) < 20, continue; end
        
        rowSpan  = rowPixels(end) - rowPixels(1);
        rowTrim  = round(rowSpan * TRIM_FRAC);
        rStart   = rowPixels(1) + rowTrim;
        rEnd     = rowPixels(end) - rowTrim;
        
        if rEnd - rStart < 20, continue; end
        
        % Extract profile and detrend
        profile = Igray(rStart:rEnd, col);
        profile = profile - mean(profile);
        profile = profile ./ (std(profile) + 1e-6);
        
        % Normalized autocorrelation
        n = numel(profile);
        acorr = xcorr(profile, 'coeff');
        acorr = acorr(n:end);  % keep positive lags only
        
        % Pad or truncate to consistent length
        maxLen = min(numel(acorr), MAX_LAG + 1);
        acorr_trimmed = acorr(1:maxLen);
        
        if valid_profiles == 0
            all_acorr = zeros(0, maxLen);
        end
        
        if numel(acorr_trimmed) == size(all_acorr, 2)
            all_acorr(end+1, :) = acorr_trimmed; %#ok<AGROW>
            valid_profiles = valid_profiles + 1;
        end
        
        profile_lengths(end+1) = n; %#ok<AGROW>
    end
    
    if valid_profiles < 3
        continue;
    end
    
    % --- Average autocorrelation across all profiles ---
    mean_acorr = mean(all_acorr, 1);
    lags       = 0:(numel(mean_acorr)-1);
    
    % --- Find peaks in the valid lag range ---
    search_start = MIN_LAG + 1;  % +1 for 1-based indexing
    search_end   = min(MAX_LAG + 1, numel(mean_acorr));
    
    if search_end <= search_start, continue; end
    
    search_acorr = mean_acorr(search_start:search_end);
    search_lags  = lags(search_start:search_end);
    
    [pks, locs, widths, prominences] = findpeaks(search_acorr, search_lags, ...
        'MinPeakProminence', 0.05, 'MinPeakDistance', 3);
    
    % --- Periodicity score: strength of the strongest peak ---
    if ~isempty(pks)
        [best_peak, best_idx] = max(prominences);
        best_lag              = locs(best_idx);
        periodicity_score     = best_peak;
        
        % Check for harmonics (second peak at ~2x the lag)
        has_harmonic = false;
        for pi = 1:numel(locs)
            if abs(locs(pi) - 2*best_lag) < 3 && pi ~= best_idx
                has_harmonic = true;
                break;
            end
        end
    else
        best_peak         = 0;
        best_lag          = 0;
        periodicity_score = 0;
        has_harmonic      = false;
    end
    
    is_periodic = periodicity_score > 0.1;
    
    % --- Plot ---
    subplot(nRows, 3, m);
    
    % Left half: autocorrelation
    yyaxis left;
    plot(lags, mean_acorr, 'b-', 'LineWidth', 1.5); hold on;
    if ~isempty(pks)
        plot(locs, pks, 'rv', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    end
    ylabel('Autocorrelation');
    xlim([0 MAX_LAG]);
    ylim([-0.3 1]);
    
    % Mark the detection region
    xline(MIN_LAG, '--', 'Color', [0.5 0.5 0.5]);
    
    yyaxis right;
    % Show one example profile
    if valid_profiles > 0
        example_profile = all_acorr(1, :);
        plot(lags, example_profile, 'Color', [0.8 0.6 0.2 0.4], 'LineWidth', 0.5);
    end
    ylabel('Single Profile');
    
    hold off;
    xlabel('Lag (pixels)');
    
    if is_periodic
        status = sprintf('PERIODIC (lag=%d, score=%.2f)', best_lag, periodicity_score);
        if has_harmonic
            status = [status ' +harmonic']; %#ok<AGROW>
        end
        titleColor = [0 0.6 0];
    else
        status = sprintf('NOT periodic (score=%.2f)', periodicity_score);
        titleColor = [0.8 0 0];
    end
    
    title(sprintf('Mask %d: %s\n(%d profiles, median len=%d)', ...
        m, status, valid_profiles, round(median(profile_lengths))), ...
        'FontSize', 9, 'Color', titleColor);
end

% --- Summary overlay ---
figure('Position', [100 100 1200 600]);

overlay = zeros(Hc, Wc, 3);
colors_map = lines(numMasks);

for m = 1:numMasks
    thisMask = squeeze(allMasksExclusive(m, :, :));
    
    % Recompute periodicity quickly for coloring
    is_periodic_m = false;  % default
    
    colHasPixels = find(any(thisMask, 1));
    if numel(colHasPixels) >= 10 && sum(thisMask(:)) >= 500
        colSpan  = colHasPixels(end) - colHasPixels(1);
        colTrim  = round(colSpan * TRIM_FRAC);
        colStart = colHasPixels(1) + colTrim;
        colEnd   = colHasPixels(end) - colTrim;
        
        if colEnd > colStart
            sampleCols = round(linspace(colStart, colEnd, NUM_PROFILES));
            temp_acorr = [];
            count = 0;
            
            for ci = 1:numel(sampleCols)
                col = sampleCols(ci);
                rowPixels = find(thisMask(:, col));
                if numel(rowPixels) < 20, continue; end
                rowSpan = rowPixels(end) - rowPixels(1);
                rowTrim = round(rowSpan * TRIM_FRAC);
                rStart  = rowPixels(1) + rowTrim;
                rEnd    = rowPixels(end) - rowTrim;
                if rEnd - rStart < 20, continue; end
                
                profile = Igray(rStart:rEnd, col);
                profile = profile - mean(profile);
                profile = profile ./ (std(profile) + 1e-6);
                n = numel(profile);
                acorr = xcorr(profile, 'coeff');
                acorr = acorr(n:end);
                maxLen = min(numel(acorr), MAX_LAG + 1);
                
                if count == 0
                    temp_acorr = zeros(0, maxLen);
                end
                if numel(acorr(1:maxLen)) == size(temp_acorr, 2)
                    temp_acorr(end+1, :) = acorr(1:maxLen); %#ok<AGROW>
                    count = count + 1;
                end
            end
            
            if count >= 3
                ma = mean(temp_acorr, 1);
                ss = MIN_LAG + 1;
                se = min(MAX_LAG + 1, numel(ma));
                if se > ss
                    [~, ~, ~, proms] = findpeaks(ma(ss:se), (ss-1):(se-1), ...
                        'MinPeakProminence', 0.05, 'MinPeakDistance', 3);
                    if ~isempty(proms) && max(proms) > 0.1
                        is_periodic_m = true;
                    end
                end
            end
        end
    end
    
    % Color: green = periodic (structure), red = not periodic
    if is_periodic_m
        mask_color = [0.2 0.8 0.2];  % green
    else
        mask_color = [0.8 0.2 0.2];  % red
    end
    
    for c = 1:3
        ch = overlay(:,:,c);
        ch(thisMask) = mask_color(c);
        overlay(:,:,c) = ch;
    end
end

imshow(overlay * 0.6 + im2double(I_cropped) * 0.4);
title('Green = Periodic (3D-printed structure)  |  Red = Not periodic (lumen/substrate)', ...
    'FontSize', 12);

end