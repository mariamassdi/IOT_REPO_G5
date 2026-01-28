# Patient Monitoring Project by: Mariam Assdi, Ranin Haj Yahya, Gharam Kharanbeh

In this project we built a patient mobility monitoring system that monitors daily activity and safety using two ESP32 devices (IMU + radar) and a smartphone app. The system tracks steps and stair steps, detects potential falls, detects long immobility, and notifies caregivers through push notifications. The app supports three roles: patient, caregiver, and doctor.

## Our Project in details

First, the IMU ESP32 is worn on the ankle and samples the MPU9250 sensors continuously, while the radar ESP32 is placed in the room and tracks the patient using RD-03D radar frames. Both devices send telemetry and alert events to the backend (Firebase Cloud Functions), which stores data in Firestore and triggers push notifications.

1. **Sessions (Patient role)**  
   The patient starts a monitoring session from the app (SESSION START) and stops it (SESSION STOP). A session controls when telemetry is recorded and when totals are finalized.

2. **Activity tracking (IMU ESP32)**  
   The IMU samples acceleration/gyro continuously, maintains a moving average baseline for acceleration magnitude, and detects steps when the current magnitude crosses a threshold above the baseline (with debounce). For stairs, the IMU opens a short time window after a detected step and computes additional features (e.g., acceleration RMS and tilt range) to classify the step as stair-related.

3. **Fall detection (IMU ESP32)**  
   The IMU runs a rule-based state machine. A fall is suspected on strong impact and fast rotation, and is confirmed only if posture/tilt becomes abnormal and motion becomes still for a minimum duration. When confirmed, a fall alert is sent.

4. **Long immobility detection (Radar ESP32)**  
   The radar reads RD-03D target frames over UART, selects and maintains a single tracked target by scoring candidates and applying position/velocity gating. If the tracked target remains stable with no meaningful movement for longer than `IMMOBILITY_TIMEOUT`, a `long_immobility` alert is sent.

5. **Notifications and handling (Backend + App)**  
   The backend receives telemetry and alert events over HTTP, manages session state, stores updates in Firestore, and sends push notifications via Firebase Cloud Messaging. The caregiver can view alerts and mark them as handled, the patient can confirm “I’M OK” when an alert is active, and the doctor can view current live metrics and daily session history.

## Folder description

- **ESP32**: source code for the esp side (firmware).  
  - `IMU_RECIEVER.ino` (MPU9250 + steps/stairs/fall + ESP-NOW sender)  
  - `Radar-sender.ino` (RD-03D + tracking + immobility + ESP-NOW receiver)
- **Documentation**: wiring diagram + basic operating instructions.
- **Unit Tests**: tests for individual hardware components (input / output devices).
- **flutter_app**: dart code for our Flutter app +Firebase Cloud Functions.
- **Parameters**: contains description of configurable parameters.


## Arduino/ESP32 libraries used in this project

External:
- `MPU9250_WE` - version `0.4.8`
- `RD03D` - version `XXXX`

Built-in / ESP32 core libraries:
- `WiFi`
- `HTTPClient`
- `WiFiClientSecure`
- `esp_now`

## Connection diagram:	
[ ESP32 ]                 [ RD03D RADAR ]
+-----------+            +------------+
|           |            |            |
|           |            |            |
| VIN/5V ---|----------->| VCC        |
|           |            |            |
|           |            |            |
| GND   ----|----------->| GND        |
|           |            |            |
|           |            |            |
| GPIO 26 --|----------->| TX         |
|   (RX)    |            |            |
|           |            |            |
| GPIO 27 --|----------->| RX         |
|    (TX)   |            |            |
|           |            |            |
+-----------+            +------------+


[ ESP32 ]                 [ MPU9250 ]
+-----------+            +------------+
|           |            |            |
|           |            |            |
| 3.3V -----|----------->| VCC        |
|           |            |            |
|           |            |            |
| GND  -----|----------->| GND        |
|           |            |            |
|           |            |            |
| GPIO 21 --|----------->| SDA        |
|           |            |            |
|           |            |            |
| GPIO 22 --|----------->| SCL        |
|           |            |            |
|           |            |            |
+-----------+            +------------+


