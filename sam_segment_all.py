# sam_segment_all.py
# Gets CENTER-BASED lumen mask PLUS all other masks for texture analysis
import cv2
import numpy as np
import torch
from segment_anything import sam_model_registry, SamPredictor

# Load image
image = cv2.imread(image_path)
image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
h, w = image.shape[:2]

# Load SAM
sam = sam_model_registry["vit_b"](checkpoint=checkpoint_path)
device = "cuda" if torch.cuda.is_available() else "cpu"
sam.to(device)
predictor = SamPredictor(sam)
predictor.set_image(image_rgb)

# ============================================
# STEP 1: Get LUMEN mask using CENTER point
# ============================================
cx = int(target_x)
cy = int(target_y)

center_point = np.array([[cx, cy]])
point_labels = np.array([1])

masks, scores, _ = predictor.predict(
    point_coords=center_point,
    point_labels=point_labels,
    multimask_output=False,
)

lumen_mask = masks[0].astype(np.uint8)
lumen_confidence = float(scores[0])

# ============================================
# STEP 2: Get ALL OTHER masks using point grid
# ============================================
all_masks_list = []
all_scores_list = []

# Grid of points
points_per_side = 6
x_coords = np.linspace(w * 0.1, w * 0.9, points_per_side)
y_coords = np.linspace(h * 0.1, h * 0.9, points_per_side)

for y in y_coords:
    for x in x_coords:
        px, py = int(x), int(y)
        
        # Skip if inside lumen mask
        if lumen_mask[py, px] > 0:
            continue
        
        point = np.array([[px, py]])
        label = np.array([1])
        
        point_masks, point_scores, _ = predictor.predict(
            point_coords=point,
            point_labels=label,
            multimask_output=True,
        )
        
        best_idx = np.argmax(point_scores)
        all_masks_list.append(point_masks[best_idx])
        all_scores_list.append(point_scores[best_idx])

# ============================================
# STEP 3: Remove duplicates
# ============================================
unique_masks = []
unique_scores = []

for i, mask in enumerate(all_masks_list):
    is_duplicate = False
    
    # Check against lumen
    intersection = np.logical_and(mask, lumen_mask).sum()
    union = np.logical_or(mask, lumen_mask).sum()
    if union > 0 and intersection / union > 0.5:
        is_duplicate = True
    
    # Check against existing unique masks
    if not is_duplicate:
        for existing in unique_masks:
            intersection = np.logical_and(mask, existing).sum()
            union = np.logical_or(mask, existing).sum()
            if union > 0 and intersection / union > 0.7:
                is_duplicate = True
                break
    
    if not is_duplicate and all_scores_list[i] > 0.7:
        unique_masks.append(mask)
        unique_scores.append(all_scores_list[i])

# ============================================
# STEP 4: Combine all masks (lumen first)
# ============================================
all_masks_combined = [lumen_mask]
for m in unique_masks:
    all_masks_combined.append(m.astype(np.uint8))

num_masks = len(all_masks_combined)
all_masks_out = np.stack(all_masks_combined, axis=0)

# ============================================
# STEP 5: Export
# ============================================
lumen_mask_out = lumen_mask
confidence_score = lumen_confidence
all_masks_out = all_masks_out
num_masks = int(num_masks)