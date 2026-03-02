function saveErrorDebug(ME, debugFolder, baseName, showFigures)
fig = newFig(showFigures, 600, 300);
text(0.5,0.5,sprintf('ERROR:\n%s\n\n%s',ME.message,ME.identifier),...
    'FontSize',12,'HorizontalAlignment','center','Color','r');
axis off;
saveFig(fig, showFigures, debugFolder, baseName, '_ERROR.png');
end