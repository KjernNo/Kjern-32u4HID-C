// /examples/MacroKeys/MacroKeys.ino
// Four shortcut keys. Wire a push button from each pin to GND.
//   D8 = copy   D9 = paste   D10 = undo   D11 = lock the computer (Windows)
#include <Keyboard.h>

struct Macro { uint8_t pin; uint8_t modifier; uint8_t key; };
const Macro MACROS[] = {
  {8,  KEY_LEFT_CTRL, 'c'},
  {9,  KEY_LEFT_CTRL, 'v'},
  {10, KEY_LEFT_CTRL, 'z'},
  {11, KEY_LEFT_GUI,  'l'},
};
const uint8_t MACRO_COUNT = sizeof(MACROS) / sizeof(MACROS[0]);
bool wasDown[MACRO_COUNT];

void setup() {
  for (uint8_t i = 0; i < MACRO_COUNT; i++) pinMode(MACROS[i].pin, INPUT_PULLUP);
  Keyboard.begin();
}

void loop() {
  for (uint8_t i = 0; i < MACRO_COUNT; i++) {
    bool down = digitalRead(MACROS[i].pin) == LOW;
    if (down && !wasDown[i]) {
      Keyboard.press(MACROS[i].modifier);
      Keyboard.press(MACROS[i].key);
      delay(20);
      Keyboard.releaseAll();
    }
    wasDown[i] = down;
  }
  delay(10);                              // debounce
}
