clc
clear all
close all

% =========================================================================
% TWO-PASS MAIN SCRIPT:
%   PASS 0: build table from filenames only (fast)
%   PASS 1: fill OCR + measurements + sag analysis into existing table (slow)
% =========================================================================

%% USER INPUTS
pixelWidth_mm = 0.032;    % XY pixel resolution of the printer
layerHeight_mm = 0.05;    % Z layer height specified to the printer
rootDir    = pwd;
recurse    = false;
exts       = {'.png','.jpg','.jpeg','.tif','.tiff','.bmp'};

roi.bottomFrac = 0.09;
roi.leftFrac   = 0.00;
roi.widthFrac  = 1.00;
roi.heightFrac = 0.09;

thrWhite = 0.85;
minAreaPx      = 80;
minAspectRatio = 8;
minWidthPx     = 50;

debugPlots     = false;       % For scale bar visualization
saveSagDebug   = true;        % Save sag analysis debug images

%% CREATE DEBUG FOLDER
debugFolder = fullfile(rootDir, 'debug_sag_analysis');
if saveSagDebug
    make_clean_folder(debugFolder);
    fprintf('Debug folder created: %s\n', debugFolder);
end

%% CREATE RESULTS FOLDER
resultsFolder = fullfile(rootDir, 'results');
make_clean_folder(resultsFolder);
fprintf('Clean results folder created: %s\n', resultsFolder);

%% FIND IMAGES
% Additional directories to include
%additionalDirs = {
 %   'C:\Users\...' 
%};
allDirs = [{rootDir}]; %; additionalDirs(:)];

% Get files with per-folder reporting
files = {};
fprintf('\n=== Searching for images ===\n');
for d = 1:numel(allDirs)
    thisDir = allDirs{d};
    theseFiles = listImages(thisDir, exts, recurse);
    fprintf('  [%d] %s: %d images\n', d, thisDir, numel(theseFiles));
    files = [files; theseFiles(:)];
end
files = unique(files, 'stable');

if isempty(files)
    error('No images found in specified directories.');
end
fprintf('=== Total: %d unique image(s) ===\n\n', numel(files));

%% PASS 0: BUILD TABLE FROM FILENAMES ONLY (FAST)
N = numel(files);
Folder       = cell(N,1);
File         = cell(N,1);

% --- NEW COLUMN FOR DATASET TYPE ---
Condition    = cell(N,1); 

Lens_Name    = nan(N,1);
TiltDeg_Name = nan(N,1);
H_layers     = nan(N,1);
Width_px     = nan(N,1);
Roof_layers  = nan(N,1);
Replicate    = nan(N,1);

% Placeholders for slow fields (filled in Pass 1)
Lens_OCR         = nan(N,1);
TiltDeg_OCR      = nan(N,1);
ScaleValue_OCR   = nan(N,1);
ScaleUnits_OCR   = cell(N,1);
BarPx            = nan(N,1);
mmPerPx          = nan(N,1);

% Lumen-derived metrics
LumenArea_px     = nan(N,1);
LumenWidth_px    = nan(N,1);
LumenHeight_px   = nan(N,1);

% ===== SAG ANALYSIS METRICS =====
SagDepth_px                 = nan(N,1);
SagDepth_mm                 = nan(N,1);
SagPct_ofMeasuredHeight     = nan(N,1);
SagPct_ofTheoreticalHeight  = nan(N,1);
SagPct_ofWidthSpan          = nan(N,1);
ParabolaR2                  = nan(N,1);

% ===== SAG ANALYSIS METRICS =====
SagArea_px2             = nan(N,1); % 
SagArea_mm2             = nan(N,1); % 

% ===== SAG VALIDATION FLAGS =====
IsVertexBetween         = false(N,1);
IsVertexLowerLeft       = false(N,1);
IsVertexLowerRight      = false(N,1);

MeasuredHeight_px           = nan(N,1);
MeasuredHeight_mm           = nan(N,1);
TheoreticalHeight_px        = nan(N,1);
TheoreticalHeight_mm        = nan(N,1);
HeightPct_ofTheoretical     = nan(N,1);

