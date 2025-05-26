# server.py
from flask import Flask, request, jsonify
import cv2, numpy as np
from ultralytics import YOLO
import os
import time
import random

app = Flask(__name__)

# Model yolları
TRUCK_MODEL_PATH = 'models/truck v2.pt'
PLATE_MODEL_PATH = 'models/number plate detection model_- 21 may 2025 11_55.pt'
PLATE_OCR_MODEL_PATH = 'models/palaka_okuma.pt'

# YOLO modellerini yükle
truck_model = YOLO(TRUCK_MODEL_PATH)
plate_model = YOLO(PLATE_MODEL_PATH)
plate_ocr_model = YOLO(PLATE_OCR_MODEL_PATH)

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'ok'}), 200

@app.route("/detect", methods=["POST"])
def detect():
    # 1) Görseli oku
    file = request.files.get("image")
    if not file:
        return jsonify({"error":"no image"}), 400

    data = np.frombuffer(file.read(), np.uint8)
    img  = cv2.imdecode(data, cv2.IMREAD_COLOR)

    # Görseli kaydet
    os.makedirs("detected_images", exist_ok=True)
    ts = int(time.time() * 1000)
    rnd = random.randint(1000, 9999)
    img_filename = f"detected_images/input_{ts}_{rnd}.jpg"
    cv2.imwrite(img_filename, img)

    # 2) Kamyon tespiti (app.py'deki detect_trucks fonksiyonu gibi)
    results = truck_model(img)
    trucks = []
    other_vehicles = []
    for box in results[0].boxes:
        cls = int(box.cls[0])
        label = results[0].names[cls]
        print(f"Detected label: {label}, cls: {cls}")  # Debug için eklendi
        if label == 'truck':
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            trucks.append([x1, y1, x2, y2])
        elif label.strip().lower() == 'other-vehicles':
            print("Other vehicle detected (label 0).---------------------------------------")
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            other_vehicles.append([x1, y1, x2, y2])

    if not trucks:
        if other_vehicles:
            return jsonify({"status": "other-vehicle", "warning": "Other vehicle detected (label 1)."})
        return jsonify({"status":"none"})

    # 3) Kamyon bulundu: ilkini al
    x1, y1, x2, y2 = trucks[0]
    crop = img[y1:y2, x1:x2]

    # 4) Plaka tespiti (app.py'deki detect_plate fonksiyonu gibi)
    plate_results = plate_model(crop, conf=0.5)
    plates = []
    for box in plate_results[0].boxes:
        px1, py1, px2, py2 = map(int, box.xyxy[0])
        plates.append([px1, py1, px2, py2])

    if not plates:
        return jsonify({"status":"truck","plate":None})

    # 5) Plaka bulundu: ilkini al
    px1, py1, px2, py2 = plates[0]
    plate_roi = crop[py1:py2, px1:px2]

    # Plaka kırpıntısını kaydet
    os.makedirs("detected_plates", exist_ok=True)
    plate_filename = f"detected_plates/plate_{ts}_{rnd}.jpg"
    cv2.imwrite(plate_filename, plate_roi)

    # 6) YOLO ile OCR (app.py'deki read_plate fonksiyonu gibi)
    gray_plate = cv2.cvtColor(plate_roi, cv2.COLOR_BGR2GRAY)
    if len(gray_plate.shape) == 2:
        gray_plate = cv2.cvtColor(gray_plate, cv2.COLOR_GRAY2BGR)
    ocr_results = plate_ocr_model(gray_plate, conf=0.5, iou=0.5, agnostic_nms=True)
    chars = []
    for box in ocr_results[0].boxes:
        cx1, _, cx2, _ = box.xyxy[0]
        cls = int(box.cls[0])
        label = ocr_results[0].names[cls]
        x_center = (cx1 + cx2) / 2
        chars.append((x_center, label))
    chars.sort(key=lambda x: x[0])
    labels = [c[1] for c in chars]
    plate_text = ""
    if len(labels) >= 7:
        part1 = ''.join(labels[:2])
        part2 = ''.join(labels[2:5])
        part3 = ''.join(labels[5:7])
        plate_text = f"{part1} {part2} {part3}"
        if not (part1.isdigit() and part2.isalpha() and part3.isdigit()):
            plate_text = ""
    else:
        plate_text = ""

    return jsonify({"status":"truck","plate":plate_text})

if __name__=="__main__":
    app.run(host="0.0.0.0", port=5000)
