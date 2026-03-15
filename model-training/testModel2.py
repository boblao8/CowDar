import cv2
from ultralytics import YOLO

# 1. Load your trained model
model = YOLO("best.pt")

# 2. Run prediction on a test image
img_path = "ajay-test.webp"
results = model.predict(source=img_path)

# 3. Read the image using OpenCV so we can draw on it
img = cv2.imread(img_path)

# Extract the keypoints for the first cow detected
keypoints = results[0].keypoints.data[0] 

# 4. Loop through all 20 points
for index, kp in enumerate(keypoints):
    if index in [2,3,10,7]:
        x, y, conf = int(kp[0].item()), int(kp[1].item()), kp[2].item()
        
        # Only draw the number if the model is actually confident the point is there
        if conf > 0.2: 
            # Draw a small red dot at the exact joint
            cv2.circle(img, (x, y), radius=6, color=(0, 0, 255), thickness=-1)
            
            # Write the index number (0, 1, 2...) in bright green next to the dot
            cv2.putText(img, str(index), (x + 8, y - 8), 
                        cv2.FONT_HERSHEY_SIMPLEX, fontScale=1, 
                        color=(0, 255, 0), thickness=2)

# 5. Save the final image to your folder
output_filename = "mapped_cow_2.jpg"    
cv2.imwrite(output_filename, img)
print(f"Success! Open {output_filename} to see your index map.")