MeasuredWidth_px            = nan(N,1);
MeasuredWidth_mm            = nan(N,1);
TheoreticalWidth_px         = nan(N,1);
TheoreticalWidth_mm         = nan(N,1);
WidthPct_ofTheoretical      = nan(N,1);

LeftWallTiltAngle_deg       = nan(N,1);
RightWallTiltAngle_deg      = nan(N,1);
AvgWallTiltAngle_deg        = nan(N,1);
TotalWallInward_mm          = nan(N,1);

ActualArea_mm2              = nan(N,1);
TheoreticalArea_mm2         = nan(N,1);
AreaPct_ofTheoretical       = nan(N,1);
ConvexityRatio              = nan(N,1);

% ===== LUMEN QUALITY METRICS =====
LumenBrightness         = nan(N,1);
LumenBrightnessStd      = nan(N,1);
LumenStatus             = cell(N,1);
Solidity                = nan(N,1);
DebrisArea_px           = nan(N,1);
DebrisArea_mm2          = nan(N,1);
DebrisPct_ofLumen       = nan(N,1);

% BoundingBox-based sag metrics
SagDepthBB_px               = nan(N,1);
SagDepthBB_mm               = nan(N,1);
SagAreaBB_px2               = nan(N,1);
SagAreaBB_mm2               = nan(N,1);
SagBB_Pct_ofMeasuredHeight  = nan(N,1);
SagBB_Pct_ofTheoreticalHeight = nan(N,1);
SagBB_Pct_ofWidthSpan       = nan(N,1);
BaselineDiff_px             = nan(N,1);
BaselineDiff_mm             = nan(N,1);

RotationAngle_deg = nan(N,1);

Notes        = cell(N,1);

for i = 1:N
    fpath = files{i};
    [fld, base, ext] = fileparts(fpath);
    Folder{i} = fld;
    File{i}   = [base ext];
    
    % Lens/Tilt from filename if present (often NaN)
    metaName = parseFromFilename(base);
    Lens_Name(i)    = metaName.lens;
    TiltDeg_Name(i) = metaName.tiltDeg;
    
    % Experimental metadata (ConstH, Condition, Width, layer, replicate)
    metaExp = parseImageFilename(base);
    
    % Debug print
    % fprintf('File: %s -> Cond: %s, Rep: %d\n', base, metaExp.Condition, metaExp.Replicate);
    
    H_layers(i)     = metaExp.H_layers;
    Condition{i}    = metaExp.Condition;  % <--- NEW
    Width_px(i)     = metaExp.Width_px;
    Roof_layers(i)  = metaExp.Roof_layers;
    Replicate(i)    = metaExp.Replicate;
    
    Notes{i} = 'PENDING';
end

T = table( ...
    File, Folder, Condition, ...
    H_layers, Width_px, Roof_layers, Replicate, ...
    Lens_Name, TiltDeg_Name, ...
    Lens_OCR, TiltDeg_OCR, ...
    ScaleValue_OCR, ScaleUnits_OCR, ...
    BarPx, mmPerPx, ...
    RotationAngle_deg, ...
    LumenArea_px, LumenWidth_px, LumenHeight_px, ...
    ... % Corner-based sag (original)
    SagDepth_px, SagDepth_mm, ...
    SagArea_px2, SagArea_mm2, ...
    SagPct_ofMeasuredHeight, SagPct_ofTheoreticalHeight, SagPct_ofWidthSpan, ...
    ... % BoundingBox-based sag (new)
    SagDepthBB_px, SagDepthBB_mm, ...
    SagAreaBB_px2, SagAreaBB_mm2, ...
    SagBB_Pct_ofMeasuredHeight, SagBB_Pct_ofTheoreticalHeight, SagBB_Pct_ofWidthSpan, ...
    ... % Baseline comparison
    BaselineDiff_px, BaselineDiff_mm, ...
    ... % Parabola & validation
    ParabolaR2, ...
    IsVertexBetween, IsVertexLowerLeft, IsVertexLowerRight, ...
    ... % Height
    MeasuredHeight_px, MeasuredHeight_mm, TheoreticalHeight_px, TheoreticalHeight_mm, HeightPct_ofTheoretical, ...
    ... % Width
    MeasuredWidth_px, MeasuredWidth_mm, TheoreticalWidth_px, TheoreticalWidth_mm, WidthPct_ofTheoretical, ...
    ... % Wall tilt
    LeftWallTiltAngle_deg, RightWallTiltAngle_deg, AvgWallTiltAngle_deg, TotalWallInward_mm, ...
    ... % Area
    ActualArea_mm2, TheoreticalArea_mm2, AreaPct_ofTheoretical, ConvexityRatio, ...
    ... % Lumen quality
    LumenBrightness, LumenBrightnessStd, LumenStatus, Solidity, ...
    DebrisArea_px, DebrisArea_mm2, DebrisPct_ofLumen, ...
    Notes);

