# sam_segment_simple.py - Just returns all SAM masks, no filtering
import cv2
import numpy as np
import torch
from segment_anything import sam_model_registry, SamAutomaticMaskGenerator

# Load image
image = cv2.imread(image_path)
image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
h, w = image.shape[:2]

# Load SAM
sam = sam_model_registry["vit_b"](checkpoint=checkpoint_path)
device = "cuda" if torch.cuda.is_available() else "cpu"
sam.to(device)

mask_generator = SamAutomaticMaskGenerator(
    model=sam,
    points_per_side=32,
    pred_iou_thresh=0.86,
    stability_score_thresh=0.92,
    min_mask_region_area=50,
)

all_masks = mask_generator.generate(image_rgb)

# Export all masks
num_masks = len(all_masks)
all_masks_array = np.zeros((num_masks, h, w), dtype=np.uint8)
for i, mask_data in enumerate(all_masks):
    all_masks_array[i] = mask_data['segmentation'].astype(np.uint8)

all_masks_out = all_masks_array
num_masks = int(num_masks)