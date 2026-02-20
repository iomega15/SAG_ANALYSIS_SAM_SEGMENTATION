function edge_density = computeHorizontalLayerTexture(Igray, mask)

if sum(mask(:)) < 100
    edge_density = 0;
    return;
end

canny_edges  = edge(Igray, 'Canny', [0.01 0.1]);
edge_density = sum(canny_edges(mask)) / sum(mask(:));
end