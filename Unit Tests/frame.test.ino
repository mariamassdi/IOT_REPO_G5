// RD-03D full-frame debug test

const uint8_t HEADER[4] = {0xAA, 0xFF, 0x03, 0x00};  // common RD-03D header
const int FRAME_LEN = 30;   // typical frame length for RD-03D (may be 24/30/32 depending on fw)

void setup() {
  Serial.begin(115200);                          // PC monitor
  Serial2.begin(256000, SERIAL_8N1, 26, 27);     // radar UART
  Serial.println("RD-03D frame debug starting...");
}

void loop() {
  // Wait until there is at least 4 bytes to check for header
  if (Serial2.available() < 4) return;

  // Look for header
  if (Serial2.peek() != HEADER[0]) {
    Serial2.read();  // discard byte
    return;
  }

  uint8_t buf[FRAME_LEN];
  size_t n = Serial2.readBytes(buf, FRAME_LEN);

  if (n != FRAME_LEN) {
    // Not enough bytes yet
    return;
  }

  // Quick check: header matches?
  if (buf[0] != HEADER[0] || buf[1] != HEADER[1] ||
      buf[2] != HEADER[2] || buf[3] != HEADER[3]) {
    return;
  }

  // Print the whole frame
  Serial.print("FRAME: ");
  for (int i = 0; i < FRAME_LEN; i++) {
    if (buf[i] < 0x10) Serial.print("0");
    Serial.print(buf[i], HEX);
    Serial.print(" ");
  }
  Serial.println();
}