% Consolidated columns 
Lens = Lens_Name;
TiltDeg = TiltDeg_Name;
T = addvars(T, Lens, 'After','File');
T = addvars(T, TiltDeg, 'After','Lens');

disp('=== TABLE AFTER PASS 0 (FILENAMES ONLY) ===');
disp(T(1:min(10,height(T)), {'File', 'Condition', 'Width_px', 'Roof_layers', 'Replicate'}))

% Save the quick table immediately
outCsv0 = fullfile(rootDir, 'image_results_PASS0_filenames_only.csv');
writetable(T, outCsv0);
fprintf('Saved (pass0): %s\n', outCsv0);

%% FILTER DUPLICATES: Keep only newest date for non-replicate overlaps
% IMPORTANT: We must now group by 'Condition' as well. 
% DefaultALL and PreOptimized are DIFFERENT conditions, even if width/roof are same.

fprintf('\n=== Filtering duplicate conditions (keeping newest date) ===\n');

% Extract date from filename (expects format: 2026_02_06_...)
dateNums = NaT(height(T), 1);  % NaT = Not a Time
for i = 1:height(T)
    tok = regexp(T.File{i}, '^(\d{4}_\d{2}_\d{2})_', 'tokens', 'once');
    if ~isempty(tok)
        dateNums(i) = datetime(tok{1}, 'InputFormat', 'yyyy_MM_dd');
    end
end
T.ExpDate = dateNums;

% Identify rows to remove
removeIdx = false(height(T), 1);

% Only check non-replicates (Replicate == 0) for duplicates
nonRepIdx = find(T.Replicate == 0);

if ~isempty(nonRepIdx)
    % Group by experimental condition AND Dataset Type (Condition)
    % We convert cell Condition to categorical for findgroups
    [G, ~] = findgroups(T.H_layers(nonRepIdx), categorical(T.Condition(nonRepIdx)), ...
                        T.Width_px(nonRepIdx), T.Roof_layers(nonRepIdx));
    
    uniqueGroups = unique(G);
    
    for g = 1:numel(uniqueGroups)
        groupMask = (G == uniqueGroups(g));
        groupIdx = nonRepIdx(groupMask);  % indices into T
        
        if numel(groupIdx) > 1
            % Multiple entries for same condition - keep only newest
            [~, newestLocal] = max(T.ExpDate(groupIdx));
            
            % Mark all but newest for removal
            for k = 1:numel(groupIdx)
                if k ~= newestLocal
                    removeIdx(groupIdx(k)) = true;
                    fprintf('  REMOVING (superseded): %s\n', T.File{groupIdx(k)});
                end
            end
        end
    end
end

% Remove superseded rows
nRemoved = sum(removeIdx);
T(removeIdx, :) = [];
fprintf('=== Removed %d superseded experiments, %d remaining ===\n\n', nRemoved, height(T));

