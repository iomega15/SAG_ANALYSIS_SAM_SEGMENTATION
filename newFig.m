function fig = newFig(showFigures, w, h)
% NEWFIG  Create a figure that is either visible or hidden.
%
% Inputs:
%   showFigures - logical, true = display on screen, false = hidden for saving
%   w           - figure width in pixels
%   h           - figure height in pixels
%
% Output:
%   fig         - figure handle

if showFigures
    fig = figure('Position', [100 100 w h]);
else
    fig = figure('Visible', 'off', 'Position', [100 100 w h]);
end
end
