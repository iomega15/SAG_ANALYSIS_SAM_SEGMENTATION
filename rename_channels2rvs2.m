%% RENAME_CHANNELS2RVS2 — import the W110–W150 batch into Cross_Section_RVS2
% Student's July-2026 data drop (Results\Channels) uses an OLD naming
% convention:   H5_Channel_R{r}_W{W} ({N}).jpg
% with TWO quirks relative to the current pipeline convention
% (H5_W{W}_ML{ml}_R{rep}_{MMDDYY}.jpg, as used in Cross_Section_RVS2):
%
%   1. The (N) suffix counts membrane layers in the OPPOSITE direction:
%      (10) means ML1 and (1) means ML10  =>  ML = 11 - N.
%      (Same reversal that once produced the mislabeled Cross_Section_RVS
%      folder — see unused_archive/README there.)
%   2. No experiment-date suffix; the date is derived from the file's
%      oldest filesystem timestamp (min of creation/modified), same rule
%      as the original rename.m.
%   3. Replicates are 1-based (R1..R3); existing RVS2 data is 0-based
%      (R0..R2)  =>  rep = r - 1.
%
% COPIES (does not move) the renamed files into Cross_Section_RVS2 and
% writes a rename summary CSV back into the source folder.

clear; clc;

dropboxRoot = fullfile(getenv('USERPROFILE'), 'Dropbox');
srcFolder = fullfile(dropboxRoot, 'MANUSCRIPTS', 'micromachines_valve_printing_framework', ...
    'Results', 'Channels');
dstFolder = fullfile(dropboxRoot, 'MANUSCRIPTS', 'micromachines_valve_printing_framework', ...
    'Figures', 'NanoClear', 'Sorted_ConstH5', 'Cross_Section_RVS2');

assert(exist(srcFolder, 'dir') == 7, 'Source folder not found: %s', srcFolder);
assert(exist(dstFolder, 'dir') == 7, 'Destination folder not found: %s', dstFolder);

files = dir(fullfile(srcFolder, '*.jpg'));
fprintf('Found %d jpg files in %s\n', numel(files), srcFolder);

summary = cell(numel(files), 3);
nCopied = 0; nSkipped = 0;

for i = 1:numel(files)
    oldName = files(i).name;

    tok = regexp(oldName, '^H5_Channel_R(\d+)_W(\d+) \((\d+)\)\.jpg$', 'tokens', 'once');
    if isempty(tok)
        warning('Skipping (pattern mismatch): %s', oldName);
        nSkipped = nSkipped + 1;
        continue;
    end

    r = str2double(tok{1});
    W = str2double(tok{2});
    N = str2double(tok{3});

    ML  = 11 - N;    % REVERSED numbering: (10)->ML1, (1)->ML10
    rep = r - 1;     % 1-based -> 0-based replicates

    % Oldest available timestamp -> experiment-batch date (mmddyy)
    fi = System.IO.FileInfo(fullfile(srcFolder, oldName));
    dtCreate = datetime(double(fi.CreationTime.Year), double(fi.CreationTime.Month), double(fi.CreationTime.Day));
    dtWrite  = datetime(double(fi.LastWriteTime.Year), double(fi.LastWriteTime.Month), double(fi.LastWriteTime.Day));
    dateStr  = char(datetime(min([dtCreate dtWrite]), 'Format', 'MMddyy'));

    newName = sprintf('H5_W%d_ML%d_R%d_%s.jpg', W, ML, rep, dateStr);
    newPath = fullfile(dstFolder, newName);

    if exist(newPath, 'file')
        warning('Destination exists, NOT overwriting: %s', newName);
        nSkipped = nSkipped + 1;
        continue;
    end

    copyfile(fullfile(srcFolder, oldName), newPath);
    nCopied = nCopied + 1;
    summary(nCopied, :) = {oldName, newName, dateStr};
end

summary = summary(1:nCopied, :);
S = cell2table(summary, 'VariableNames', {'OriginalName', 'NewName', 'DateUsed'});
outCsv = fullfile(srcFolder, 'rename_to_RVS2_summary.csv');
writetable(S, outCsv);

fprintf('Copied %d, skipped %d. Summary: %s\n', nCopied, nSkipped, outCsv);