%% PASS 1: FILL OCR + MEASUREMENTS + SAG ANALYSIS (SLOW)
tic
for i = 1:height(T) 
    try
        fpath = fullfile(T.Folder{i}, T.File{i});
        I = imread(fpath);
        fprintf('[%d/%d] %s\n', i, height(T), T.File{i});
        
        % OCR (full image)
        ocrOut = extractLensAndScaleTextOCR(I, roi, false);
        
        % Parse OCR text
        [T.Lens_OCR(i), T.TiltDeg_OCR(i)] = parseLensTiltFromOCR(ocrOut.rawText);
        [T.ScaleValue_OCR(i), T.ScaleUnits_OCR{i}] = parseScaleFromOCRText(ocrOut.rawText);
        
        % Scale bar pixels
        T.BarPx(i) = measureScaleBarPixels(I, roi, thrWhite, minAreaPx, minAspectRatio, minWidthPx, debugPlots);
        
        % mm/px
        if ~isnan(T.ScaleValue_OCR(i)) && T.BarPx(i) > 0
            T.mmPerPx(i) = T.ScaleValue_OCR(i) / T.BarPx(i);
        end
      
        % Get base name
        [~, baseName, ~] = fileparts(T.File{i});
        
        % Define backup folder path
        backupDir = fullfile(T.Folder{i}, 'backup');
        if ~exist(backupDir, 'dir')
            mkdir(backupDir);
        end
        
        % Define path for SAM backup file
        backupFile = fullfile(backupDir, [baseName '_sam_data.mat']);
        
        % FORCE RE-RUN OPTION
        forceSAM = false; 
        
        if exist(backupFile, 'file') && ~forceSAM
            loadedData = load(backupFile, 'BWlumen', 'samQuality');
            BWlumen = loadedData.BWlumen;
            samQuality = loadedData.samQuality;
        else
            % Run SAM on ORIGINAL image (no rotation yet)
            [BWlumen, samQuality] = segmentLumenSAM(I, roi, debugFolder, baseName);
            
            try
                save(backupFile, 'BWlumen', 'samQuality');
            catch
                warning('Could not save SAM backup file to %s', backupFile);
            end
        end


        % ================================================================
        % ROTATION STEP: Apply AFTER SAM, BEFORE measureMembraneSag
        % ================================================================
        [I_rotated, BWlumen_rotated, rotationAngle] = autoRotateImage(I, BWlumen, roi, saveSagDebug, debugFolder, baseName);
        
        if abs(rotationAngle) > 0.05
            fprintf('  Auto-rotated by %.2f degrees\n', rotationAngle);
        end
        
        % Store rotation angle in table
        T.RotationAngle_deg(i) = rotationAngle;
        % ================================================================
        % END ROTATION STEP
        % ================================================================
      
        % Update LumenStatus from SAM
        if isfield(samQuality, 'polarity')
            T.LumenStatus{i} = samQuality.polarity;
        else
            T.LumenStatus{i} = 'unknown';
        end
        
        % Debug Figure: SAM result (show rotated version)
        if saveSagDebug
            figSAM = figure('Visible', 'off', 'Position', [100 100 1400 500]);
            subplot(1,3,1); imshow(I_rotated); title('Image (Rotated)');
            subplot(1,3,2); imshow(BWlumen_rotated); title('SAM Mask (Rotated)');
            subplot(1,3,3); imshow(I_rotated); hold on;
            if any(BWlumen_rotated(:)), visboundaries(BWlumen_rotated,'Color','r'); end
            hold off; title('Overlay');
            saveas(figSAM, fullfile(debugFolder, [baseName '_SAM_debug.png']));
            close(figSAM);
        end
        
        % ================================================================
        % Basic lumen metrics (use ROTATED mask)
        % ================================================================
        lumenFound = any(BWlumen_rotated(:));
        sagValid = false;
        
        if lumenFound
            rp = regionprops(BWlumen_rotated, 'Area', 'BoundingBox');
            [~,k] = max([rp.Area]);
            bb = rp(k).BoundingBox; 
            T.LumenArea_px(i)   = rp(k).Area;
            T.LumenWidth_px(i)  = bb(3);
            T.LumenHeight_px(i) = bb(4);
            
            % ===== SAG ANALYSIS (use ROTATED mask) =====
            sagMetrics = measureMembraneSag(BWlumen_rotated, T.mmPerPx(i), false, ...
                                            T.H_layers(i), T.Width_px(i), ...
                                            layerHeight_mm, pixelWidth_mm);
            
            sagValid = sagMetrics.valid;
            
            if sagValid
                % --- Sag measurements ---
                T.SagDepth_px(i)                = sagMetrics.sagDepth_px;
                T.SagDepth_mm(i)                = sagMetrics.sagDepth_mm;
                T.SagPct_ofMeasuredHeight(i)   = sagMetrics.sagPct_ofMeasuredHeight;
                T.SagPct_ofTheoreticalHeight(i) = sagMetrics.sagPct_ofTheoreticalHeight;
                T.SagPct_ofWidthSpan(i)         = sagMetrics.sagPct_ofWidthSpan;
                T.ParabolaR2(i)                 = sagMetrics.parabolaR2;
                
                T.SagArea_px2(i)                = sagMetrics.sagArea_px2;

                % --- Validation Flags ---
                T.IsVertexBetween(i)    = sagMetrics.isVertexBetween;
                T.IsVertexLowerLeft(i)  = sagMetrics.isVertexLowerLeft;
                T.IsVertexLowerRight(i) = sagMetrics.isVertexLowerRight;
                
                % Height
                T.MeasuredHeight_px(i)          = sagMetrics.measuredHeight_px;
                T.MeasuredHeight_mm(i)          = sagMetrics.measuredHeight_mm;
                T.TheoreticalHeight_px(i)       = sagMetrics.theoreticalHeight_px;
                T.TheoreticalHeight_mm(i)       = sagMetrics.theoreticalHeight_mm;
                T.HeightPct_ofTheoretical(i)    = sagMetrics.heightPct_ofTheoretical;
                
                % Width
                T.MeasuredWidth_px(i)           = sagMetrics.measuredWidth_px;
                T.MeasuredWidth_mm(i)           = sagMetrics.measuredWidth_mm;
                T.TheoreticalWidth_px(i)        = sagMetrics.theoreticalWidth_px;
                T.TheoreticalWidth_mm(i)        = sagMetrics.theoreticalWidth_mm;
                T.WidthPct_ofTheoretical(i)     = sagMetrics.widthPct_ofTheoretical;
                
                % Wall tilt
                T.LeftWallTiltAngle_deg(i)      = sagMetrics.leftWallTiltAngle_deg;
                T.RightWallTiltAngle_deg(i)     = sagMetrics.rightWallTiltAngle_deg;
                T.AvgWallTiltAngle_deg(i)       = sagMetrics.avgWallTiltAngle_deg;
                T.TotalWallInward_mm(i)         = sagMetrics.totalWallInward_mm;
                
                % Area
                T.ActualArea_mm2(i)             = sagMetrics.actualArea_mm2;
                T.TheoreticalArea_mm2(i)        = sagMetrics.theoreticalArea_mm2;
                T.AreaPct_ofTheoretical(i)      = sagMetrics.areaPct_ofTheoretical;
                T.ConvexityRatio(i)             = sagMetrics.convexityRatio;

                % BoundingBox-based sag
                T.SagDepthBB_px(i)              = sagMetrics.sagDepthBB_px;
                T.SagDepthBB_mm(i)              = sagMetrics.sagDepthBB_mm;
                T.SagAreaBB_px2(i)              = sagMetrics.sagAreaBB_px2;
                T.SagAreaBB_mm2(i)              = sagMetrics.sagAreaBB_mm2;
                T.SagBB_Pct_ofMeasuredHeight(i) = sagMetrics.sagBB_Pct_ofMeasuredHeight;
                T.SagBB_Pct_ofTheoreticalHeight(i) = sagMetrics.sagBB_Pct_ofTheoreticalHeight;
                T.SagBB_Pct_ofWidthSpan(i)      = sagMetrics.sagBB_Pct_ofWidthSpan;
                T.BaselineDiff_px(i)            = sagMetrics.baselineDiff_px;
                T.BaselineDiff_mm(i)            = sagMetrics.baselineDiff_mm;

                % ===== LUMEN QUALITY ANALYSIS (use ROTATED image & mask) =====
                qualityMetrics = analyzeLumenQuality(BWlumen_rotated, sagMetrics, I_rotated, T.mmPerPx(i));
                
                if qualityMetrics.valid
                    T.LumenBrightness(i)      = qualityMetrics.brightness;
                    T.LumenBrightnessStd(i)   = qualityMetrics.brightnessStd;
                    T.LumenStatus{i}          = qualityMetrics.status;
                    T.Solidity(i)             = qualityMetrics.solidity;
                    T.DebrisArea_px(i)        = qualityMetrics.debrisArea_px;
                    T.DebrisArea_mm2(i)       = qualityMetrics.debrisArea_mm2;
                    T.DebrisPct_ofLumen(i)    = qualityMetrics.debrisPct_ofLumen;
                end
                
                % Save additional debug figures (use ROTATED versions)
                if saveSagDebug
                    figSag = measureMembraneSag_debugFigure(BWlumen_rotated, sagMetrics, T.File{i});
                    saveas(figSag, fullfile(debugFolder, [baseName '_sag_debug.png']));
                    close(figSag);
                    
                    if qualityMetrics.valid
                        figQuality = plotLumenQualityDebug(I_rotated, BWlumen_rotated, qualityMetrics, T.File{i});
                        saveas(figQuality, fullfile(debugFolder, [baseName '_quality_debug.png']));
                        close(figQuality);
                    end
                end
            end
        end
        
        % Record status
        if ~lumenFound
            T.LumenStatus{i} = 'no_lumen_detected';
            T.Notes{i} = 'SAM: no lumen';
        elseif ~sagValid
            T.LumenStatus{i} = 'sag_analysis_failed';
            T.Notes{i} = 'SAM OK, sag failed';
        else
            T.Notes{i} = 'OK';
        end
        
        % Update consolidated columns
        T.Lens(i) = T.Lens_Name(i);
        if isnan(T.Lens(i)) && ~isnan(T.Lens_OCR(i)), T.Lens(i) = T.Lens_OCR(i); end
        T.TiltDeg(i) = T.TiltDeg_Name(i);
        if isnan(T.TiltDeg(i)) && ~isnan(T.TiltDeg_OCR(i)), T.TiltDeg(i) = T.TiltDeg_OCR(i); end
        
    catch ME
        T.Notes{i} = ['FAIL: ' ME.message];
        fprintf('  ERROR: %s\n', ME.message);
        close all
    end
