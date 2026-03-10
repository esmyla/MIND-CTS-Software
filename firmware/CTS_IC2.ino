#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ================= BLE UUIDs =================
#define SERVICE_UUID           "12345678-1234-1234-1234-1234567890ab"

#define HR_CHAR_UUID           "11111111-1111-1111-1111-111111111111"
#define TEMP_CHAR_UUID         "22222222-2222-2222-2222-222222222222"
#define FSR_CHAR_UUID          "33333333-3333-3333-3333-333333333333"
#define CMD_CHAR_UUID          "44444444-4444-4444-4444-444444444444"

// ================= BLE Globals =================
BLECharacteristic *hrChar;
BLECharacteristic *tempChar;
BLECharacteristic *fsrChar;
BLECharacteristic *cmdChar;

bool deviceConnected = false;

// ================= Sensors =================
MAX30105 particleSensor;

// Analog pins (ESP32-C6 ADC capable)
#define TEMP_PIN A0   // TMP36
#define FSR_PIN  A1   // FSR 402

// TMP36 constants
const float TMP36_OFFSET = 0.5;
const float TMP36_SCALE  = 100.0;

// Heart rate variables
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute = 0;
int beatAvg = 0;

// ================= BLE Callbacks =================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    BLEDevice::getAdvertising()->start();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String value = pChar->getValue();   // ✅ FIXED

    value.trim();        // remove whitespace
    value.toUpperCase(); // normalize

    if (value.length() == 0) return;

    Serial.print("BLE Command: ");
    Serial.println(value);

    if (value == "UP") {
      Serial.println("Command UP received");
    }
    else if (value == "DOWN") {
      Serial.println("Command DOWN received");
    }
    else if (value == "STOP") {
      Serial.println("Command STOP received");
    }
  }
};

// ================= Setup =================
void setup() {
  Serial.begin(115200);
  delay(1000);

  // ---------- BLE ----------
  BLEDevice::init("ESP32-C6_RawSensors");
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);

  // Heart Rate Characteristic
  hrChar = service->createCharacteristic(
    HR_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  hrChar->addDescriptor(new BLE2902());

  // Temperature Characteristic
  tempChar = service->createCharacteristic(
    TEMP_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  tempChar->addDescriptor(new BLE2902());

  // FSR Characteristic
  fsrChar = service->createCharacteristic(
    FSR_CHAR_UUID,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  fsrChar->addDescriptor(new BLE2902());

  // Command RX Characteristic
  cmdChar = service->createCharacteristic(
    CMD_CHAR_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  cmdChar->setCallbacks(new CommandCallbacks());

  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();

  Serial.println("BLE advertising started");

  // ---------- I2C ----------
  Wire.begin();

  // ---------- MAX30102 ----------
  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("MAX30102 not found");
    while (1);
  }

  particleSensor.setup();
  particleSensor.setPulseAmplitudeIR(0x1F);
  particleSensor.setPulseAmplitudeRed(0x0A);
  particleSensor.setPulseAmplitudeGreen(0);

  Serial.println("Sensors initialized");
}

// ================= Main Loop =================
void loop() {

  // -------- Heart Rate --------
long irValue = particleSensor.getIR();

// Finger detection (NO RETURN)
bool fingerPresent = irValue > 50000;

if (fingerPresent) {
  if (checkForBeat(irValue)) {
    long delta = millis() - lastBeat;
    lastBeat = millis();

    // Reject insane intervals
    if (delta > 300 && delta < 2000) {   // 30–200 BPM
      beatsPerMinute = 60.0 / (delta / 1000.0);

      rates[rateSpot++] = (byte)beatsPerMinute;
      rateSpot %= RATE_SIZE;

      beatAvg = 0;
      for (byte i = 0; i < RATE_SIZE; i++)
        beatAvg += rates[i];
      beatAvg /= RATE_SIZE;
    }
  }
} else {
  beatAvg = 0;
}

  // -------- Temperature --------
  int tempADC = analogRead(TEMP_PIN);
  float voltage = tempADC * (3.3 / 4095.0);  // ESP32-C6 ADC
  float tempC = (voltage - TMP36_OFFSET) * TMP36_SCALE;
  float tempF = (tempC * 9.0 / 5.0) + 32.0;

  // -------- FSR --------
  int fsrADC = analogRead(FSR_PIN);

  // -------- BLE Notify --------
  if (deviceConnected) {
    char buffer[80];

    // Heart Rate RAW
    snprintf(buffer, sizeof(buffer),
             "IR:%ld,BPM:%d",
             irValue, beatAvg);
    hrChar->setValue((uint8_t*)buffer, strlen(buffer));
    hrChar->notify();

    // Temperature RAW
    snprintf(buffer, sizeof(buffer),
             "ADC:%d,TempC:%.2f,TempF:%.2f",
             tempADC, tempC, tempF);
    tempChar->setValue((uint8_t*)buffer, strlen(buffer));
    tempChar->notify();

    // FSR RAW
    snprintf(buffer, sizeof(buffer),
             "FSR_ADC:%d",
             fsrADC);
    fsrChar->setValue((uint8_t*)buffer, strlen(buffer));
    fsrChar->notify();
  }

  // -------- Serial Debug --------
  Serial.print("IR=");
  Serial.print(irValue);
  Serial.print(" BPM=");
  Serial.print(beatAvg);
  Serial.print(" TempC=");
  Serial.print(tempC);
  Serial.print(" FSR=");
  Serial.println(fsrADC);

  delay(5);
}


