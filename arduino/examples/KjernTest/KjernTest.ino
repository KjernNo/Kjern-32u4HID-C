// /KjernTest.ino
#include <Keyboard.h>

const uint8_t BUTTON_PIN = 2;

void setup() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(LED_BUILTIN, OUTPUT);
  Keyboard.begin(KeyboardLayout_da_DK);
}

void loop() {
  // LED: solid = USB enumerated, blinking = running but not enumerated
  if (USBDevice.configured()) digitalWrite(LED_BUILTIN, HIGH);
  else digitalWrite(LED_BUILTIN, (millis() / 250) & 1);

  if (digitalRead(BUTTON_PIN) == LOW) {
    Keyboard.println("Kjern-32u4HID-C fungerer!");
    while (digitalRead(BUTTON_PIN) == LOW) delay(10);
    delay(50);
  }
}