end
toc

disp('=== TABLE AFTER PASS 1 (DATA FILLED) ===');
disp(T(1:min(10,height(T)), {'File', 'Condition', 'SagDepth_mm', 'LumenStatus'}))

%% VISUALIZATION: Sag Analysis Summary Plots (COMPARATIVE)
% Group by Width, RoofLayers, AND Condition
T_sag_stats = groupsummary(T, {'Width_px', 'Roof_layers', 'Condition'}, {'mean', 'std'}, 'SagPct_ofMeasuredHeight');
valid_sag = ~isnan(T_sag_stats.mean_SagPct_ofMeasuredHeight);
T_sag_stats = T_sag_stats(valid_sag, :);

%% VISUALIZATION: Sag Analysis Summary Plots

% Plot Corner-based sag (original method)
plotComparativeSag(T, resultsFolder, 'SagPct_ofMeasuredHeight', 'Corner', '_corner');

% Plot BoundingBox-based sag (new method)
plotComparativeSag(T, resultsFolder, 'SagBB_Pct_ofMeasuredHeight', 'BoundingBox', '_BB');

% You could also plot other metrics easily:
% plotComparativeSag(T, resultsFolder, 'SagPct_ofTheoreticalHeight', 'Corner (vs Theoretical)', '_theo');

