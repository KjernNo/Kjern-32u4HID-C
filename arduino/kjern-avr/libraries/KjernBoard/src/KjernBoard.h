// /src/KjernBoard.h
// Small helpers for the Kjern-32u4HID-C. Header only, nothing runs unless a sketch calls it.
#ifndef KJERN_BOARD_H
#define KJERN_BOARD_H

#include <Arduino.h>
#include <avr/wdt.h>

// Supply voltage in millivolts, measured against the internal 1.1 V bandgap (about +-10 %).
// A healthy board on USB reads 4700 to 5200. Below 4500 the chip is outside its 16 MHz rating.
static inline uint16_t kjernReadVccMillivolts() {
  uint8_t admux = ADMUX, adcsra = ADCSRA, adcsrb = ADCSRB;
  ADCSRB &= ~_BV(MUX5);
  ADMUX = _BV(REFS0) | 0x1E;                      // AVCC as reference, bandgap as input
  ADCSRA = _BV(ADEN) | _BV(ADPS2) | _BV(ADPS1) | _BV(ADPS0);
  delay(3);                                       // bandgap settling
  uint16_t raw = 0;
  for (uint8_t i = 0; i < 2; i++) {               // first conversion after a mux change is discarded
    ADCSRA |= _BV(ADSC);
    while (ADCSRA & _BV(ADSC)) {}
    raw = ADC;
  }
  ADMUX = admux; ADCSRA = adcsra; ADCSRB = adcsrb;
  if (raw == 0) return 0;
  return (uint16_t)(1125300UL / raw);             // 1.1 V * 1023 * 1000
}

// Restarts into the bootloader, the same way the Arduino IDE does before an upload.
// The board comes back as "Kjern Bootloader" for 8 seconds, then the sketch starts again.
static inline void kjernEnterBootloader() {
  *(volatile uint16_t *)0x0800 = 0x7777;          // boot key the bootloader looks for
  wdt_enable(WDTO_120MS);                         // the watchdog reset lands in the bootloader
  for (;;) {}
}

#endif
