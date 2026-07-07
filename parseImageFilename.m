function meta = parseImageFilename(base)
meta.H_layers    = NaN;
meta.Width_px    = NaN;
meta.Roof_layers = NaN;   % maps to ML# in new format
meta.Replicate   = 0;
meta.Condition   = 'Default';  % no condition tag in new format

% New format: H{n}_W{n}_ML{n}_R{n}_{MMDDYY}
% Example:    H5_W11_ML1_R1_030226

% Parse H
tok = regexp(base, 'H(\d+)', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), meta.H_layers = str2double(tok{1}); end

% Parse W
tok = regexp(base, 'W(\d+)', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), meta.Width_px = str2double(tok{1}); end

% Parse ML (membrane layers → stored in Roof_layers column)
tok = regexp(base, 'ML(\d+)', 'tokens', 'once', 'ignorecase');
if ~isempty(tok), meta.Roof_layers = str2double(tok{1}); end

% Parse R (replicate)
tok = regexp(base, '_R(\d+)_', 'tokens', 'once', 'ignorecase');
if ~isempty(tok)
    meta.Replicate = str2double(tok{1});
end

if isnan(meta.H_layers) || isnan(meta.Width_px) || isnan(meta.Roof_layers)
    disp(['Unmatched pattern: ' base]);
    error('parseImageFilename:PatternMismatch', ...
        'Filename does not match expected pattern: %s', base);
end
end