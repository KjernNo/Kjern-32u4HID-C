// /examples/MouseButton/MouseButton.ino
// Needs the "Mouse" library (Library Manager). While D2 is held to GND the pointer moves in a
// small square, D3 to GND is a left click.
#include <Mouse.h>

const uint8_t MOVE_PIN = 2;
const uint8_t CLICK_PIN = 3;
const int8_t STEP_X[] = {4, 0, -4, 0};
const int8_t STEP_Y[] = {0, 4, 0, -4};

void setup() {
  pinMode(MOVE_PIN, INPUT_PULLUP);
  pinMode(CLICK_PIN, INPUT_PULLUP);
  Mouse.begin();
}

void loop() {
  static uint8_t side = 0, count = 0;
  if (digitalRead(MOVE_PIN) == LOW) {
    Mouse.move(STEP_X[side], STEP_Y[side], 0);
    if (++count >= 25) { count = 0; side = (side + 1) & 3; }
  }
  if (digitalRead(CLICK_PIN) == LOW) {
    if (!Mouse.isPressed(MOUSE_LEFT)) Mouse.press(MOUSE_LEFT);
  } else if (Mouse.isPressed(MOUSE_LEFT)) {
    Mouse.release(MOUSE_LEFT);
  }
  delay(10);
}