% FIGURE 2: Comparative Wall Tilt
plotWallTilt(T, resultsFolder)

%% SAVE FINAL RESULTS
outCsv = fullfile(resultsFolder, 'image_scale_results.csv');
writetable(T, outCsv);
fprintf('Saved (final): %s\n', outCsv);

fprintf('\n=== PROCESSING COMPLETE ===\n');
fprintf('Total images: %d\n', height(T));
fprintf('Successful: %d\n', sum(strcmp(T.Notes, 'OK')));
fprintf('Debug images saved to: %s\n', debugFolder);


%% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function meta = parseImageFilename(base)
    meta.H_layers    = NaN;
    meta.Width_px    = NaN;
    meta.Roof_layers = NaN;
    meta.Replicate   = 0;
    meta.Condition   = 'Unknown'; % Default
    
    % Updated Regex to capture:
    % 1. ConstH value
    % 2. Condition Tag (DefaultALL or PreOptimized)
    % 3. Width value
    % 4. Roof Layer value
    % 5. Replicate (optional)
    
    % Pattern WITH replicate suffix
    % Example: ...ConstH5_DefaultALL_Width100_1layer_1
    tok = regexp(base, 'ConstH(\d+)_([A-Za-z]+)_Width(\d+)_(\d+)layer_(\d+)$', ...
                 'tokens', 'once', 'ignorecase');
    
    if ~isempty(tok)
        meta.H_layers    = str2double(tok{1});
        meta.Condition   = tok{2}; % e.g., 'DefaultALL' or 'PreOptimized'
        meta.Width_px    = str2double(tok{3});
        meta.Roof_layers = str2double(tok{4});
        meta.Replicate   = str2double(tok{5});
        return;
    end
    
    % Pattern WITHOUT replicate suffix
    % Example: ...ConstH5_PreOptimized_Width100_1layer
    tok = regexp(base, 'ConstH(\d+)_([A-Za-z]+)_Width(\d+)_(\d+)layer$', ...
                 'tokens', 'once', 'ignorecase');
    
    if ~isempty(tok)
        meta.H_layers    = str2double(tok{1});
        meta.Condition   = tok{2};
        meta.Width_px    = str2double(tok{3});
        meta.Roof_layers = str2double(tok{4});
        meta.Replicate   = 0;
        return;
    end
    
    disp(['Unmatched pattern: ' base]);
    % If neither matched, throw error or warning
    error('parseImageFilename:PatternMismatch', ...
          'Filename does not match expected pattern: %s', base);
