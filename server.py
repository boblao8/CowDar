
from scipy.spatial import cKDTree
from scipy.sparse import lil_matrix
from scipy.sparse.csgraph import dijkstra
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

def load_ply_points_numpy(ply_path: str) -> np.ndarray:
    """Reads XYZ coordinates from an ASCII PLY file without using Open3D."""
    points = []
    with open(ply_path, "r") as f:
        lines = f.readlines()
        
    try:
        header_end = lines.index("end_header\n") + 1
    except ValueError:
        header_end = 0

    for line in lines[header_end:]:
        parts = line.strip().split()
        if len(parts) >= 3:
            try:
                points.append([float(parts[0]), float(parts[1]), float(parts[2])])
            except ValueError:
                continue
                
    return np.array(points)

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
                    
def load_depth_map(depth_bin_path: str, depth_h: int, depth_w: int) -> np.ndarray:
    expected_bytes = depth_h * depth_w * 4
    actual_bytes   = os.path.getsize(depth_bin_path)

    print(f"[DepthMap] Expected {expected_bytes}B ({depth_w}x{depth_h} x 4), got {actual_bytes}B")

    if actual_bytes == expected_bytes:
        depth_map = np.fromfile(depth_bin_path, dtype=np.float32).reshape((depth_h, depth_w))
        print(f"[DepthMap] Loaded {depth_map.shape} (no padding)")

    elif actual_bytes > expected_bytes and actual_bytes % depth_h == 0:
        stride_bytes  = actual_bytes // depth_h
        stride_floats = stride_bytes // 4
        data      = np.fromfile(depth_bin_path, dtype=np.float32).reshape((depth_h, stride_floats))
        depth_map = data[:, :depth_w]
        print(f"[DepthMap] Stride {stride_bytes}B/row -> sliced to {depth_map.shape}")

    else:
        raise ValueError(
            f"Depth file size mismatch: expected {expected_bytes}B for "
            f"{depth_w}x{depth_h} float32 map, got {actual_bytes}B."
        )

    valid_mask = (depth_map > 0.0) & np.isfinite(depth_map)
    valid_pct  = valid_mask.mean() * 100.0
    print(
        f"[DepthMap] min={depth_map[valid_mask].min():.3f}m  "
        f"max={depth_map[valid_mask].max():.3f}m  "
        f"mean={depth_map[valid_mask].mean():.3f}m  "
        f"valid={valid_pct:.1f}%"
    )

    return depth_map


def parse_info_file(info_path: str) -> tuple[float, float]:
    try:
        with open(info_path, "r") as f:
            info = json.load(f)
    except Exception as e:
        print(f"[InfoFile] Could not parse: {e} -- using default multipliers")
        return (1.0, 1.0)

    breed = info.get("breed", "Other")
    sex   = info.get("sex", "Other")

    breed_mult = BREED_WEIGHT_MULTIPLIERS.get(breed, 1.0)
    sex_mult   = SEX_WEIGHT_MULTIPLIERS.get(sex, 1.0)

    print(f"[InfoFile] breed={breed!r} x{breed_mult}  sex={sex!r} x{sex_mult}")
    return (breed_mult, sex_mult)


def calculate_3d_coordinates(
    norm_coords: dict,
    depth_map: np.ndarray,
    depth_h: int,
    depth_w: int,
    rgb_w: int,
    rgb_h: int,
    fx: float,
    fy: float,
    cx: float,
    cy: float,
    search_radius: int = 5,
) -> dict:
    results_3d = {}

    for point_name, coords in norm_coords.items():
        u_norm, v_norm = coords["x"], coords["y"]

        dx = min(int(u_norm * depth_w), depth_w - 1)
        dy = min(int(v_norm * depth_h), depth_h - 1)
        z  = float(depth_map[dy, dx])

        used_fallback = False
        if z <= 0.0 or not math.isfinite(z):
            used_fallback = True
            y0 = max(0, dy - search_radius)
            y1 = min(depth_h - 1, dy + search_radius)
            x0 = max(0, dx - search_radius)
            x1 = min(depth_w - 1, dx + search_radius)
            patch = depth_map[y0:y1 + 1, x0:x1 + 1]
            valid = patch[(patch > 0.0) & np.isfinite(patch)]
            if len(valid) > 0:
                z = float(np.median(valid))
            else:
                print(
                    f"[3D] {point_name}: depth invalid after {search_radius}px search "
                    f"(norm=({u_norm:.3f},{v_norm:.3f}) depth_px=({dx},{dy}))"
                )
                results_3d[point_name] = {
                    "valid": False,
                    "error": f"Invalid depth after {search_radius}px search.",
                }
                continue

        u_pixel = u_norm * rgb_w
        v_pixel = v_norm * rgb_h
        x_3d = (u_pixel - cx) * z / fx
        y_3d = (v_pixel - cy) * z / fy

        print(
            f"[3D] {point_name}: norm=({u_norm:.4f},{v_norm:.4f}) "
            f"depth_px=({dx},{dy}) z={z:.4f}m{' [fallback]' if used_fallback else ''} "
            f"-> X={x_3d:.4f} Y={y_3d:.4f} Z={z:.4f}"
        )

        results_3d[point_name] = {
            "valid": True,
            "X": round(x_3d, 4),
            "Y": round(y_3d, 4),
            "Z": round(z,    4),
        }

    return results_3d


