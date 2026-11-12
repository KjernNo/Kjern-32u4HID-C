// /examples/SelfTest/SelfTest.ino
// Board check for the Kjern-32u4HID-C. Open the Serial Monitor (any baud rate).
// Leave the castellated pins unconnected while the pin test runs.
//   i = info      v = supply voltage      p = pin leak test
//   k = type a test line as a keyboard    b = restart into the bootloader
// Shorting D2 to GND also types the test line. LED: slow blink = running.
#include <Keyboard.h>
#include <KjernBoard.h>
#include <avr/boot.h>

const uint8_t BUTTON_PIN = 2;

struct TestPin { const char *name; uint8_t pin; };
const TestPin TEST_PINS[] = {
  {"D0  PD2", 0}, {"D1  PD3", 1}, {"D2  PD1", 2}, {"D3  PD0", 3}, {"D8  PB4", 8}, {"D9  PB5", 9},
  {"D10 PB6", 10}, {"D11 PB7", 11}, {"D14 MISO", 14}, {"D15 SCK", 15}, {"D16 MOSI", 16},
  {"D17 PB0", 17}, {"A3  PF4", A3}, {"A4  PF1", A4}, {"A5  PF0", A5},
};

void printVcc() {
  uint16_t mv = kjernReadVccMillivolts();
  Serial.print(F("Supply: ")); Serial.print(mv); Serial.print(F(" mV  "));
  if (mv < 4500) Serial.println(F("LOW: below the 4.5 V the chip needs at 16 MHz. Check fuse F1 / JP5."));
  else Serial.println(F("ok"));
}

void printInfo() {
  Serial.println(F("--- Kjern-32u4HID-C self test ---"));
  printVcc();
  Serial.print(F("Fuses low/high/ext: "));
  Serial.print(boot_lock_fuse_bits_get(GET_LOW_FUSE_BITS), HEX);      Serial.print(' ');
  Serial.print(boot_lock_fuse_bits_get(GET_HIGH_FUSE_BITS), HEX);     Serial.print(' ');
  Serial.print(boot_lock_fuse_bits_get(GET_EXTENDED_FUSE_BITS), HEX);
  Serial.print(F("   lock: "));
  Serial.println(boot_lock_fuse_bits_get(GET_LOCK_BITS), HEX);
  Serial.println(F("  expected FF D8 CB (ext may read FB), lock 2F or EF"));
  Serial.print(F("Uptime: ")); Serial.print(millis() / 1000); Serial.println(F(" s"));
  Serial.println(F("Commands: i info, v voltage, p pin test, k keyboard test, b bootloader"));
}

// Each pin is checked floating: it must follow its own pull-up to HIGH and must fall back to
// LOW after being discharged. A pin that stays LOW leaks to GND, one that stays HIGH leaks to +5V.
void pinTest() {
  Serial.println(F("Pin test (nothing may be connected to the edge pins):"));
  uint8_t bad = 0;
  for (uint8_t i = 0; i < sizeof(TEST_PINS) / sizeof(TEST_PINS[0]); i++) {
    uint8_t p = TEST_PINS[i].pin;
    pinMode(p, INPUT_PULLUP); delay(2);
    bool high = digitalRead(p);
    pinMode(p, OUTPUT); digitalWrite(p, LOW); delay(1);
    pinMode(p, INPUT); delayMicroseconds(50);
    bool low = !digitalRead(p);
    Serial.print(F("  ")); Serial.print(TEST_PINS[i].name); Serial.print(F(": "));
    if (high && low) Serial.println(F("ok"));
    else { bad++; Serial.println(high ? F("stays HIGH (leak to +5V?)") : F("stays LOW (leak to GND?)")); }
  }
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  Serial.print(bad); Serial.println(F(" pin(s) with a problem"));
}

void typeTestLine() {
  Keyboard.println("Kjern-32u4HID-C fungerer!");
}

void setup() {
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(115200);
  Keyboard.begin(KeyboardLayout_da_DK);   // matches Norwegian for the characters used here
}

void loop() {
  static bool greeted = false;
  if (Serial && !greeted) { delay(300); printInfo(); greeted = true; }
  if (!Serial) greeted = false;

  digitalWrite(LED_BUILTIN, (millis() / 500) & 1);

  if (Serial.available()) {
    char c = Serial.read();
    if (c == 'i') printInfo();
    else if (c == 'v') printVcc();
    else if (c == 'p') pinTest();
    else if (c == 'k') { Serial.println(F("Typing in 3 s, click into a text field...")); delay(3000); typeTestLine(); }
    else if (c == 'b') { Serial.println(F("Restarting into the bootloader")); Serial.flush(); delay(100); kjernEnterBootloader(); }
  }

  if (digitalRead(BUTTON_PIN) == LOW) {
    typeTestLine();
    while (digitalRead(BUTTON_PIN) == LOW) delay(10);
    delay(50);
  }
}
