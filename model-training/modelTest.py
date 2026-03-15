from ultralytics import YOLO

model = YOLO("best.pt") 

# 2. Run inference on your test file
results = model.predict(
    source="reef-farm.webp", 
    conf=0.1,      # Only show predictions it is at least 50% confident about
    save=True,     # Saves a new copy of the image with the skeleton drawn on it
    show=True      # Pops up a window to show you the result immediately
)