end

function meta = parseFromFilename(base)
    % (Kept same as original)
    meta.lens    = NaN;
    meta.tiltDeg = NaN;
    if isempty(base) || ~ischar(base), return; end
    tok = regexp(base, '(?i)(?:^|[_\-\s])Lens[_\-\s]*(\d+)(?:$|[_\-\s])', 'tokens', 'once');
    if isempty(tok), tok = regexp(base, '(?i)(?:^|[_\-\s])L[_\-\s]*(\d+)(?:$|[_\-\s])', 'tokens', 'once'); end
    if ~isempty(tok) && ~isempty(tok{1}), meta.lens = str2double(tok{1}); end
    tok = regexp(base, '(?i)(?:^|[_\-\s])Tilt[_\-\s]*([0-9]+(?:\.[0-9]+)?)(?:$|[_\-\s])', 'tokens', 'once');
    if isempty(tok), tok = regexp(base, '(?i)(?:^|[_\-\s])T[_\-\s]*([0-9]+(?:\.[0-9]+)?)(?:$|[_\-\s])', 'tokens', 'once'); end
    if ~isempty(tok) && ~isempty(tok{1}), meta.tiltDeg = str2double(tok{1}); end
end

function files = listImages(rootDirs, exts, recurse)
    files = {};
    if ischar(rootDirs), rootDirs = {rootDirs}; end
    for d = 1:numel(rootDirs)
        thisDir = rootDirs{d};
        if ~exist(thisDir, 'dir'), warning('Skip %s',thisDir); continue; end
        if recurse, listing = dir(fullfile(thisDir, '**', '*')); else, listing = dir(thisDir); end
        for k = 1:numel(listing)
            if listing(k).isdir, continue; end
            [~, ~, e] = fileparts(listing(k).name);
            if any(strcmpi(e, exts))
                files{end+1, 1} = fullfile(listing(k).folder, listing(k).name); 
            end
        end
    end
    files = unique(files, 'stable');
end

function out = extractLensAndScaleTextOCR(I, roi, debugPlots)
    Irgb = ensureRGB(I);
    try
        txt = ocr(Irgb);
        out.rawText = txt.Text;
        out.ocrObject = txt;
    catch
        out.rawText = '';
        out.ocrObject = [];
    end
    out.cropRect = [];
end

