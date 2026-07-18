function [is_valid, quality, MIN_CONTRAST, polarity_out] = validateLumenTexture( ...
    Igray, allMasksExclusive, selected_mask_idx, quality, expectedLumenWH_px)
%VALIDATELUMENTEXTURE  Intensity-contrast lumen validation + polarity.
%
% REWRITTEN 2026-07-18 (fix batch 4). The old texture-density-ratio gate
% (lumen_density/anchor_density >= 1 => "not formed") was proven
% unsalvageable during the run-1..4 debug-figure reviews: its false-reject
% band (real dark lumens at ratios 1.06-2.20) fully overlapped its correct
% rejects (collapse at 1.97+), and the definitive counterexample was two
% W5 images with the SAME ratio 1.46 and OPPOSITE ground truth. The imfill
% polarity vote it relied on also mislabeled ~14 dark lumens as 'bright'.
%
% Replacement logic — judge the selected mask by what a lumen physically IS:
%   1. INTENSITY CONTRAST: median gray of the mask interior vs a local
%      surrounding ring. A real lumen is measurably darker (shadowed cavity)
%      or brighter (transilluminated opening) than the printed material
%      around it. |contrast| < MIN_CONTRAST => the mask sits on plain
%      material => not a lumen.
%   2. POLARITY from the SIGN of that contrast (replaces the imfill vote).
%   3. ASPECT PRIOR (bright only): the nominal channel geometry (from the
%      filename, via expectedLumenWH_px) bounds the expected rectangle
%      aspect. Bright false positives at W1-2 were thin horizontal glint
%      slivers with aspects orders of magnitude off; real open lumens track
%      the nominal shape. Dark masks are exempt: genuinely incipient dark
%      lumens are physically squished flat, so their aspect legitimately
%      deviates (per Roman: partial dark captures are acceptable).
%
% Wide-W membrane collapse (the one thing the old gate caught correctly) is
% now handled at the map level by the touchdown inference in
% plotOcclusionHeatmap, not per-image here.
%
% quality field reuse (so the FINAL debug figure and the results table keep
% their columns): texture_contrast/texture_ratio now hold the SIGNED
% intensity contrast; lumen_density/anchor_density hold the mask/ring
% median gray levels.

MIN_CONTRAST = 0.06;   % min |median(mask) - median(ring)| on 0..1 gray
ASPECT_TOL   = 4;      % bright mask bbox aspect may deviate from the
                       % expected lumen aspect by at most this factor
RING_RADIUS  = 25;     % px, local surroundings ring width

is_valid     = false;
polarity_out = 'unknown';

if isempty(selected_mask_idx)
    if isempty(quality.rejection_reason)   % keep a more specific upstream reason
        quality.rejection_reason = 'No lumen candidate was selected';
    end
    return;
end

mask = squeeze(allMasksExclusive(selected_mask_idx, :, :));
ring = imdilate(mask, strel('disk', RING_RADIUS)) & ~mask;

if ~any(mask(:)) || ~any(ring(:))
    quality.rejection_reason = 'Selected mask empty or has no surroundings';
    return;
end

maskMed = median(Igray(mask));
ringMed = median(Igray(ring));
contrast = maskMed - ringMed;   % >0: brighter than surroundings; <0: darker

quality.lumen_density    = maskMed;
quality.anchor_density   = ringMed;
quality.texture_ratio    = contrast;
quality.texture_contrast = contrast;

if abs(contrast) < MIN_CONTRAST
    quality.rejection_reason = sprintf( ...
        'No intensity contrast vs surroundings (mask %.2f vs ring %.2f, d=%+.2f) — not a lumen', ...
        maskMed, ringMed, contrast);
    return;
end

if contrast > 0
    polarity_out = 'bright';
else
    polarity_out = 'dark';
end

% --- Aspect prior, bright candidates only ---
if strcmp(polarity_out, 'bright') && nargin >= 5 && numel(expectedLumenWH_px) == 2 && ...
        all(isfinite(expectedLumenWH_px)) && all(expectedLumenWH_px > 0)
    rp = regionprops(mask, 'BoundingBox');
    if ~isempty(rp)
        bb = rp(1).BoundingBox;
        maskAspect = bb(3) / max(bb(4), 1);
        expAspect  = expectedLumenWH_px(1) / expectedLumenWH_px(2);
        deviation  = max(maskAspect / expAspect, expAspect / maskAspect);
        if deviation > ASPECT_TOL
            quality.rejection_reason = sprintf( ...
                'Bright mask aspect %.2f vs expected %.2f (%.0fx off) — glint/sliver, not an open lumen', ...
                maskAspect, expAspect, deviation);
            polarity_out = 'unknown';
            return;
        end
    end
end

is_valid            = true;
quality.is_textured = false;
end
