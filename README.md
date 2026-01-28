# Patient Monitoring Project by: Mariam Assdi, Ranin Haj Yahya, Gharam Kharanbeh

## Details about the project
This project implements a **patient mobility monitoring system** using:
- **ESP32 IMU node (ankle)**: reads MPU9250, detects steps/stairs, detects falls, and sends telemetry/alerts to the cloud.
- **ESP32 Radar node (room)**: receives packets from the imu-ESP,reads RD-03D radar targets, tracks the patient, detects long immobility , and sends alerts to the cloud.
- **Firebase Cloud Functions **: receives telemetry and alert events over HTTP, manages sessions, stores data in Firestore, and sends push notifications via Firebase Cloud Messaging.

## Folder description
- **ESP32**: source code for the esp side.
  - `IMU_RECIEVER.ino` (MPU9250 + steps/stairs/fall + ESP-NOW sender)
  - `Radar-sender.ino` (RD-03D + tracking + immobility + ESP-NOW receiver)
- **Documentation**: wiring diagram + basic operating instructions.
- **Unit Tests**: tests for individual hardware components (input / output devices).
- **flutter_app**: dart code for our Flutter app.
- **Backend**: Firebase Cloud Functions (`index.js`) for ingestion + sessions + push notifications.
- **Parameters**: contains description of parameters and settings that can be modified the code.
---

## Arduino/ESP32 libraries used in this project
External:
- **MPU9250_WE** — used by IMU firmware
- **RD03D** — used by Radar firmware

Built-in / ESP32 core libraries:
- **WiFi**
- **HTTPClient** 
- **WiFiClientSecure** 
- **esp_now** (ESP32 core / ESP-NOW protocol)
--
## Hardware algorithm 

- **IMU ESP32:** samples MPU9250 acceleration/gyro continuously, builds a moving average for the acceleration magnitude, and detects **steps** when the current magnitude rises above that baseline by a threshold. For **stairs**, it opens a short time window after a step and computes features to classify the step as stair related. For **falls**, it runs a state machine: a fall is suspected on a strong impact and fast rotation, then confirmed only if the tilt is abnormal and motion becomes still for a minimum duration. 

- **Radar ESP32:** reads RD-03D target frames over UART, selects and maintains a single tracked target by scoring candidates and applying position/velocity gates. It determines movement based on the tracked target’s velocity and stability over time and if the movement matches the IMU. If the tracked target remains stable with no meaningful movement for longer than `IMMOBILITY_TIMEOUT` an alert is sent.

## Parameters (modifiable settings)
### IMU firmware (IMU_RECIEVER.ino)

#### Network / cloud
- `PATIENT_ID` (default `"p1"`)  
  Patient identifier embedded in each JSON payload so the backend updates the correct Firestore paths.
- `WIFI_SSID`, `WIFI_PASSWORD`  
  Wi-Fi credentials used by `WiFi.begin()` to connect the IMU ESP32 to the network.
- `CLOUD_URL`  
  The IMU posts JSON to this URL using Arduino `HTTPClient`.

#### ESP-NOW
- `RADAR_MAC[6]`  
  Destination ESP32 MAC address for ESP-NOW packets (the radar board).
- `ESPNOW_SEND_MS`   
  Interval between ESP-NOW status transmissions. 

#### Step / stair detection
- `threshold`  
  Step detection sensitivity: required gap between current acceleration magnitude (`amag`) and its moving-average baseline.  
- `bufferLength`  
  Window size for moving-average baseline.
- `debounceDelay` 
  Minimum time between step detections to prevent double counting after a step.
- `yThreshold` 
  Minimum absolute delta on the Y axis per sample used to stop noise from triggering steps.

#### Stair window + classification
- `STAIR_WIN_MS` 
  Accumulation window after a candidate step. 
- `STAIRS_ALIM_RMS_TH`  
  Minimum linear acceleration magnitude during stair window.
- `STAIRS_TILT_RANGE_TH`  
  Minimum tilt angle range during stair window. 
  
#### Fall detection
The fall logic is typically a combination of impact + rotation + stillness over time.

- `IMPACT_G`  
  Impact threshold (g units). 
- `ROT_DPS`  
  Rotation threshold (deg/sec). Used to require fast rotation.
- `TILT_DEG`  
  Tilt threshold (degrees) after suspected fall. Used to confirm unusual orientation.
- `STILL_W`  
  Gyro stillness threshold. Must be below this to consider “not moving.”
- `STILL_AL`  
  Linear acceleration stillness threshold. Must be below this to consider “settled.”

Timing parameters (ms):
- `STILL_TIME_MS`  
  Duration stillness must persist to confirm a fall.
- `SUSPECT_TIMEOUT_MS`  
  Maximum time allowed in SUSPECT before aborting back to NORMAL if confirmation conditions aren’t met.

---

### Radar firmware (Radar-sender.ino)

#### Network / cloud
- `PATIENT_ID`, `WIFI_SSID`, `WIFI_PASSWORD`, `CLOUD_URL`  
  Same roles as IMU: identify patient, connect to Wi-Fi, post telemetry/alerts to backend.
- `WIFI_RETRY_MS` 
  Minimum interval between reconnect attempts. Prevents tight reconnect loops and reduces power usage.

#### Radar hardware
- `RX_PIN` (default 26), `TX_PIN` (default 27)  
  UART pins connected to the RD-03D radar module.

#### IMU freshness / fusion logic
- `IMU_FRESH_MS`  
  Maximum age for last received IMU ESP-NOW packet. If exceeded, IMU state is treated as stale and radar relies more on its own motion cues.

#### Tracking tuning
These parameters control how aggressively you “stick” to one target vs switching.

- `GATE_DPOS_M`  
  Position gating in meters: maximum allowed jump from last track position for a candidate to be considered the same target.
- `GATE_DV`  
  Velocity gating: maximum allowed velocity difference to accept a candidate as the same target.
- `V_MOVE_TH`  
  Velocity magnitude threshold to mark radar target as moving.
- `FAST_V`  
  High-speed cutoff: penalizes targets moving too fast to be the intended patient target.
- `NEED_STABLE_TO_LOCK`  
  Number of consecutive frames required to declare a stable lock on a target.
- `MAX_LOST_FRAMES`  
  How many frames you can lose the target before dropping lock and restarting search.
- `MIN_Y_M`, `MAX_Y_M`  
  Valid distance band (meters). Rejects too near/too far detections.

#### Immobility alert
- `IMMOBILITY_TIMEOUT` 
  Time without movement before sending a long immobility alert. 
- Alert JSON type: `"long_immobility"`  
  Event type string sent to backend.
---

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


