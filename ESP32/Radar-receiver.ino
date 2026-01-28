// RADAR ESP32 (Receiver) — IMU->RADAR via ESP-NOW


#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <esp_now.h>
#include <math.h>
#include "RD03D.h"
#include "parameters.h" 
#include "secrets.h"    
unsigned long lastWifiRetryMs = 0;

// ===================== Radar HW =====================
RD03D radar(RX_PIN, TX_PIN); // משתמש ב-RX_PIN, TX_PIN מתוך parameters.h

// ===================== IMU packet =====================
typedef struct __attribute__((packed)) {
  uint32_t seq;
  uint8_t  imuMoving;    
  uint8_t  activity;     
  float    wmag;
  float    alim;
  float    tiltDeg;
} ImuStatusPacket;

volatile ImuStatusPacket gImu = {};
volatile unsigned long lastImuRecvMs = 0;
portMUX_TYPE imuMux = portMUX_INITIALIZER_UNLOCKED;

static int prevBest = -999;
static bool prevLocked = false;

// ===================== Tracking structs =====================
struct TrackState {
  bool  locked = false;
  int   idx = -1;
  float x = 0, y = 0, v = 0;
  int   stableFrames = 0;
  int   lostFrames = 0;
};

struct Target {
  bool  valid = false;
  float x = 0, y = 0, v = 0;
};

TrackState patient;

// ===================== TUNING =====================

unsigned long lastMovementTime = 0;
bool longAlertSent = false;

// ===================== Helpers =====================
static inline float sqf(float a){ return a*a; }
static inline float dpos(float x1,float y1,float x2,float y2){ return sqrtf(sqf(x1-x2)+sqf(y1-y2)); }
static inline bool radarMoving(const Target& t){ return fabsf(t.v) > V_MOVE_TH; }

