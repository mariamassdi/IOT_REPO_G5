#include <MPU9250_WE.h>
#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <math.h>
#include <esp_now.h>
#include "freertos/portmacro.h"
#include <vector> 
#include "parameters.h" 
#include "secrets.h"   

// ===================== ESP-NOW (IMU -> RADAR) =====================

typedef struct __attribute__((packed)) {
  uint32_t seq;
  uint8_t  imuMoving;      
  uint8_t  activity;       
  float    wmag;
  float    alim;           
  float    tiltDeg;        
} ImuStatusPacket;

static ImuStatusPacket imuPkt;
static uint32_t imuSeq = 0;
static unsigned long lastEspNowSend = 0;

WiFiClientSecure client;
HTTPClient http;
bool isHttpConnected = false;
unsigned long lastSend = 0; 

struct PendingAlert {
  String jsonPayload;
};
std::vector<PendingAlert> alertQueue; 

struct SharedData {
  int steps;
  int stairs;
  int falls;
  bool isMoving;
  bool fallDetected; 
  bool sendImOk;     
  unsigned long fallSeq;
  float raw_alim;
  float raw_wmag;
  float raw_tilt;
};
volatile SharedData g_data = {0, 0, 0, false, false, false, 0, 0.0, 0.0, 0.0};
portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

// ===================== משתני חיישן (ליבה 1) =====================
MPU9250_WE myMPU9250 = MPU9250_WE(MPU9250_ADDR);

float buffer[50];
int bufferIndex = 0;
bool stepDetected = false;
unsigned long lastStepTime = 0;
float prevAx = 0.0, prevAy = 0.0, prevAz = 0.0;
bool firstSample = true;
int local_steps = 0;

enum StairStep { ST_NONE, ST_UP, ST_DOWN, ST_UNK };
int local_stairs = 0;
bool stairWinActive = false;
unsigned long stairWinStart = 0;
float alimSqSum = 0.0f;
int   alimN = 0;
float tiltMinW = 9999.0f;
float tiltMaxW = -9999.0f;
float yPosPeak = 0.0f;   
float yNegPeak = 0.0f;   

enum FallState { NORMAL, SUSPECT, ALERT, IM_OK };
FallState fallState = NORMAL;

unsigned long suspectStart = 0;
unsigned long stillStart = 0;
unsigned long alertStart = 0;
unsigned long imOkStart = 0;
bool awaitingOk = false;
int local_falls = 0;
unsigned long local_fallSeq = 0;
bool imOkJustConfirmed = false;
xyzFloat gLP = { 0, 0, 0 };
bool gInit = false; 

// ===================== פונקציות עזר =====================
static inline float norm3(float x, float y, float z) { return sqrtf(x*x+y*y+z*z); }
static inline float clamp01(float v) { if(v<0)return 0; if(v>1)return 1; return v; }

static float legTiltDegFromVertical(const xyzFloat& g) {
  float gmag = norm3(g.x,g.y,g.z);
  if(gmag<1e-6f)return 0;
  return acosf(clamp01(fabs(g.y)/gmag)) * 57.29578f;
}

uint8_t calcImuMoving(float alim, float wmag, unsigned long nowMs) {
  bool recentStep = (nowMs - lastStepTime) < 800;
  bool moving = (alim > 0.12f) || (wmag > 60.0f) || recentStep;
  return moving ? 1 : 0;
}

uint8_t calcActivity(float alim, float wmag) {
  float a = alim / 0.60f;     
  float w = wmag / 300.0f;
  float s = 0.6f*a + 0.4f*w;
  if (s < 0) s = 0;
  if (s > 1) s = 1;
  return (uint8_t)lroundf(s * 100.0f);
}

void finishStairWindowAndClassify() {
  if (!stairWinActive) return;
  stairWinActive = false;
  float alimRms = (alimN > 0) ? sqrtf(alimSqSum / alimN) : 0.0f;
  float tiltRange = tiltMaxW - tiltMinW;
  bool passAlim = (alimRms >= STAIRS_ALIM_RMS_TH);
  bool passTilt = (tiltRange >= STAIRS_TILT_RANGE_TH);
  bool yAsym = (yPosPeak > yNegPeak * STAIRS_DIR_RATIO) || (yNegPeak > yPosPeak * STAIRS_DIR_RATIO);
  bool isStairStep = passAlim && (yAsym || passTilt);
  
  if (isStairStep) {
    local_stairs++;
    Serial.println(">>> STAIR DETECTED! <<<");
  }
}

