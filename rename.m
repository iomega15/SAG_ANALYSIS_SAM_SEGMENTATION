clear all
clc
close all

srcFolder = fullfile(pwd, 'Cross_section_view');
dstFolder = fullfile(pwd, 'Cross_Section_RVS');

if ~exist(srcFolder, 'dir')
    error('Source folder does not exist: %s', srcFolder);
end

if ~exist(dstFolder, 'dir')
    mkdir(dstFolder);
end

extList = {'*.jpg','*.jpeg','*.png','*.tif','*.tiff','*.bmp'};
files = [];

for k = 1:numel(extList)
    files = [files; dir(fullfile(srcFolder, extList{k}))]; %#ok<AGROW>
end

if isempty(files)
    error('No image files found in %s', srcFolder);
end

fprintf('Found %d image files in %s\n\n', numel(files), srcFolder);

summary = cell(numel(files), 8);

for i = 1:numel(files)
    oldName = files(i).name;
    oldPath = fullfile(files(i).folder, files(i).name);

    [~, baseName, ext] = fileparts(oldName);

    % Parse date from filename if present
    dateToken = regexp(baseName, '(\d{4})_(\d{2})_(\d{2})', 'tokens', 'once');

    if ~isempty(dateToken)
        yyyy = str2double(dateToken{1});
        mm   = str2double(dateToken{2});
        dd   = str2double(dateToken{3});
        dt   = datetime(yyyy, mm, dd);
        dateSource = 'filename';
    else
        [dt, dateSource] = getOldestFileDate(oldPath);
    end

    dateStr = datestr(dt, 'mmddyy');

    % Parse height
    tokH = regexp(baseName, 'ConstH(\d+)', 'tokens', 'once', 'ignorecase');
    if isempty(tokH)
        warning('Skipping file (no ConstH found): %s', oldName);
        continue
    end
    H = str2double(tokH{1});

   % Parse width — simple dedicated match
tokW = regexp(baseName, 'Width(\d+)', 'tokens', 'once', 'ignorecase');
if isempty(tokW)
    warning('Skipping file (no Width found): %s', oldName);
    continue
end
W = str2double(tokW{1});

% Parse replicate — explicit pattern: Width##_R followed by space/( or end
% This avoids optional-group ambiguity that caused R to always read as 0
tokR = regexp(baseName, 'Width\d+_(\d+)\s*[\s\(]', 'tokens', 'once', 'ignorecase');
if ~isempty(tokR) && ~isempty(tokR{1})
    R = str2double(tokR{1});
else
    R = 0;
end

    % Parse membrane layers from trailing parentheses
    tokML = regexp(baseName, '\((\d+)\)\s*$', 'tokens', 'once');
    if isempty(tokML)
        warning('Skipping file (no membrane layer in parentheses): %s', oldName);
        continue
    end
    ML = str2double(tokML{1});

    % Build new filename
    newName = sprintf('H%d_W%d_ML%d_R%d_%s%s', H, W, ML, R, dateStr, lower(ext));
    newPath = fullfile(dstFolder, newName);

    if exist(newPath, 'file')
        [newName, newPath] = makeUniqueName(dstFolder, dateStr, H, W, ML, R, lower(ext));
    end

    copyfile(oldPath, newPath);

    summary{i,1} = oldName;
    summary{i,2} = newName;
    summary{i,3} = char(string(dt, 'MM/dd/yyyy HH:mm:ss'));
    summary{i,4} = dateSource;
    summary{i,5} = H;
    summary{i,6} = W;
    summary{i,7} = ML;
    summary{i,8} = R;

    fprintf('%4d/%4d  %s\n', i, numel(files), oldName);
    fprintf('          -> %s\n\n', newName);
end

emptyRows = cellfun(@isempty, summary(:,1));
summary(emptyRows,:) = [];

T = cell2table(summary, ...
    'VariableNames', {'OriginalName','NewName','ChosenDate','DateSource','H_layers','Width_px','MembraneLayers','Repeat'});

outTable = fullfile(dstFolder, 'rename_summary.csv');
writetable(T, outTable);

fprintf('Done.\n');
fprintf('Copied renamed files to: %s\n', dstFolder);
fprintf('Summary table saved to:  %s\n', outTable);

function [dtOldest, sourceName] = getOldestFileDate(filePath)
    fi = System.IO.FileInfo(filePath);

    dtCreate = dotNetDateTimeToDatetime(fi.CreationTime);
    dtWrite  = dotNetDateTimeToDatetime(fi.LastWriteTime);
    dtAccess = dotNetDateTimeToDatetime(fi.LastAccessTime);

    allDates = [dtCreate, dtWrite, dtAccess];
    [dtOldest, idx] = min(allDates);

    switch idx
        case 1
            sourceName = 'creation_time';
        case 2
            sourceName = 'modified_time';
        case 3
            sourceName = 'accessed_time';
    end
end

function dt = dotNetDateTimeToDatetime(netDT)
    y  = netDT.Year;
    mo = netDT.Month;
    d  = netDT.Day;
    h  = netDT.Hour;
    mi = netDT.Minute;
    s  = netDT.Second;
    dt = datetime(double(y), double(mo), double(d), double(h), double(mi), double(s));
end

function [uniqueName, uniquePath] = makeUniqueName(dstFolder, dateStr, H, W, ML, R, ext)
    n = 1;
    while true
        uniqueName = sprintf('H%d_W%d_ML%d_R%d_%s_dup%d%s', H, W, ML, R, dateStr, n, ext);
        uniquePath = fullfile(dstFolder, uniqueName);
        if ~exist(uniquePath, 'file')
            return
        end
        n = n + 1;
    end
end