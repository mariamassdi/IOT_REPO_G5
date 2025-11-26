#include <Arduino.h>

// RD-03D frame format (multi-target):
// Header: AA FF 03 00
// Then 3 * 8-byte targets: X(2) Y(2) Speed(2) Distance(2)
// Tail: 55 CC
const uint8_t HEADER[4] = {0xAA, 0xFF, 0x03, 0x00};
const uint8_t TAIL[2]   = {0x55, 0xCC};
const int FRAME_LEN     = 30;   // 4 + 3*8 + 2

// UART pins (what you already use)
const int RX_PIN = 26;  // ESP32 receives from radar TX
const int TX_PIN = 27;  // ESP32 sends to radar RX

// Helpers to turn two bytes into ints
int16_t toInt16(uint8_t hi, uint8_t lo) {
  return (int16_t)((hi << 8) | lo);
}

uint16_t toUint16(uint8_t hi, uint8_t lo) {
  return (uint16_t)((hi << 8) | lo);
}

void setup() {
  Serial.begin(115200);
  Serial2.begin(256000, SERIAL_8N1, RX_PIN, TX_PIN);

  Serial.println("\nRD-03D parsed target monitor starting...");
  Serial.println("Move a PERSON 0.5–3m in front of the antenna.");
}

void loop() {
  if (Serial2.available() < FRAME_LEN) {
    // not enough data yet
    return;
  }

  // Look for header
  if (Serial2.peek() != HEADER[0]) {
    Serial2.read(); // throw away one byte and try again next loop
    return;
  }

  uint8_t buf[FRAME_LEN];
  size_t n = Serial2.readBytes(buf, FRAME_LEN);
  if (n != FRAME_LEN) return;

  // Verify header
  if (buf[0] != HEADER[0] || buf[1] != HEADER[1] ||
      buf[2] != HEADER[2] || buf[3] != HEADER[3]) {
    return;
  }

  // Verify tail
  if (buf[FRAME_LEN-2] != TAIL[0] || buf[FRAME_LEN-1] != TAIL[1]) {
    return;
  }

  // Parse 3 targets
  bool anyTarget = false;
  for (int t = 0; t < 3; t++) {
    int base = 4 + t * 8;

    int16_t x_raw   = toInt16(buf[base + 0], buf[base + 1]);
    int16_t y_raw   = toInt16(buf[base + 2], buf[base + 3]);
    int16_t v_raw   = toInt16(buf[base + 4], buf[base + 5]);
    uint16_t d_raw  = toUint16(buf[base + 6], buf[base + 7]);

    // Heuristic: if everything is zero, treat as "no target"
    if (x_raw == 0 && y_raw == 0 && d_raw == 0 && v_raw == 0) continue;

    anyTarget = true;

    // Convert to meters (rough scaling, depends on firmware;
    // you can tune factors if needed)
    float x = x_raw / 1000.0f;
    float y = y_raw / 1000.0f;
    float v = v_raw / 1000.0f;
    float d = d_raw / 1000.0f;

    Serial.print("TARGET ");
    Serial.print(t + 1);
    Serial.print(": dist=");
    Serial.print(d, 2);
    Serial.print(" m, x=");
    Serial.print(x, 2);
    Serial.print(" m, y=");
    Serial.print(y, 2);
    Serial.print(" m, speed=");
    Serial.print(v, 2);
    Serial.println(" m/s");
  }

  if (!anyTarget) {
    Serial.println("NO TARGETS");
  }
}
