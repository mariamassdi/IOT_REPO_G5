#ifndef PARAMETERS_H
#define PARAMETERS_H

#include <Arduino.h> 
// ===================== הגדרות כלליות =====================
const char* PATIENT_ID = "p1";
const char* CLOUD_URL  = "https://receivedata-ddy3ss2dzq-uc.a.run.app";
const unsigned long WIFI_RETRY_MS = 30000;

// ===================== הגדרות רדאר (Receiver) =====================
#define RX_PIN 26
#define TX_PIN 27

const unsigned long IMU_FRESH_MS = 2000;
const float GATE_DPOS_M = 0.8f;
const float GATE_DV     = 0.7f;
const float V_MOVE_TH   = 0.12f;
const float FAST_V      = 0.85f;
const int NEED_STABLE_TO_LOCK = 6;
const int MAX_LOST_FRAMES     = 40;
const float MIN_Y_M = 0.3f;
const float MAX_Y_M = 4.0f;

const unsigned long IMMOBILITY_TIMEOUT = 30000;

// =====================  (IMU Sender) =====================
#define MPU9250_ADDR 0x68
const uint8_t RADAR_MAC_ADDR[6] = {0xCC, 0xDB, 0xA7, 0x5A, 0x7F, 0xC0}; // שונה השם למניעת התנגשות
const unsigned long ESPNOW_SEND_MS = 50;

const float STEP_THRESHOLD = 0.15;
const int BUFFER_LENGTH = 50;
const unsigned long DEBOUNCE_DELAY = 300;
const float Y_THRESHOLD = 0.15;

const unsigned long STAIR_WIN_MS = 350;
const float STAIRS_ALIM_RMS_TH   = 0.34f;
const float STAIRS_TILT_RANGE_TH = 1.3f;
const float STAIRS_DIR_RATIO = 1.25f;
const bool INVERT_Y = false;

const float IMPACT_G = 2.0f;
const float ROT_DPS = 250.0f;
const float TILT_DEG = 60.0f;
const float STILL_W = 120.0f;
const float STILL_AL = 0.2f;
const unsigned long STILL_TIME_MS = 1000;
const unsigned long SUSPECT_TIMEOUT_MS = 3000;
const unsigned long OK_TIMEOUT_MS = 30000;
const unsigned long IM_OK_HOLD_MS = 5000;

const float ALPHA_G = 0.9696970f;

#endif
