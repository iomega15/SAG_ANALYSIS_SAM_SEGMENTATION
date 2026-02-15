# sam_segment_center.py
# Segments a single object located at a SPECIFIC point passed from MATLAB
import cv2
import numpy as np
import torch
from segment_anything import sam_model_registry, SamPredictor

# 1. Load image
image = cv2.imread(image_path)
image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)

# 2. Load SAM
sam = sam_model_registry["vit_b"](checkpoint=checkpoint_path)
device = "cuda" if torch.cuda.is_available() else "cpu"
sam.to(device)
predictor = SamPredictor(sam)

# 3. Set image
predictor.set_image(image_rgb)

# 4. Use Coordinates passed from MATLAB
# We expect variables 'target_x' and 'target_y' to exist in the scope
cx = int(target_x)
cy = int(target_y)

center_point = np.array([[cx, cy]])
point_labels = np.array([1])  # 1 = foreground point

# 5. Predict
masks, scores, logits = predictor.predict(
    point_coords=center_point,
    point_labels=point_labels,
    multimask_output=False,  # Return only the best mask
)

# 6. Export result
lumen_mask_out = masks[0].astype(np.uint8)
confidence_score = float(scores[0])