function [lens, tiltDeg] = parseLensTiltFromOCR(rawText)
    lens = NaN; tiltDeg = NaN;
    if isempty(rawText), return; end
    t = regexprep(rawText, '\s+', ' ');
    tok = regexp(t, 'Lens\s*(\d+)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok), lens = str2double(tok{1}); end
    tok = regexp(t, 'Tilt\s*[:=]?\s*(\d+(?:\.\d+)?)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok), tiltDeg = str2double(tok{1}); end
end

function [val, units] = parseScaleFromOCRText(rawText)
    val = NaN; units = '';
    if isempty(rawText), return; end
    t = strrep(rawText, char(181), 'u');
    t = regexprep(t, '[—–−]', ' ');
    t = regexprep(t, '\s+', ' ');
    tok = regexp(t, '(\d+(?:\.\d+)?)\s*(mm|um|µm|nm)', 'tokens', 'once', 'ignorecase');
    if ~isempty(tok)
        val = str2double(tok{1});
        u = lower(tok{2});
        if strcmp(u,'µm'), u = 'um'; end
        units = strrep(u, ' ', '');
    end
end

function barPx = measureScaleBarPixels(I, roi, thrWhite, minAreaPx, minAspectRatio, minWidthPx, debugPlots)
    Irgb = ensureRGB(I);
    try, ocrOut = ocr(Irgb); words = string(ocrOut.Words); bboxes = ocrOut.WordBoundingBoxes; catch, barPx=NaN; return; end
    if isempty(words), barPx=NaN; return; end
    idx = find(lower(words) == "mm", 1, 'first');
    if isempty(idx), idx = find(contains(lower(words), "mm"), 1, 'first'); end
    if isempty(idx)
        barPx = measureScaleBarPixels_fallback(I, roi, thrWhite, minAreaPx, minAspectRatio, minWidthPx, debugPlots);
        return;
    end
    bb = bboxes(idx,:);
    [H,W,~] = size(Irgb);
    roiX2 = max(1, round(bb(1) - 5));
    roiX1 = max(1, round(roiX2 - 0.30*W));
    roiY1 = max(1, round(bb(2) - 2*bb(4)));
    roiY2 = min(H, round(bb(2) + 3*bb(4)));
    roiImg = Irgb(roiY1:roiY2, roiX1:roiX2, :);
    g = im2double(rgb2gray(roiImg));
    BW = bwareaopen(g > thrWhite, minAreaPx);
    CC = bwconncomp(BW, 8);
    if CC.NumObjects == 0, barPx = NaN; return; end
    stats = regionprops(CC, 'BoundingBox');
    bestW = 0;
    for k = 1:numel(stats)
        wk = stats(k).BoundingBox(3); hk = stats(k).BoundingBox(4);
        if wk>=20 && (wk/max(hk,eps)>=5) && wk>bestW, bestW = wk; end
    end
    barPx = bestW; if barPx==0, barPx=NaN; end
end

function barPx = measureScaleBarPixels_fallback(I, roi, thrWhite, minAreaPx, minAspectRatio, minWidthPx, debugPlots)
    Irgb = ensureRGB(I); Ig = im2double(rgb2gray(Irgb)); [H,W] = size(Ig);
    y0 = max(1, round(H*(1 - roi.bottomFrac))); h = max(1, round(H*roi.heightFrac));
    x0 = max(1, round(W*roi.leftFrac) + 1); w = max(1, round(W*roi.widthFrac));
    BW = bwareaopen(Ig(y0:min(H,y0+h-1), x0:min(W,x0+w-1)) > thrWhite, minAreaPx);
    CC = bwconncomp(BW);
    if CC.NumObjects == 0, barPx = NaN; return; end
    S = regionprops(CC, 'BoundingBox');
    widths = arrayfun(@(s) s.BoundingBox(3), S);
    heights = arrayfun(@(s) s.BoundingBox(4), S);
    aspect = widths ./ max(1e-9, heights);
    isBar = (aspect >= minAspectRatio) & (widths >= minWidthPx);
    if any(isBar), [~,k] = max(widths .* isBar); barPx = widths(k); else, [~,k] = max(widths); barPx = widths(k); end
end

function Irgb = ensureRGB(I)
    if ndims(I) == 2, Irgb = repmat(I, [1 1 3]); else, Irgb = I; end
end

% Include your separate 'make_clean_folder', 'segmentLumenSAM', 'measureMembraneSag', etc. functions here or in path
% (Assuming they are already in your MATLAB path/folder as per previous scripts)