// ===================== ליבה 1: והחיישנים =====================
void SensorTask(void *pvParameters) {
  for(int i=0; i<BUFFER_LENGTH; i++) buffer[i] = 1.0f;
  for(;;) {
    unsigned long now = millis();
    xyzFloat gValue = myMPU9250.getGValues();
    float amag = myMPU9250.getResultantG(gValue);
    xyzFloat gyro = myMPU9250.getGyrValues();    
    float wmag = norm3(gyro.x, gyro.y, gyro.z);

    if (!gInit) { gLP = gValue; gInit = true; }
    gLP.x = ALPHA_G * gLP.x + (1.0f - ALPHA_G) * gValue.x;
    gLP.y = ALPHA_G * gLP.y + (1.0f - ALPHA_G) * gValue.y;
    gLP.z = ALPHA_G * gLP.z + (1.0f - ALPHA_G) * gValue.z;
    float alx = gValue.x - gLP.x;
    float aly = gValue.y - gLP.y; float alz = gValue.z - gLP.z;
    float alim = norm3(alx, aly, alz);
    float tiltDeg = legTiltDegFromVertical(gLP);

    uint8_t moveVal = calcImuMoving(alim, wmag, now);
    if (stairWinActive) {
      alimSqSum += alim*alim; alimN++;
      if (tiltDeg<tiltMinW) tiltMinW=tiltDeg; if (tiltDeg>tiltMaxW) tiltMaxW=tiltDeg;
      if (aly>yPosPeak) yPosPeak=aly; if (-aly>yNegPeak) yNegPeak=-aly;
      if (now - stairWinStart >= STAIR_WIN_MS) finishStairWindowAndClassify();
    }

    float ax=gValue.x, ay=gValue.y, az=gValue.z;
    if(firstSample){prevAx=ax;prevAy=ay;prevAz=az;firstSample=false;}
    float dy = fabs(ay - prevAy); prevAx=ax; prevAy=ay;
    prevAz=az;
    buffer[bufferIndex] = amag; bufferIndex = (bufferIndex + 1) % BUFFER_LENGTH;
    float avgMag = 0; for(int i=0;i<BUFFER_LENGTH;i++) avgMag+=buffer[i]; avgMag/=BUFFER_LENGTH;
    if (amag > (avgMag + STEP_THRESHOLD) && (dy > Y_THRESHOLD) && fallState == NORMAL) {
      if (!stepDetected && (now - lastStepTime) > DEBOUNCE_DELAY) {
        finishStairWindowAndClassify();
        stairWinActive = true; stairWinStart = now;
        alimSqSum=0; alimN=0; tiltMinW=9999; tiltMaxW=-9999; yPosPeak=0; yNegPeak=0;
        stepDetected = true; lastStepTime = now;
         local_steps++;
        Serial.println(">>> STEP DETECTED! <<<");
      }
    } else { stepDetected = false; }

    bool suspectTrigger = (amag > IMPACT_G) && (wmag > ROT_DPS);
    bool fallJustTriggered = false;
    if (fallState == NORMAL) {
      if (suspectTrigger) { fallState = SUSPECT; suspectStart = now; }
    } else if (fallState == SUSPECT) {
      if ((tiltDeg > TILT_DEG) && (wmag < STILL_W) && (alim < STILL_AL)) {
        if (stillStart == 0) stillStart = now;
        if (now - stillStart > STILL_TIME_MS) {
          fallState = ALERT;
          awaitingOk = true; alertStart = now;
          fallJustTriggered = true; 
          local_fallSeq++; 
          local_falls++;
          Serial.println("!!! FALL DETECTED (Logic Trigger) !!!");
        }
      } else { stillStart = 0; }
      if (now - suspectStart > SUSPECT_TIMEOUT_MS) fallState = NORMAL;
    } else if (fallState == ALERT) {
      if (awaitingOk && (now - alertStart > OK_TIMEOUT_MS)) { awaitingOk = false; fallState = NORMAL; }
    }

    portENTER_CRITICAL(&g_mux);
    g_data.steps = local_steps;
    g_data.stairs = local_stairs;
    g_data.falls = local_falls;
    g_data.fallSeq = local_fallSeq; g_data.isMoving = (moveVal == 1);
    g_data.raw_alim = alim; g_data.raw_wmag = wmag; g_data.raw_tilt = tiltDeg;
    if (fallJustTriggered) g_data.fallDetected = true;
    portEXIT_CRITICAL(&g_mux);

    vTaskDelay(10 / portTICK_PERIOD_MS); 
  }
}

// ===================== ליבה 0: תקשורת =====================
void ensureEspNow() {
  if (esp_now_init() != ESP_OK) return;
  esp_now_peer_info_t peerInfo = {};
  memcpy(peerInfo.peer_addr, RADAR_MAC_ADDR, 6); 
  peerInfo.channel = 0;      
  peerInfo.encrypt = false;
  esp_now_add_peer(&peerInfo);
}

void ensureWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  static unsigned long lastTry = 0;
  if (millis() - lastTry > 5000) { 
    lastTry = millis();
    Serial.println("--- WiFi Lost. Reconnecting... ---");
    WiFi.disconnect();
    WiFi.reconnect();
  }
}

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);
  WiFi.mode(WIFI_AP_STA); 
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\nWiFi Connected!");
  
  ensureEspNow();
  client.setInsecure();
  myMPU9250.init();
  myMPU9250.autoOffsets();
  myMPU9250.setSampleRateDivider(5);
  myMPU9250.setAccRange(MPU9250_ACC_RANGE_4G);
  myMPU9250.enableAccDLPF(true);
  myMPU9250.setAccDLPF(MPU9250_DLPF_4);
  xTaskCreatePinnedToCore(SensorTask, "SensorTask", 10000, NULL, 1, NULL, 1);
}

bool sendJsonToCloudBool(String json) {
  if (WiFi.status() != WL_CONNECTED) return false;

  if (!isHttpConnected) {
      http.begin(client, CLOUD_URL);
      http.setReuse(true); 
      http.addHeader("Content-Type", "application/json");
      isHttpConnected = true;
  }
  int code = http.POST(json);
  
  if (code >= 200 && code < 300) { 
    String r = http.getString();
    return true; 
  }
  else { 
    http.end(); 
    isHttpConnected = false; 
    Serial.print("HTTP Error: "); Serial.println(code);
    return false;
  }
}

String buildJson(const SharedData& d, const char* type, bool alert) {
  String j = "{";
  j += "\"patientId\":\"" + String(PATIENT_ID) + "\",";
  j += "\"type\":\"" + String(type) + "\","; 
  j += "\"source\":\"imu\",";
  j += "\"steps\":" + String(d.steps) + ",";
  j += "\"stairsCount\":" + String(d.stairs) + ",";
  j += "\"fallsCount\":" + String(d.falls) + ",";
  j += "\"imuMoving\":" + String(d.isMoving ? "true" : "false") + ",";
  j += "\"fall\":" + String(alert ? "true" : "false");
  j += "}";
  return j;
}

void loop() {
  ensureWiFi(); 

  unsigned long now = millis();
  
  if (WiFi.status() == WL_CONNECTED && !alertQueue.empty()) {
     Serial.println(">>> Internet Back! Syncing pending alerts...");
     
     PendingAlert alert = alertQueue.front();
     if (sendJsonToCloudBool(alert.jsonPayload)) {
         Serial.println(">>> Sync Success!");
         alertQueue.erase(alertQueue.begin());
     }
  }
  // ========================================================

  SharedData snap;
  bool triggerAlert = false;
  
  portENTER_CRITICAL(&g_mux);
  snap.steps = g_data.steps;
  snap.stairs = g_data.stairs;
  snap.falls = g_data.falls;
  snap.isMoving = g_data.isMoving;
  snap.fallSeq = g_data.fallSeq;
  snap.raw_alim = g_data.raw_alim;
  snap.raw_wmag = g_data.raw_wmag;
  snap.raw_tilt = g_data.raw_tilt;
  if (g_data.fallDetected) {
    triggerAlert = true;
    g_data.fallDetected = false;
  }
  portEXIT_CRITICAL(&g_mux);

  if (now - lastEspNowSend >= ESPNOW_SEND_MS) {
    lastEspNowSend = now;
    imuPkt.seq = imuSeq++;
    imuPkt.imuMoving = snap.isMoving ? 1 : 0;
    imuPkt.activity = calcActivity(snap.raw_alim, snap.raw_wmag);
    imuPkt.wmag = snap.raw_wmag;
    imuPkt.alim = snap.raw_alim;
    imuPkt.tiltDeg = snap.raw_tilt;
    esp_now_send(RADAR_MAC_ADDR, (uint8_t*)&imuPkt, sizeof(imuPkt)); 
  }

  if (triggerAlert) {
    Serial.println("!!! FALL DETECTED !!!");
    String json = buildJson(snap, "fall_alert", true);
    
    bool sent = sendJsonToCloudBool(json);
    
    if (!sent) {
      Serial.println("!!! NO INTERNET - QUEUING ALERT !!!");
      if (alertQueue.size() < 20) { 
        alertQueue.push_back({json});
      }
    } else {
       Serial.println("!!! ALERT SENT TO CLOUD !!!");
    }
  }
  
  if (now - lastSend > 600) {
    lastSend = now;
    sendJsonToCloudBool(buildJson(snap, "telemetry", false));
  }
  delay(5);
}
