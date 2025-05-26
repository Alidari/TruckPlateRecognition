# Mobile Truck Detection & Plate Recognition System

A comprehensive mobile application system that detects trucks and performs license plate recognition for automated gate control. The system consists of a Flutter mobile app, Flask AI server, and ESP32 hardware controller.

## Demo Video

[![Mobile Truck Detection Demo](https://img.youtube.com/vi/dypM37S279k/0.jpg)](https://www.youtube.com/watch?v=dypM37S279k)

**[Watch the Demo Video](https://www.youtube.com/watch?v=dypM37S279k)** - See the complete system in action!


## Project Overview

This system provides automated truck detection and access control through license plate recognition. When a truck arrives:

1. **Mobile App** captures images and sends them to the AI server
2. **Flask Server** processes images using YOLO models to detect trucks and read license plates
3. **Access Control** validates detected plates against registered vehicles
4. **Gate Control** sends commands to ESP32 to open/close the gate via LED simulation

## System Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flutter App   │───▶│   Flask Server  │    │     ESP32       │
│  (Mobile Client)│    │   (AI Backend)  │    │ (Gate Controller)│
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                       ▲
                                ▼                       │
                       ┌─────────────────┐              │
                       │   YOLO Models   │              │
                       │ • Truck Detection│              │
                       │ • Plate Detection│              │
                       │ • OCR Recognition│              │
                       └─────────────────┘              │
                                                        │
                       ┌─────────────────┐              │
                       │ Registered      │──────────────┘
                       │ Plates Database │
                       └─────────────────┘
```

## Project Structure

```
├── esp32/                          # ESP32 Arduino Code
│   └── sketch_may26a.ino          # Gate controller firmware
├── flask-server/                   # AI Backend Server
│   ├── server.py                  # Main Flask application
│   └── models/                    # YOLO AI Models
│       ├── truck v2.pt           # Truck detection model
│       ├── number plate detection model_- 21 may 2025 11_55.pt
│       └── palaka_okuma.pt       # OCR model for plate reading
└── mobile-flutter/                # Flutter Mobile Application
    └── truck_detection/
        ├── lib/
        │   ├── main.dart         # Main app logic and camera interface
        │   └── settings.dart     # Settings and plate management
        ├── android/              # Android platform files
        ├── ios/                  # iOS platform files
        ├── web/                  # Web platform files
        └── windows/              # Windows platform files
```

## Features

### Mobile Application
- **Real-time Camera Feed**: Live camera preview with truck detection
- **Plate Management**: Add/remove registered license plates via `settings.dart`
- **Security Interface**: Visual feedback for access control status
- **Gate Control**: Manual and automatic gate commands
- **Multi-platform**: Supports Android, iOS, Web, and Windows

### AI Server
- **Truck Detection**: Uses YOLO model to identify trucks vs other vehicles
- **License Plate Detection**: Locates plate areas within detected trucks
- **OCR Recognition**: Reads license plate characters using specialized model
- **Image Storage**: Saves detected images and plate crops for analysis

### ESP32 Controller
- **WiFi Communication**: Receives commands from mobile app
- **LED Control**: Simulates gate operation with timed LED activation
- **Auto-off Timer**: LED automatically turns off after 2 seconds

## Setup Instructions

### 1. Flask Server Setup

```bash
cd flask-server
pip install flask opencv-python ultralytics numpy
python server.py
```

The server runs on `http://0.0.0.0:5000` as configured in `server.py`.

### 2. ESP32 Setup

1. Install Arduino IDE and ESP32 board package
2. Open `sketch_may26a.ino`
3. Update WiFi credentials:
   ```cpp
   const char* ssid = "YOUR_WIFI_SSID";
   const char* password = "YOUR_WIFI_PASSWORD";
   ```
4. Upload to ESP32 and note the IP address

### 3. Flutter App Setup

```bash
cd mobile-flutter/truck_detection
flutter pub get
flutter run
```

Update server URLs in `settings.dart` and `main.dart` to match your Flask server and ESP32 IP addresses.

## Configuration

### Server URLs
Update these in the Flutter app:
- **Flask Server**: Update API endpoint in `main.dart`
- **ESP32 Gate URL**: Update `_gateUrl` in `settings.dart`

### Registered Plates
Use the settings screen in the mobile app to:
- Add new license plates to the allowed list
- Remove existing plates
- View all registered plates

## System Workflow

1. **Detection Phase**: Camera captures frames and sends to Flask server
2. **AI Processing**: Server uses YOLO models to detect trucks and read plates
3. **Verification**: Detected plate is checked against registered plates list
4. **Access Control**: 
   - ✅ **Approved**: Gate opens via ESP32 LED activation
   - ❌ **Denied**: Warning displayed for unauthorized vehicles
5. **Logging**: All detections and access attempts are logged

## 📱 API Endpoints

### Flask Server (`server.py`)
- `GET /health` - Health check endpoint
- `POST /detect` - Image analysis endpoint (accepts multipart/form-data)

### ESP32 (`sketch_may26a.ino`)
- `POST /data` - Gate control endpoint (accepts "ON"/"OFF" commands)

## AI Models

The system uses three YOLO models:
1. **Truck Detection** (`truck v2.pt`) - Distinguishes trucks from other vehicles
2. **Plate Detection** (`number plate detection model_- 21 may 2025 11_55.pt`) - Locates license plates
3. **OCR Recognition** (`palaka_okuma.pt`) - Reads plate characters

## Hardware Requirements

- **ESP32 Development Board**
- **LED** connected to GPIO 2
- **WiFi Network** for communication
- **Mobile Device** with camera for the Flutter app

## License

Copyright (C) 2025 com.example. All rights reserved.

## 🔍 Troubleshooting

- **Connection Issues**: Verify all devices are on the same WiFi network
- **Model Loading**: Ensure YOLO model files are in the correct paths
- **Plate Recognition**: Check lighting conditions and plate visibility
- **ESP32 Communication**: Verify ESP32 IP address and network connectivity