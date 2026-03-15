from ultralytics import YOLO
model = YOLO("yolov8m-pose.pt") 
results = model.train(
    data="cow_pose.yaml", 
    epochs=100,           
    imgsz=640,            
    device="0"
)