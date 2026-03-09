#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"
// #include <BLEDevice.h>
// #include <BLEServer.h>
// #include <BLEUtils.h>
// #include <BLE2902.h>

// BLECharacteristic *pCharacteristic;
// bool deviceConnected = false;

// #define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
// #define CHARACTERISTIC_UUID "abcd1234-5678-1234-5678-abcdef123456"

// class MyServerCallbacks : public BLEServerCallbacks {
//   void onConnect(BLEServer* pServer) {
//     deviceConnected = true;
//   }
//   void onDisconnect(BLEServer* pServer) {
//     deviceConnected = false;
//   }
// };
#define HEATER_PIN 5     // GPIO connected to MOSFET gate
const int sensorPin = A0; // TMP36 analog pin

// Control parameters
const float TARGET_TEMP_C = 37.0;   // Desired temperature (°C)
const float DEADBAND = 0.5;          // Prevent rapid switching

float prevTempC = 0.0;
unsigned long prevTime = 0;

MAX30105 particleSensor;

// Pin definitions
const int TEMP_PIN = A0;  // TMP36
const int FSR_PIN  = A1;  // FSR 402
const int FSR_PIN2 = A2; // FSR 402 #2

int reading = 0; // define reading variable 

// TMP36 constants
const float TMP36_VOLTAGE_OFFSET = 0.5; // 500 mV offset
const float TMP36_SCALE = 100.0;         // 10 mV per °C

// Heart rate variables
const byte RATE_SIZE = 4;
byte rates[RATE_SIZE];
byte rateSpot = 0;
long lastBeat = 0;
float beatsPerMinute;
int beatAvg;

// class CommandCallback : public BLECharacteristicCallbacks {
//   void onWrite(BLECharacteristic *pChar) {
//     String value = pChar->getValue();  // <-- FIX HERE

//     Serial.print("Received BLE data: ");
//     Serial.println(value);

//     if (value == "UP") {
//       Serial.println("Command: UP");
//     }
//     else if (value == "DOWN") {
//       Serial.println("Command: DOWN");
//     }
//     else if (value == "STOP") {
//       Serial.println("Command: STOP");
//     }
//   }
// };

float readTemperatureC() {
  // int sensorValue = analogRead(sensorPin);
  // float voltage = sensorValue * (5.0 / 1023.0); // Use 3.3 if on ESP32
  // return (voltage - 0.5) * 100.0; // TMP36 conversion

  int sensorValue = analogRead(sensorPin); 
  float tempC = ((sensorValue * 5000 / 1024.0) - 500) / 10.0;
  return(tempC);
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  // BLEDevice::init("XIAO_ESP32C6");
  // BLEServer *pServer = BLEDevice::createServer();
  // pServer->setCallbacks(new MyServerCallbacks());

  // BLEService *pService = pServer->createService(SERVICE_UUID);

  // pCharacteristic = pService->createCharacteristic(
  //                     CHARACTERISTIC_UUID,
  //                     BLECharacteristic::PROPERTY_READ |
  //                     BLECharacteristic::PROPERTY_WRITE | 
  //                     BLECharacteristic::PROPERTY_NOTIFY
                      
  //                   );
  // pCharacteristic->addDescriptor(new BLE2902());
  // pCharacteristic->setValue("Hello BLE");
  // pCharacteristic->setCallbacks(new CommandCallback());

  // pService->start();

  // BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  // pAdvertising->addServiceUUID(SERVICE_UUID);
  // pAdvertising->setScanResponse(true);
  // pAdvertising->start();
  // Serial.println("BLE device is advertising...");
  // Serial.println("Initializing sensors...");

  // Initialize I2C
  Wire.begin();

  // Initialize MAX30102
  if (!particleSensor.begin(Wire, I2C_SPEED_STANDARD)) {
    Serial.println("MAX30102 not found. Check wiring.");
    while (1);
  }

  // particleSensor.setup();                 // Default configuration
  // particleSensor.setPulseAmplitudeRed(0x1F);
  // particleSensor.setPulseAmplitudeGreen(0); // Green not used
  particleSensor.setup(); //Configure sensor with default settings
  particleSensor.setPulseAmplitudeIR(0x1F);
  particleSensor.setPulseAmplitudeRed(0x0A); //Turn Red LED to low to indicate sensor is running
  particleSensor.setPulseAmplitudeGreen(0); //Turn off Green LED



  Serial.println("Sensors initialized.");

  pinMode(HEATER_PIN, OUTPUT);
  digitalWrite(HEATER_PIN, LOW); // Heater OFF on boot

  Serial.begin(9600);
  delay(1000);

  prevTime = millis();
  prevTempC = readTemperatureC();
}