def calc_distance(p1: dict, p2: dict) -> float | str:
    if not p1 or not p2 or not p1.get("valid") or not p2.get("valid"):
        return "Invalid (Missing Depth for one or both points)"
    return round(
        math.sqrt(
            (p2["X"] - p1["X"]) ** 2 +
            (p2["Y"] - p1["Y"]) ** 2 +
            (p2["Z"] - p1["Z"]) ** 2
        ),
        4,
    )
    
@app.post("/api/3d-distances")
async def api_get_3d_distances(
    request: Request,
    image_file: UploadFile = File(...),
    depth_file: UploadFile = File(...),
    meta_file:  UploadFile = File(...),
    info_file:  UploadFile = File(None),
):
    img_temp = depth_temp = meta_temp = info_temp = ""

    print(f"\n[3D-Distances] Request received")
    print(f"  image_file : {image_file.filename} ({image_file.content_type})")
    print(f"  depth_file : {depth_file.filename}")
    print(f"  meta_file  : {meta_file.filename}")
    print(f"  info_file  : {info_file.filename if info_file else 'not provided'}")

    try:
        ext = os.path.splitext(image_file.filename)[1].lower() or ".jpg"

        with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
            shutil.copyfileobj(image_file.file, tmp)
            img_temp = tmp.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
            shutil.copyfileobj(depth_file.file, tmp)
            depth_temp = tmp.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            shutil.copyfileobj(meta_file.file, tmp)
            meta_temp = tmp.name

        if info_file:
            with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
                shutil.copyfileobj(info_file.file, tmp)
                info_temp = tmp.name

        print(
            f"[3D-Distances] Saved: img={img_temp} ({os.path.getsize(img_temp)}B)  "
            f"depth={depth_temp} ({os.path.getsize(depth_temp)}B)  "
            f"meta={meta_temp} ({os.path.getsize(meta_temp)}B)"
        )

        try:
            with open(meta_temp, "r") as f:
                meta = json.load(f)

            depth_w = int(meta["depthWidth"])
            depth_h = int(meta["depthHeight"])
            rgb_w   = int(meta["imageWidth"])
            rgb_h   = int(meta["imageHeight"])
            intrinsics = meta["intrinsics"]

            # Intrinsics stored column-major from Swift simd_float3x3:
            # [fx, 0, 0, 0, fy, 0, cx, cy, 1]
            fx = float(intrinsics[0])
            fy = float(intrinsics[4])
            cx = float(intrinsics[6])
            cy = float(intrinsics[7])

            print(f"[Metadata] depth={depth_w}x{depth_h}  rgb={rgb_w}x{rgb_h}")
            print(f"[Metadata] fx={fx:.2f}  fy={fy:.2f}  cx={cx:.2f}  cy={cy:.2f}")

        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to parse metadata: {e}")

        breed_mult, sex_mult = (1.0, 1.0)
        if info_temp and os.path.exists(info_temp):
            breed_mult, sex_mult = parse_info_file(info_temp)
        else:
            print("[InfoFile] Not provided -- using default multipliers (1.0 x 1.0)")

        model = request.app.state.model
        error, norm_coords = getFourPOI(img_temp, model)

        if error:
            raise HTTPException(status_code=500, detail="Failed to open or run inference on image.")

        if not norm_coords:
            print("[3D-Distances] YOLO could not detect required keypoints -- returning zero weight")
            return {
                "success":        False,
                "predictedWeight": 0,
                "distPoint2To10": -1,
                "distMidpointTo3": -1,
                "error": "YOLO could not detect cattle keypoints in the image.",
            }

        with Image.open(img_temp) as pil_img:
            w, h = pil_img.size
            named_px = {k: (v["x"] * w, v["y"] * h) for k, v in norm_coords.items()}
        save_debug_image(
            img_temp, named_px, "3d-distances", image_file.filename or "upload.jpg",
            draw_lines=[("point_2", "point_10"), ("midpoint_2_10", "point_3")],
        )

        try:
            depth_map = load_depth_map(depth_temp, depth_h, depth_w)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to load depth map: {e}")

        coords_3d = calculate_3d_coordinates(
            norm_coords, depth_map, depth_h, depth_w, rgb_w, rgb_h, fx, fy, cx, cy,
        )

        dist_2_10  = calc_distance(coords_3d.get("point_2"),       coords_3d.get("point_10"))
        dist_mid_3 = calc_distance(coords_3d.get("midpoint_2_10"), coords_3d.get("point_3"))

        print(f"[Weight] dist_2_10  (body length) = {dist_2_10}")
        print(f"[Weight] dist_mid_3 (body radius) = {dist_mid_3}")

        predicted_weight_kg = 0.0

        if isinstance(dist_2_10, float) and isinstance(dist_mid_3, float):
                # 1. Map physical lines to correct variables
                body_length_m = dist_mid_3    # Horizontal line is length
                chest_diameter_m = dist_2_10  # Vertical line is diameter
                
                # 2. Calculate Girth (Circumference = pi * diameter)
                girth_m = chest_diameter_m * math.pi 

                # 3. Convert to inches for Schaeffer's formula
                length_in = body_length_m * 39.3701
                girth_in  = girth_m * 39.3701

                print(f'[Weight] length_in={length_in:.2f}"  girth_in={girth_in:.2f}"')

                # 4. Schaeffer's Formula
                weight_lbs = (length_in * (girth_in ** 2)) / 300.0
                weight_kg  = weight_lbs * 0.453592

                print(f"[Weight] Schaffer raw: {weight_lbs:.1f} lb = {weight_kg:.1f} kg")

                predicted_weight_kg = round(weight_kg * breed_mult * sex_mult, 1)
                print(f"[Weight] After multipliers (x{breed_mult} x{sex_mult}): {predicted_weight_kg} kg")
        else:
            print(f"[Weight] Cannot compute -- dist_2_10={dist_2_10!r}  dist_mid_3={dist_mid_3!r}")

        print("[3D-Distances] Done\n")

        return {
            "success":         True,
            "predictedWeight": predicted_weight_kg,
            "distPoint2To10":  dist_2_10  if isinstance(dist_2_10,  float) else -1,
            "distMidpointTo3": dist_mid_3 if isinstance(dist_mid_3, float) else -1,
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"[3D-Distances] Unhandled exception: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        for path in [img_temp, depth_temp, meta_temp, info_temp]:
            if path and os.path.exists(path):
                try:
                    os.remove(path)
                except Exception as e:
                    print(f"Failed to delete temp file {path}: {e}")
                    

from scipy.spatial import cKDTree
from scipy.sparse import lil_matrix
from scipy.sparse.csgraph import dijkstra

def get_surface_path(start_idx, end_idx, points, graph):
    dist_matrix, predecessors = dijkstra(
        csgraph=graph,
        directed=False,
        indices=start_idx,
        return_predecessors=True
    )
    total_dist = dist_matrix[end_idx]
    if np.isinf(total_dist):
        print(f"No path found between {start_idx} and {end_idx}")
        return None

    path_indices = []
    current = end_idx
    while current != start_idx:
        path_indices.append(current)
        current = predecessors[current]
        if current == -9999:
            print("Path reconstruction failed.")
            return None
    path_indices.append(start_idx)
    path_indices = path_indices[::-1]

    path_points = points[path_indices]
    segment_distances = np.linalg.norm(path_points[1:] - path_points[:-1], axis=1)
    return float(np.sum(segment_distances))


@app.post("/api/reef/dist")
async def get_reef_dist(
    request: Request,
    image: UploadFile = File(...),
    ply:   UploadFile = File(...),
):
    print(f"\n[reef/dist] Request received (Curved Surface Distance Mode)")
    img_ext = os.path.splitext(image.filename)[1].lower() or ".jpg"

    try:
        # 1. Save uploads to temporary files
        with tempfile.NamedTemporaryFile(delete=False, suffix=img_ext) as tmp_img:
            shutil.copyfileobj(image.file, tmp_img)
            temp_img_path = tmp_img.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=".ply") as tmp_ply:
            shutil.copyfileobj(ply.file, tmp_ply)
            temp_ply_path = tmp_ply.name

        # 2. Extract keypoints via YOLO
        model = request.app.state.model
        error, coords_data = getFourPOI(temp_img_path, model)

        if error or not coords_data:
            print("[reef/dist] Failed to detect required keypoints.")
            return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

        # 3. Load PLY
        try:
            points_3d = load_ply_points_numpy(temp_ply_path)
            if points_3d.shape[0] == 0:
                print("[reef/dist] PLY file contains no points.")
                return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}
        except Exception as e:
            print(f"[reef/dist] Failed to load point cloud: {e}")
            return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

        # ---------------------------------------------------------
        # 3.5 APPLY RELATIVE CAMERA TRANSFORMATIONS (The Fix)
        # ---------------------------------------------------------
        theta = -np.pi / 2
        Rz = np.array([
            [np.cos(theta), -np.sin(theta), 0],
            [np.sin(theta),  np.cos(theta), 0],
            [0,              0,             1]
        ])
        
        # Apply rotation around Z
        points_3d = points_3d @ Rz.T
        
        # Invert Z axis and mirror X axis
        points_3d[:, 2] *= -1
        points_3d[:, 0] *= -1

        # 4. Project LiDAR → Image 
        image_width, image_height = 1920, 1440
        fx, fy = 1450, 1450
        cx, cy = image_width / 2, image_height / 2

        xs = points_3d[:, 0]
        ys = -points_3d[:, 1]          # flip vertical axis
        zs = -points_3d[:, 2].copy()   # flip depth sign
        zs[np.abs(zs) < 1e-6] = 1e-6

        u = fx * (xs / zs) + cx
        v = fy * (ys / zs) + cy
        projected_norm = np.column_stack((u / image_width, v / image_height))

        # 5. Match YOLO 2D keypoints to 3D points
        target_keys = ["point_2", "point_10", "midpoint_2_10", "point_3"]
        matched_idx = {}

        for key in target_keys:
            target_pt = np.array([coords_data[key]["x"], coords_data[key]["y"]])
            dists     = np.linalg.norm(projected_norm - target_pt, axis=1)
            matched_idx[key] = int(np.argmin(dists))

        # 6. Build KNN graph for surface path
        print("[reef/dist] Building KNN graph...")
        k = 12
        tree = cKDTree(points_3d)
        dists_knn, nbrs_knn = tree.query(points_3d, k=k + 1)

        n = len(points_3d)
        graph = lil_matrix((n, n), dtype=np.float64)
        for i in range(n):
            for j_idx in range(1, k + 1):
                j = nbrs_knn[i, j_idx]
                d = dists_knn[i, j_idx]
                graph[i, j] = d
                graph[j, i] = d

        # 7. Compute curved surface distances via Dijkstra
        print("[reef/dist] Computing surface paths...")
        curved_d_2_10  = get_surface_path(matched_idx["point_2"],       matched_idx["point_10"], points_3d, graph)
        curved_d_mid_3 = get_surface_path(matched_idx["midpoint_2_10"], matched_idx["point_3"],  points_3d, graph)

        if curved_d_2_10 is None or curved_d_mid_3 is None:
            print("[reef/dist] Surface path computation failed.")
            return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

        # ---------------------------------------------------------
        # 8. Predict weight using correct curved formula (The Fix)
        # ---------------------------------------------------------
        weight = 1.5 * ((curved_d_mid_3 * 100) * (curved_d_2_10 * 100 * 3.14159) ** 2) / 10840

        # 9. Save Debug Output
        try:
            with Image.open(temp_img_path) as debug_img:
                draw = ImageDraw.Draw(debug_img)
                w, h = debug_img.size
                px_2   = (int(coords_data["point_2"]["x"]       * w), int(coords_data["point_2"]["y"]       * h))
                px_10  = (int(coords_data["point_10"]["x"]      * w), int(coords_data["point_10"]["y"]      * h))
                px_mid = (int(coords_data["midpoint_2_10"]["x"] * w), int(coords_data["midpoint_2_10"]["y"] * h))
                px_3   = (int(coords_data["point_3"]["x"]       * w), int(coords_data["point_3"]["y"]       * h))

                draw.line([px_2, px_10],  fill="red",  width=8)
                draw.line([px_mid, px_3], fill="blue", width=8)
                for px in [px_2, px_10, px_mid, px_3]:
                    draw.ellipse((px[0] - 10, px[1] - 10, px[0] + 10, px[1] + 10), fill="yellow")

                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                debug_img.save(os.path.join(DEBUG_IMAGE_DIR, f"reef_dist_weight_{timestamp}.jpg"))
        except Exception as e:
            print(f"[reef/dist] Failed to save debug image: {e}")

        return {
            "success":         True,
            "predictedWeight": float(round(weight, 2)),
            "distPoint2To10":  float(round(curved_d_2_10,  4)),
            "distMidpointTo3": float(round(curved_d_mid_3, 4)),
        }

    except Exception as e:
        print(f"[reef/dist] Unhandled exception: {e}")
        return {"success": False, "predictedWeight": 0, "distPoint2To10": 0, "distMidpointTo3": 0}

    finally:
        if "temp_img_path" in locals() and os.path.exists(temp_img_path):
            os.remove(temp_img_path)
        if "temp_ply_path" in locals() and os.path.exists(temp_ply_path):
            os.remove(temp_ply_path)