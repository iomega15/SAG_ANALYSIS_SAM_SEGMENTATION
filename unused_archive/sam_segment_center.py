# sam_segment_simple.py
# Generates ALL masks from SAM with optional debug visualization
import cv2
import numpy as np
import torch
import os
from segment_anything import sam_model_registry, SamAutomaticMaskGenerator

# 1. Load image
image = cv2.imread(image_path)
image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

# 2. Load SAM
sam = sam_model_registry["vit_b"](checkpoint=checkpoint_path)
device = "cuda" if torch.cuda.is_available() else "cpu"
sam.to(device)

# 3. Create automatic mask generator
mask_generator = SamAutomaticMaskGenerator(
    model=sam,
    points_per_side=32,
    pred_iou_thresh=0.86,
    stability_score_thresh=0.92,
    crop_n_layers=1,
    crop_n_points_downscale_factor=2,
    min_mask_region_area=100,
)

# 4. Generate all masks
masks_data = mask_generator.generate(image_rgb)

# 5. Sort by area (largest first)
masks_data = sorted(masks_data, key=lambda x: x['area'], reverse=True)

# 6. Extract mask arrays
num_masks = len(masks_data)

if num_masks == 0:
    all_masks_out = np.zeros((1, image_rgb.shape[0], image_rgb.shape[1]), dtype=bool)
    num_masks = 0
else:
    all_masks_out = np.stack([m['segmentation'] for m in masks_data], axis=0)

# 7. Optional: Save debug visualization
# Check if debug_path variable exists (passed from MATLAB)
try:
    if debug_path and len(debug_path) > 0:
        # Create colored overlay of all masks
        h, w = image_rgb.shape[:2]
        overlay = image_rgb.copy().astype(np.float32)
        
        # Generate distinct colors for each mask
        np.random.seed(42)
        colors = np.random.randint(0, 255, size=(num_masks, 3), dtype=np.uint8)
        
        # Create mask visualization
        mask_viz = np.zeros((h, w, 3), dtype=np.uint8)
        for i, mask_info in enumerate(masks_data):
            mask = mask_info['segmentation']
            mask_viz[mask] = colors[i]
        
        # Blend with original image
        alpha = 0.5
        blended = (overlay * (1 - alpha) + mask_viz.astype(np.float32) * alpha).astype(np.uint8)
        
        # Add mask numbers
        for i, mask_info in enumerate(masks_data):
            mask = mask_info['segmentation']
            # Find centroid
            ys, xs = np.where(mask)
            if len(xs) > 0:
                cx, cy = int(np.mean(xs)), int(np.mean(ys))
                cv2.putText(blended, f'M{i+1}', (cx-10, cy+5), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
        
        # Save debug image
        cv2.imwrite(debug_path, cv2.cvtColor(blended, cv2.COLOR_RGB2BGR))
except NameError:
    pass  # debug_path not defined, skip debug output

# 8. Export results
all_masks_out = all_masks_out
num_masks = num_masks