void loop() {

    // if (deviceConnected) {
    // pCharacteristic->setValue("ESP32-C6 says hi 👋");
    // pCharacteristic->notify();
    // delay(1000);
    // }

  //--------------------------------
  //Hear Rate
  //--------------------------------
  long irValue = particleSensor.getIR();

  if (checkForBeat(irValue) == true)
  {
    long delta = millis() - lastBeat;
    lastBeat = millis();

    beatsPerMinute = 60 / (delta / 1000.0);

    if (beatsPerMinute < 255 && beatsPerMinute > 20)
    {
      rates[rateSpot++] = (byte)beatsPerMinute; //Store this reading in the array
      rateSpot %= RATE_SIZE; //Wrap variable

      //Take average of readings
      beatAvg = 0;
      for (byte x = 0 ; x < RATE_SIZE ; x++)
        beatAvg += rates[x];
      beatAvg /= RATE_SIZE;
    }
  
  // -------------------------------
  // TMP36 – Temperature
  // -------------------------------
  int tempADC = analogRead(TEMP_PIN);
  // float voltage = tempADC * (5.0 / 1023.0);
  // float temperatureC = (voltage - TMP36_VOLTAGE_OFFSET) * TMP36_SCALE;
  float temperatureC = ((tempADC * 5000 / 1024.0) - 500) / 10.0;
  float temperatureF = (temperatureC * 9.0 / 5.0) + 32.0;

  // -------------------------------
  // FSR 402 – Force Sensor
  // -------------------------------
  int fsrADC = analogRead(FSR_PIN);
  int fsrADC2 = analogRead(FSR_PIN2); 
  //--------------------------------
  // MOfset control
  //-------------------------------- 
  unsigned long currentTime = millis();
  float currentTempC = readTemperatureC();

  // Time difference in seconds
  float timeDiff = (currentTime - prevTime) / 1000.0;

  // Temperature rate (°C/sec)
  float rateCPerSec = 0.0;
  if (timeDiff > 0) {
    rateCPerSec = (currentTempC - prevTempC) / timeDiff;
  }

  // -------- FEEDBACK CONTROL --------
  if (currentTempC < TARGET_TEMP_C - DEADBAND) {
    digitalWrite(HEATER_PIN, HIGH);  // Heater ON
  }
  else if (currentTempC > TARGET_TEMP_C + DEADBAND) {
    digitalWrite(HEATER_PIN, LOW);   // Heater OFF
  }

  // -------- SERIAL OUTPUT --------
  Serial.print("Temp: ");
  Serial.print(currentTempC);
  Serial.print(" °C | Rate: ");
  Serial.print(rateCPerSec);
  Serial.print(" °C/sec | Heater: ");
  Serial.println(digitalRead(HEATER_PIN));

  // Update previous values
  prevTempC = currentTempC;
  prevTime = currentTime;

  // // -------------------------------
  // // Serial Output
  // // -------------------------------
  Serial.print("IR: ");
  Serial.print(irValue);

  Serial.print(" | BPM: ");
  Serial.print(beatsPerMinute);

  Serial.print(" | Avg BPM: ");
  Serial.print(beatAvg);

  Serial.print(" | Temp: ");
  Serial.print(temperatureC);
  Serial.print(" °C / ");
  Serial.print(temperatureF);
  Serial.print(" °F");

  Serial.print(" | FSR ADC: ");
  Serial.print(fsrADC);

  Serial.print(" | FSR ADC2: ");
  Serial.print(fsrADC2);

  Serial.println();

  delay(200);
  }
}

