# cowdar

### overview
- an extensible proof-of-concept 
- a free, open source cow weight estimation iOS app which tries to help small time farmers.
- our research found that current automated cattle weight prediction implementations are either:
    - expensive and subscription based
    - free and malfunctioning/not of acceptable quality / don't use lidar and real life distances
    - government funded but obsolete/abandoned/not publicly available
        - note: most research on this topic often involves complex algorithms and data pipelines
        - the current scope of the projected and our limited skillset has been a limiting factor in taking advantage of this, and our predictions are not as accurate as state of the art approaches, but can be improved over time

### current approach
- simulatenously extracts a 3D LiDAR point cloud, a photo image, and phone intrinsic data (helps to calculate real life distances) from compatible iOS devices with LIDAR hardware
- sends that data to a `fastapi` python server
    - the photo image is passed into a custom trained `yolov8m-pose` model with `100 epochs` using a dataset of labelled cow poses created by [Sorin Workspace](https://universe.roboflow.com/sorin-workspace/cow-pose-estimation-fxosp-4ac4b) of `1042` total images (`729` training, `209` validation, `104` testing) to analyse points of interest on the cow (approx 30 min on Nvidia T4)
        - this model outputs a set of normalised coordinates (normalised refers to a relative x,y value range of 0-1, as opposed to pixel measurements)
        - special note: point prediction is particularly difficult on angus cows due to their extremely dark skin colour, and we are currently experimenting with the model training and image pre processing to improve this
    - the 3D LiDAR point cloud is mathematically projected onto a 2D image plane
    - the server matches the normalised coordinates to the closest projected 3D LiDAR points to determine (estimate) the physical distance between points of interest on the cow
    - 3D euclidean distances are extracted between these coordinates (e.g., body length and radius)
    - weight is predicted using a variant of Schaeffer's Formula

### endpoints
- POST /api/tim/dist (with debug logs and debug image i/o)
    - req: multi form, `image` jpg file, `ply` ply file
    - res: json: ```json
                    {
                "success" : boolean,
                "predictedWeight" : number,
                "distPoint2To10" : number,
                "distMidpointTo3" : number
                }
                ``` 