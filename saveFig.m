function saveFig(fig, showFigures, debugFolder, baseName, suffix)
% SAVEFIG  Save a figure to disk or leave it open for display.
%
% Inputs:
%   fig         - figure handle
%   showFigures - logical, true = leave open on screen, false = save and close
%   debugFolder - path to folder where figure will be saved
%   baseName    - base filename string (no extension)
%   suffix      - filename suffix including extension e.g. '_step0_input.png'

if ~showFigures
    saveas(fig, fullfile(debugFolder, [baseName suffix]));
    close(fig);
end
end