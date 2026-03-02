function [is_valid, quality, RATIO_THRESHOLD] = validateLumenTexture( ...
    anchor_texture, selected_mask_idx, textureFeatures, quality)

RATIO_THRESHOLD = 1.0;
is_valid = false;

if isempty(selected_mask_idx)
    quality.rejection_reason = 'No lumen candidate was selected';
    return;
end

lumen_density  = textureFeatures(selected_mask_idx);
anchor_density = anchor_texture;  % area-weighted mean of all anchor masks

quality.lumen_density  = lumen_density;
quality.anchor_density = anchor_density;

if anchor_density <= 0
    quality.texture_ratio    = NaN;
    quality.texture_contrast = NaN;
    quality.rejection_reason = 'Anchor has zero texture — cannot validate';
    return;
end

texture_ratio    = lumen_density / anchor_density;
texture_contrast = 1 - texture_ratio;
quality.texture_ratio    = texture_ratio;
quality.texture_contrast = texture_contrast;

if texture_ratio >= RATIO_THRESHOLD
    quality.is_textured      = true;
    quality.rejection_reason = sprintf( ...
        'Lumen (%.4f) >= anchor (%.4f): ratio=%.2f — lumen not formed', ...
        lumen_density, anchor_density, texture_ratio);
else
    is_valid            = true;
    quality.is_textured = false;
end
end