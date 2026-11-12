// /examples/KeyboardButton/KeyboardButton.ino
// Types a line of text each time D2 is shorted to GND.
#include <Keyboard.h>

const uint8_t BUTTON_PIN = 2;

void setup() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  Keyboard.begin(KeyboardLayout_da_DK);   // matches Norwegian for letters, digits and common punctuation
}

void loop() {
  if (digitalRead(BUTTON_PIN) == LOW) {
    Keyboard.println("Hei fra Kjern-32u4HID-C");
    while (digitalRead(BUTTON_PIN) == LOW) delay(10);
    delay(50);                            // debounce
  }
}
