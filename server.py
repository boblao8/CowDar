from fastapi import FastAPI, File, Form, UploadFile, HTTPException, Request
import math
import json
import os
import shutil
import tempfile
from contextlib import asynccontextmanager
from datetime import datetime

import numpy as np
from fastapi import FastAPI, File, UploadFile, HTTPException, Request
from ultralytics import YOLO
from PIL import Image, ImageDraw, ImageFont, ImageOps


DEBUG_IMAGE_DIR = "debug_images"

KEYPOINT_INDICES: frozenset[int] = frozenset({2, 3, 7, 10})

POINT_COLORS: dict[str, tuple[int, int, int]] = {
    "point_2":       (255, 80,  80),
    "point_3":       (80,  200, 80),
    "point_10":      (80,  80,  255),
    "midpoint_2_10": (255, 200, 0),
}

_FALLBACK_COLORS: list[tuple[int, int, int]] = [
    (255, 80,  80),
    (80,  200, 80),
    (80,  80,  255),
    (255, 200, 0),
    (200, 80,  255),
]

_RADIUS    = 8
_LINE_W    = 2
_FONT_SIZE = 16

GIRTH_CIRCUMFERENCE_MULTIPLIER: float = 2 * math.pi

BREED_WEIGHT_MULTIPLIERS: dict[str, float] = {
    "Angus":        1.0,
    "Hereford":     1.0,
    "Brahman":      1.05,
    "Droughtmaster":1.0,
    "Wagyu":        0.90,
    "Charolais":    1.10,
    "Simmental":    1.05,
    "Other":        1.0,
}

SEX_WEIGHT_MULTIPLIERS: dict[str, float] = {
    "Bull":   1.15,
    "Cow":    1.00,
    "Steer":  1.00,
    "Heifer": 0.90,
    "Calf":   0.70,
}


def save_debug_image(
    img_path: str,
    named_pixel_coords: dict[str, tuple[float, float]],
    endpoint_name: str,
    original_filename: str,
    draw_lines: list[tuple[str, str]] | None = None,
) -> str:
    os.makedirs(DEBUG_IMAGE_DIR, exist_ok=True)

    try:
        img = Image.open(img_path).convert("RGB")
    except Exception as e:
        print(f"[Debug] Could not open image for overlay: {e}")
        return ""

    draw = ImageDraw.Draw(img)

    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", _FONT_SIZE
        )
    except Exception:
        font = ImageFont.load_default()

    if draw_lines:
        for label_a, label_b in draw_lines:
            if label_a in named_pixel_coords and label_b in named_pixel_coords:
                xa, ya = named_pixel_coords[label_a]
                xb, yb = named_pixel_coords[label_b]
                draw.line([(xa, ya), (xb, yb)], fill=(255, 255, 255), width=_LINE_W)

    for idx, (label, (px, py)) in enumerate(named_pixel_coords.items()):
        color = POINT_COLORS.get(label, _FALLBACK_COLORS[idx % len(_FALLBACK_COLORS)])
        draw.ellipse(
            [(px - _RADIUS, py - _RADIUS), (px + _RADIUS, py + _RADIUS)],
            fill=color,
            outline=(255, 255, 255),
            width=2,
        )
        draw.text((px + _RADIUS + 3, py - _RADIUS), label, fill=color, font=font)

    ts   = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    base = os.path.splitext(os.path.basename(original_filename))[0]
    out_path = os.path.join(DEBUG_IMAGE_DIR, f"{endpoint_name}_{ts}_{base}.jpg")

    img.save(out_path, "JPEG", quality=90)
    print(f"[Debug] Overlay saved -> {out_path}")
    return out_path


@asynccontextmanager
async def lifespan(app: FastAPI):
    print("Loading YOLO model...")
    app.state.model = YOLO("model.pt")
    os.makedirs(DEBUG_IMAGE_DIR, exist_ok=True)
    print(f"Model loaded. Debug images -> {DEBUG_IMAGE_DIR}/")
    yield
    app.state.model = None


app = FastAPI(lifespan=lifespan)


def getFourPOI(img_path: str, model) -> tuple[bool, dict | None]:
    try:
        with Image.open(img_path) as pil_img:
            pil_img = ImageOps.exif_transpose(pil_img)
            width, height = pil_img.size
            pil_img.save(img_path)
    except Exception as e:
        print(f"PIL Error: {e}")
        return (True, None)

    results = model.predict(source=img_path)

    if not results or not results[0].keypoints or results[0].keypoints.data.shape[1] <= 10:
        detected = results[0].keypoints.data.shape[1] if results and results[0].keypoints else 0
        print(f"[YOLO] Insufficient keypoints (need >10, got {detected})")
        return (False, None)

    points_array = results[0].keypoints.data[0]

    x2,  y2  = points_array[2][0].item(),  points_array[2][1].item()
    x3,  y3  = points_array[3][0].item(),  points_array[3][1].item()
    x10, y10 = points_array[10][0].item(), points_array[10][1].item()

    xM = (x2 + x10) / 2.0
    yM = (y2 + y10) / 2.0

    print(f"[YOLO] Keypoints in {width}x{height}:")
    print(f"  point_2       = ({x2:.1f}, {y2:.1f})")
    print(f"  point_3       = ({x3:.1f}, {y3:.1f})")
    print(f"  point_10      = ({x10:.1f}, {y10:.1f})")
    print(f"  midpoint_2_10 = ({xM:.1f}, {yM:.1f})")

    return (False, {
        "point_2":       {"x": x2  / width, "y": y2  / height},
        "point_3":       {"x": x3  / width, "y": y3  / height},
        "point_10":      {"x": x10 / width, "y": y10 / height},
        "midpoint_2_10": {"x": xM  / width, "y": yM  / height},
    })


