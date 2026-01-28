# Flutter App – Operating Instructions (Patient / Caregiver / Doctor)

This app has 3 user roles.

---

## Patient Mode

### Purpose
The patient controls **session start/stop** and can respond to an active alert with **I’M OK**.

### Main screen actions

#### 1) Start a session
- Press **SESSION START**.
- If internet exists:
  - The backend is called immediately and the session starts.
- If there is **no internet**:
  - The UI shows: ** No Internet. Waiting to START...**
  - The app keeps retrying automatically (every ~2 seconds) until it succeeds.

#### 2) Stop a session 
- Press **SESSION STOP**.
- The stop flow is “safe”:
  1) The app first checks internet connectivity.
  2) If internet is back, it waits ~15 seconds to let the ESP upload final telemetry.
  3) Then it calls the backend to finalize the session.
- If there is **no internet**:
  - UI shows: **Offline. Waiting for internet to SAVE...**
  - The app retries automatically (every ~2 seconds).
- While start/stop is pending:
  - The app shows a warning: **DO NOT CLOSE THE APP until saved!**
  - This is critical, because closing the app can prevent the pending operation from completing.

#### 3) I’M OK (only when an alert is active)
- If the backend marks an active alert, the patient screen shows:
  - **“Alert Active! Are you OK?”**
  - A big button: **I’M OK**
- Pressing **I’M OK** sends an “imOk” action to the backend so caregivers can see the patient confirmed they are safe.

---

## Caregiver Mode

### Purpose
The caregiver monitors:
1) **Disconnection / no data** from the patient device
2) **Alerts** (fall / long immobility) and can mark them handled

### Disconnection warning
The caregiver screen continuously shows alerts.

- If the patient device hasn’t updated for a while:
  - “ALERT: PATIENT DISCONNECTED / NO INTERNET”
  - A pop-up **CONNECTION LOST**
This warning triggers only once per disconnect event (to avoid popping up repeatedly).

### Alerts list (last 24 hours)
The caregiver sees alerts filtered to the last 24 hours, sorted newest first.
For each alert:
- If not handled: a button **MARK AS HANDLED**
- If handled:
  - Shows who handled it:
    - **THE PATIENT SENT OK** 
    - **HANDLED BY CAREGIVER*
    
- For `long_immobility` alerts, the UI also shows the duration (from payload) if provided.

---

## Doctor Mode

### Purpose
Doctors can view:
1) **Current session live metrics**
2) **Daily sessions history** and session details

### Doctor main menu
Two buttons:
- **CURRENT**
- **DAILY SESSIONS**

### 1) CURRENT 
It displays:
- Whether a session is active
- Live values:
  - steps
  - stairsCount
  - fallsCount

### 2) DAILY SESSIONS 
This page lets the doctor select a date using a calendar picker and then shows:

#### Daily summary card

Shows totals for the selected day:
- Steps
- Stairs
- Falls
- Alerts 

#### Sessions list
Tapping a session opens a **session details** screen.

