# Basic Operating Instructions

## What you need
- **ESP32 IMU node** (with MPU9250) — worn on ankle
- **ESP32 Radar node** (with RD-03D radar) — placed in room
- **Wi-Fi network** (for cloud mode)
- **Backend deployed** (Firebase Cloud Functions)
- **Flutter app installed** (Patient / Caregiver / Doctor)

---

## 1) Power-on and placement
1. Place **Radar ESP32** in the room facing the patient area.
2. Attach **IMU ESP32** securely to the ankle (consistent orientation each time).
3. Power both ESP32 boards (USB or battery).

---

## 2) Verify devices are working (Serial Monitor)
### IMU ESP32
- Should print Wi-Fi connection status.
- Should periodically print telemetry status (steps/stairs/motion) and/or “sent to cloud”.
- Should print ESP-NOW send status (IMU → Radar).

### Radar ESP32
- Should print Wi-Fi connection status.
- Should print radar target parsing / tracking updates.
- Should show that IMU packets are received (ESP-NOW) or at least update IMU “freshness”.

If either device shows no progress:
- check power, pins, baud rate, and Wi-Fi credentials.

---

## 3) Start a monitoring session (Patient role)
1. Open the app → choose **Patient** → select/enter `patientId` (example: `p1`).
2. Press **SESSION START**.
3. Keep the app open until it shows **Session Started**.

What should happen:
- Backend session becomes active.
- Telemetry starts updating in Firestore.

---

## 4) Monitoring views (Caregiver / Doctor)
### Caregiver role
- Open app → **Caregiver** → same `patientId`.
- Watch:
  - Disconnection banner (if device stops sending updates)
  - Alerts list (fall / long immobility)
  - Use **MARK AS HANDLED** to resolve alerts.

### Doctor role
- Open app → **Doctor** → same `patientId`.
- Use:
  - **CURRENT** to view live session metrics
  - **DAILY SESSIONS** to view history and session details

---

## 5) Trigger and verify alerts (demo)
### Fall alert
- Perform a controlled test movement that triggers IMU fall detection.
- Expected:
  - Backend receives `type="fall_alert"`
  - Alert document created
  - Caregiver receives push notification
  - Patient can press **I’M OK** (if shown)

### Long immobility alert (radar)
- Keep the tracked target stable with no movement longer than `IMMOBILITY_TIMEOUT`.
- Expected:
  - Backend receives `type="long_immobility"`
  - Alert document created
  - Caregiver receives push notification

---

## 6) Stop the session cleanly (Patient role)
1. Press **SESSION STOP**.
2. If the UI warns not to close the app: **do not close it** until the stop is saved.
3. Expected:
  - Backend finalizes the session
  - Daily/session totals update

---

## Common troubleshooting
- **No Wi-Fi**: verify SSID/password, router range, and that secrets are correct.
- **No radar targets**: check UART wiring and RX/TX pins.
- **ESP-NOW not working**: verify `RADAR_MAC` matches the radar ESP32 MAC and both boards are compatible on channel.
- **Backend not updating**: verify `CLOUD_URL` matches the deployed function endpoint.

---

## Files required in Documentation folder
- `Documentation/connection_diagram.png` (or `.pdf`)
- `Documentation/basic_operating_instructions.md` (this file)
- `Documentation/app_operating_instructions.md` (role-based app guide)
- `Documentation/poster.pdf` (or `.png`)