@app.post("/api/tim/dist")
async def get_tim_dist(
    request: Request,
    image: UploadFile = File(...),
    ply:   UploadFile = File(...),
):
    print(f"\n[tim/dist] Request received")
    img_ext = os.path.splitext(image.filename)[1].lower() or ".jpg"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=img_ext) as tmp_img:
            shutil.copyfileobj(image.file, tmp_img)
            temp_img_path = tmp_img.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".ply") as tmp_ply:
            shutil.copyfileobj(ply.file, tmp_ply)
            temp_ply_path = tmp_ply.name

        model = request.app.state.model
        error, coords_data = getFourPOI(temp_img_path, model)

        if error or not coords_data:
            print("[tim/dist] Failed to detect required keypoints.")
            return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

        points_3d = []
        with open(temp_ply_path, "r") as f:
            lines = f.readlines()

        header_end = lines.index("end_header\n") + 1 if "end_header\n" in lines else 0

        for line in lines[header_end:]:
            parts = line.strip().split()
            if len(parts) >= 3:
                points_3d.append([float(parts[0]), float(parts[1]), float(parts[2])])

        if not points_3d:
            return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

        points_3d = np.array(points_3d)

        image_width, image_height = 1920, 1440
        fx, fy = 1450, 1450
        cx, cy = image_width / 2, image_height / 2

        xs = points_3d[:, 0]
        ys = -points_3d[:, 1]
        zs = -points_3d[:, 2].copy()
        zs[np.abs(zs) < 1e-6] = 1e-6

        u = fx * (xs / zs) + cx
        v = fy * (ys / zs) + cy
        projected_norm = np.column_stack((u / image_width, v / image_height))

        matched_3d   = {}
        target_keys  = ["point_2", "point_10", "midpoint_2_10", "point_3"]

        for key in target_keys:
            target_pt = np.array([coords_data[key]["x"], coords_data[key]["y"]])
            dists     = np.linalg.norm(projected_norm - target_pt, axis=1)
            best_idx  = np.argmin(dists)
            matched_3d[key] = points_3d[best_idx]

        distPoint2To10  = float(np.linalg.norm(matched_3d["point_2"]       - matched_3d["point_10"]))
        distMidpointTo3 = float(np.linalg.norm(matched_3d["midpoint_2_10"] - matched_3d["point_3"]))

        weight = ((distPoint2To10 * 100) * (distMidpointTo3 * 100 * 3.14159) ** 2) / 10840

        os.makedirs(DEBUG_IMAGE_DIR, exist_ok=True)
        try:
            with Image.open(temp_img_path) as debug_img:
                draw    = ImageDraw.Draw(debug_img)
                w, h    = debug_img.size

                px_2   = (int(coords_data["point_2"]["x"]       * w), int(coords_data["point_2"]["y"]       * h))
                px_10  = (int(coords_data["point_10"]["x"]      * w), int(coords_data["point_10"]["y"]      * h))
                px_mid = (int(coords_data["midpoint_2_10"]["x"] * w), int(coords_data["midpoint_2_10"]["y"] * h))
                px_3   = (int(coords_data["point_3"]["x"]       * w), int(coords_data["point_3"]["y"]       * h))

                draw.line([px_2, px_10],  fill="red",  width=8)
                draw.line([px_mid, px_3], fill="blue", width=8)

                for px in [px_2, px_10, px_mid, px_3]:
                    draw.ellipse((px[0] - 10, px[1] - 10, px[0] + 10, px[1] + 10), fill="yellow")

                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                debug_img.save(os.path.join(DEBUG_IMAGE_DIR, f"tim_dist_weight_{timestamp}.jpg"))
        except Exception as e:
            print(f"[tim/dist] Failed to save debug image: {e}")

        print(f"[tim/dist] Done. Weight: {weight:.2f} kg\n")

        return {
            "success":         True,
            "predictedWeight": float(round(weight, 2)),
            "distPoint2To10":  float(round(distPoint2To10,  4)),
            "distMidpointTo3": float(round(distMidpointTo3, 4)),
        }

    except Exception as e:
        print(f"[tim/dist] Unhandled exception: {e}")
        return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

    finally:
        if "temp_img_path" in locals() and os.path.exists(temp_img_path):
            os.remove(temp_img_path)
        if "temp_ply_path" in locals() and os.path.exists(temp_ply_path):
            os.remove(temp_ply_path)
            