static void ensureWiFiConnected(unsigned long nowMs) {
  if (WiFi.status() == WL_CONNECTED) return;
  if (nowMs - lastWifiRetryMs < WIFI_RETRY_MS) return;
  lastWifiRetryMs = nowMs;
  Serial.println("[WIFI] Reconnect attempt...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

static bool postJsonToCloud(const String& json, unsigned long nowMs) {
  if (WiFi.status() != WL_CONNECTED) {
    if (nowMs - lastWifiRetryMs >= 2000) { 
      lastWifiRetryMs = nowMs;
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    }
    return false;
  }
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  http.begin(client, CLOUD_URL); 
  http.setTimeout(2500);
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(json);
  http.end();
  Serial.print("[CLOUD] POST code: "); Serial.println(code);
  return (code >= 200 && code < 300);
}

static String buildImmobilityJson(unsigned long immobilityMs) {
  String j = "{";
  j += "\"patientId\":\"" + String(PATIENT_ID) + "\","; 
  j += "\"type\":\"long_immobility\",";
  j += "\"source\":\"radar\",";
  j += "\"immobilityMs\":" + String((uint32_t)immobilityMs) + ",";
  j += "\"radarLocked\":true,"; 
  j += "\"imuMoving\":false";
  j += "}";
  return j;
}

void onImuRecv(const uint8_t*, const uint8_t* data, int len){
  if (len < (int)sizeof(ImuStatusPacket)) return;
  portENTER_CRITICAL(&imuMux);
  memcpy((void*)&gImu, data, sizeof(ImuStatusPacket));
  lastImuRecvMs = millis();
  portEXIT_CRITICAL(&imuMux);
}

void readTargets(Target out[3]){
  for(int i=0;i<3;i++) out[i] = Target{};
  for (uint8_t i=0; i<RD03D::MAX_TARGETS && i<3; i++){
    TargetData* t = radar.getTarget(i);
    if (!t || !t->isValid()) continue;
    float tx = t->x / 100.0f;
    float ty = t->y / 100.0f;
    float tv = t->speed / 100.0f;
    if (ty < MIN_Y_M || ty > MAX_Y_M) continue;
    out[i].valid = true;
    out[i].x = tx; out[i].y = ty; out[i].v = tv;
  }
}

float scoreTarget(const Target& t, const TrackState& st, bool haveImu, bool imuMovingNow, int imuActivity) {
  float s = 0.0f;
  if (st.locked){
    float dp = dpos(t.x, t.y, st.x, st.y);
    float dv = fabsf(t.v - st.v);
    if (dp < GATE_DPOS_M && dv < GATE_DV) {
      s += 12.0f; s -= 1.5f * dp; s -= 0.5f * dv;
    } else {
      s -= 6.0f * dp; s -= 2.0f * dv;
    }
    if (st.idx >= 0) s += 1.0f;
  } else {
    s += 0.5f; 
  }
  bool rMove = radarMoving(t);
  if (haveImu){
    if (imuMovingNow){
      if (rMove) s += 4.0f + 0.03f * imuActivity; else s -= 2.0f;
    } else {
      if (!rMove) s += 2.5f; else s -= 3.5f;
    }
  } else {
    if (fabsf(t.v) > FAST_V) s -= 2.0f;
  }
  if (fabsf(t.v) > FAST_V) s -= 5.0f;
  return s;
}

int pickBest(const Target t[3], const TrackState& st, bool haveImu, bool imuMovingNow, int imuActivity, float outScores[3]) {
  int best = -1;
  float bestS = -1e9f;
  for (int i=0;i<3;i++){
    outScores[i] = -1e9f;
    if (!t[i].valid) continue;
    float sc = scoreTarget(t[i], st, haveImu, imuMovingNow, imuActivity);
    if (st.locked && i == st.idx) sc += 1.5f; 
    outScores[i] = sc;
    if (sc > bestS){ bestS = sc; best = i; }
  }
  if (bestS < -5.0f) return -1;
  return best;
}

void updateTrack(TrackState& st, int bestIdx, const Target t[3]){
  if (bestIdx >= 0){
    if (st.idx == bestIdx) st.stableFrames++; else st.stableFrames = 1;
    st.idx = bestIdx; st.x = t[bestIdx].x; st.y = t[bestIdx].y; st.v = t[bestIdx].v;
    st.lostFrames = 0;
    if (!st.locked && st.stableFrames >= NEED_STABLE_TO_LOCK){
      st.locked = true; Serial.println("[TRACK] LOCKED");
    }
  } else {
    st.lostFrames++;
    if (st.lostFrames > MAX_LOST_FRAMES){
      st.locked = false; st.idx = -1; st.stableFrames = 0;
    }
  }
}

// ===================== SETUP =====================
void setup(){
  Serial.begin(115200);
  radar.initialize(RD03D::RD03DMode::MULTI_TARGET);
  WiFi.mode(WIFI_AP_STA);
  WiFi.setSleep(false);              
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  if (esp_now_init() != ESP_OK) {
    Serial.println("[ESP-NOW] init failed");
    return;
  }
  esp_now_register_recv_cb(onImuRecv);
  Serial.print("STA MAC: "); Serial.println(WiFi.macAddress()); 
  lastMovementTime = millis();
  Serial.println(WiFi.channel());

}

// ===================== LOOP =====================
void loop(){
  radar.tasks();
  unsigned long now = millis();

  ensureWiFiConnected(now);

  ImuStatusPacket imuSnap;
  unsigned long imuLast;
  
  portENTER_CRITICAL(&imuMux);
  memcpy(&imuSnap, (const void*)&gImu, sizeof(ImuStatusPacket));
  imuLast = lastImuRecvMs;
  portEXIT_CRITICAL(&imuMux);

  bool haveImu = (now - imuLast) < IMU_FRESH_MS;
  bool imuMovingNow = haveImu ? ((imuSnap.imuMoving != 0) || (imuSnap.activity > 5)) : false;
  int  imuActivity  = haveImu ? (int)imuSnap.activity : 0;

  Target tar[3];
  readTargets(tar);

  float scores[3];
  int best = pickBest(tar, patient, haveImu, imuMovingNow, imuActivity, scores);
  updateTrack(patient, best, tar);

  bool radarSaysMoving = (patient.locked && fabsf(patient.v) > V_MOVE_TH);
  if (imuMovingNow || radarSaysMoving) {
    lastMovementTime = now;
    longAlertSent = false;
  }

  if (!longAlertSent && (now - lastMovementTime > IMMOBILITY_TIMEOUT)) {
     if (patient.locked) { 
        Serial.println(">>> LONG IMMOBILITY ALERT <<<");
        unsigned long immMs = now - lastMovementTime;
        String j = buildImmobilityJson(immMs);
        if (postJsonToCloud(j, now)) {
          longAlertSent = true;
        }
     }
  }

  if (best != prevBest || patient.locked != prevLocked) {
    prevBest = best;
    prevLocked = patient.locked;
    Serial.printf("[STATE] locked=%d idx=%d v=%.2f IMU=%s\n",
      patient.locked, patient.idx, patient.v,
      haveImu ? (imuMovingNow ? "MOV" : "STILL") : "NO-LINK"
    );
  }
  delay(100);
}
