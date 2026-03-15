from ultralytics import YOLO
from PIL import Image

model = YOLO("best.pt")


def parseImageNormCoords(img: str) -> tuple[bool, list[tuple[float, float]] | None]:
    # Initialise results
    res = []

    # Get Image Width / Height
    width, height = 0, 0
    try:
        with Image.open(img) as img:
            width, height = img.size
    except:
        return (True, None)
    print(f'Width: {width}, Height: {height}')
    
    # Predict points of source image
    results = model.predict(source=img)
    keypoints = results[0].keypoints
    points_array = keypoints.data[0] # # The .data attribute contains the raw [x, y, confidence] for all 20 points, Shape will be (1, 20, 3) -> 1 cow, 20 points, 3 values each
    
    # Parse results
    for i, point in enumerate(points_array):
        if i in [2,3,10]:
            res.append((
                point[0].item()/width,
                point[1].item()/height
            ))
    return (False, res)

def parseImageUnnormCoords(img: str) -> tuple[bool, list[tuple[float, float]] | None]:
    # Initialise results
    res = []

    # Get Image Width / Height
    width, height = 0, 0
    try:
        with Image.open(img) as img:
            width, height = img.size
    except:
        return (True, None)
    print(f'Width: {width}, Height: {height}')
    
    # Predict points of source image
    results = model.predict(source=img)
    keypoints = results[0].keypoints
    points_array = keypoints.data[0] # # The .data attribute contains the raw [x, y, confidence] for all 20 points, Shape will be (1, 20, 3) -> 1 cow, 20 points, 3 values each
    
    # Parse results
    for i, point in enumerate(points_array):
        if i in [2,3,10]:
            res.append( (point[0].item(),point[1].item()) )
    return (False, res)


def ignore(img: str):
    # Initialise results
    res = []

    # Get Image Width / Height
    width, height = 0, 0
    try:
        with Image.open('reef-farm.webp') as img:
            width, height = img.size
    except:
        return (True, None)
    print(f'Width: {width}, Height: {height}')
    
    # Predict points of source image
    results = model.predict(source=img)
    keypoints = results[0].keypoints
    points_array = keypoints.data[0] # # The .data attribute contains the raw [x, y, confidence] for all 20 points, Shape will be (1, 20, 3) -> 1 cow, 20 points, 3 values each
    
    # Parse results
    for i, point in enumerate(points_array):
        x_coord = points_array[i][0].item()
        y_coord = points_array[i][1].item()
        confidence = points_array[i][2].item()
        print(f"Keypoint {i} is located at X:{x_coord}, Y:{y_coord} with {confidence*100:.1f}% confidence.")
# Testing
#print(parseImageUnnormCoords("reef-farm.webp"))
# print(parseImageNormCoords("reef-farm.webp"))
#ignore("reef-farm.webp")