@app.post("/api/av")
async def get_av(
    request:         Request,
    photo:           UploadFile = File(...),
    bin:             UploadFile = File(...),
    depthX:          int        = Form(...),
    depthY:          int        = Form(...),
    referenceWidth:  float      = Form(...),
    referenceHeight: float      = Form(...),
    intrinsics:      str        = Form(...),
):
    print("\n[av] Request received")
    img_ext = os.path.splitext(photo.filename)[1].lower() or ".jpg"
    temp_img_path = None
    temp_bin_path = None

    try:
        # 1. Save uploads to temp files
        with tempfile.NamedTemporaryFile(delete=False, suffix=img_ext) as tmp_img:
            shutil.copyfileobj(photo.file, tmp_img)
            temp_img_path = tmp_img.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp_bin:
            shutil.copyfileobj(bin.file, tmp_bin)
            temp_bin_path = tmp_bin.name

        # 2. Detect keypoints
        model = request.app.state.model
        error, coords_data = getFourPOI(temp_img_path, model)
        if error or not coords_data:
            print("[av] Failed to detect required keypoints.")
            return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

        # 3. Load the depth map
        depth_map = np.frombuffer(open(temp_bin_path, "rb").read(), dtype=np.float32)
        depth_map = depth_map.reshape((depthY, depthX))

        # 4. Scale the intrinsics
        K = json.loads(intrinsics)
        fx, fy = K[0][0], K[1][1]
        cx, cy = K[0][2], K[1][2]

        fx_s = fx * (depthX / referenceWidth)
        fy_s = fy * (depthY / referenceHeight)
        cx_s = cx * (depthX / referenceWidth)
        cy_s = cy * (depthY / referenceHeight)

        # Helper: Look up a valid depth value
        def find_valid_depth(depth_map, u, v, max_radius=10):
            H, W = depth_map.shape
            for r in range(max_radius + 1):
                for dv in range(-r, r + 1):
                    for du in range(-r, r + 1):
                        if abs(du) != r and abs(dv) != r:
                            continue
                        nu, nv = u + du, v + dv
                        if 0 <= nu < W and 0 <= nv < H:
                            z = depth_map[nv, nu]
                            if np.isfinite(z) and 0.0 < z < 100.0:
                                return float(z)
            return None

        # 5, 6 & 7. Map keypoints, find valid depth, and back-project to 3D
        pts = {}
        target_keys = ["point_2", "point_10", "midpoint_2_10", "point_3"]
        for key in target_keys:
            # Map normalised keypoints to depth-map pixel coordinates
            u = int(round(coords_data[key]["x"] * depthX))
            v = int(round(coords_data[key]["y"] * depthY))
            
            # Clamp to valid range
            u = max(0, min(depthX - 1, u))
            v = max(0, min(depthY - 1, v))

            # Look up valid Z
            Z = find_valid_depth(depth_map, u, v)
            if Z is None:
                print(f"[av] No valid depth found for {key} within search radius.")
                return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

            # Back-project to 3D
            X = (u - cx_s) * Z / fx_s
            Y = (v - cy_s) * Z / fy_s
            pts[key] = np.array([X, Y, Z])

        # 8. Calculate Euclidean distances
        distPoint2To10  = float(np.linalg.norm(pts["point_2"]       - pts["point_10"]))
        distMidpointTo3 = float(np.linalg.norm(pts["midpoint_2_10"] - pts["point_3"]))

        # 9. Predict weight (metric Schaeffer's formula)
        length_cm = distPoint2To10  * 100
        radius_cm = distMidpointTo3 * 100
        girth_cm  = radius_cm * 2 * math.pi
        weight_kg = (length_cm * girth_cm ** 2) / 10400

        # 10. Save a debug image
        try:
            with Image.open(temp_img_path) as debug_img:
                photo_w, photo_h = debug_img.size
                named_pixel_coords = {
                    label: (coords_data[label]["x"] * photo_w, coords_data[label]["y"] * photo_h)
                    for label in target_keys
                }
                save_debug_image(
                    temp_img_path,
                    named_pixel_coords,
                    endpoint_name="av",
                    original_filename=photo.filename or "upload",
                    draw_lines=[("point_2", "point_10"), ("midpoint_2_10", "point_3")],
                )
        except Exception as e:
            print(f"[av] Failed to save debug image: {e}")

        print(f"[av] Done. Predicted Weight: {weight_kg:.2f} kg\n")

        # 11. Return the response
        return {
            "success":         True,
            "predictedWeight": round(float(weight_kg), 2),
            "distPoint2To10":  round(float(distPoint2To10), 4),
            "distMidpointTo3": round(float(distMidpointTo3), 4),
        }

    except Exception as e:
        print(f"[av] Unhandled exception: {e}")
        return {
            "success": False, 
            "predictedWeight": 0.0, 
            "distPoint2To10": 0.0, 
            "distMidpointTo3": 0.0
        }

    finally:
        # Error handling and cleanup
        for path_var in ("temp_img_path", "temp_bin_path"):
            p = locals().get(path_var)
            if p and os.path.exists(p):
                try:
                    os.remove(p)
                except Exception as e:
                    print(f"[av] Failed to remove temp file {p}: {e}")