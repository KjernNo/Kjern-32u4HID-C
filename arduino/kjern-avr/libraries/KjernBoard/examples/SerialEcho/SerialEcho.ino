// /examples/SerialEcho/SerialEcho.ino
// Echoes everything received on the USB serial port and reports the supply voltage once a second.
#include <KjernBoard.h>

void setup() {
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(115200);
}

void loop() {
  static uint32_t last = 0;
  while (Serial.available()) {
    Serial.write(Serial.read());
    digitalWrite(LED_BUILTIN, !digitalRead(LED_BUILTIN));
  }
  if (millis() - last >= 1000) {
    last = millis();
    Serial.print(F("Kjern-32u4HID-C, supply "));
    Serial.print(kjernReadVccMillivolts());
    Serial.println(F(" mV"));
  }
}
