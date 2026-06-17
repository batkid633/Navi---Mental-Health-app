#include <Adafruit_BH1750.h>
#include <Adafruit_MCP9808.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <MAX30105.h>
#include <MPU6050_light.h>
#include <Wire.h>
#include "heartRate.h"

// ESP32-WROOM default I2C pins. Change these if your wiring diagram differs.
constexpr int I2C_SDA_PIN = 21;
constexpr int I2C_SCL_PIN = 22;
constexpr int BATTERY_ADC_PIN = 34;

constexpr char DEVICE_NAME[] = "Navi Beacon";
constexpr char SERVICE_UUID[] = "6e400001-b5a3-f393-e0a9-e50e24dcca9e";
constexpr char TELEMETRY_UUID[] = "6e400003-b5a3-f393-e0a9-e50e24dcca9e";
constexpr unsigned long SERIAL_INTERVAL_MS = 1000;
constexpr unsigned long BLE_INTERVAL_MS = 5000;

MAX30105 ppg;
Adafruit_MCP9808 tempSensor;
Adafruit_BH1750 lightSensor;
MPU6050 mpu(Wire);
BLECharacteristic *telemetryCharacteristic = nullptr;

bool hasPpg = false;
bool hasTemp = false;
bool hasLight = false;
bool hasMotion = false;
bool bleClientConnected = false;

unsigned long lastSerialMs = 0;
unsigned long lastBleMs = 0;
long lastBeatMs = 0;
float bpm = 0;
float bpmAverage = 0;
byte bpmSamples = 0;

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *server) override {
    bleClientConnected = true;
  }

  void onDisconnect(BLEServer *server) override {
    bleClientConnected = false;
    BLEDevice::startAdvertising();
  }
};

void setup() {
  Serial.begin(115200);
  delay(300);

  Wire.begin(I2C_SDA_PIN, I2C_SCL_PIN);
  Wire.setClock(400000);

  hasPpg = ppg.begin(Wire, I2C_SPEED_FAST);
  if (hasPpg) {
    ppg.setup();
    ppg.setPulseAmplitudeRed(0x2f);
    ppg.setPulseAmplitudeGreen(0);
  }

  hasTemp = tempSensor.begin(0x18);
  if (hasTemp) {
    tempSensor.setResolution(2);
  }

  hasLight = lightSensor.begin(BH1750_TO_GROUND);
  hasMotion = mpu.begin() == 0;
  if (hasMotion) {
    delay(1000);
    mpu.calcOffsets(true, true);
  }

  setupBle();
  Serial.println("{\"status\":\"navi_beacon_ready\"}");
}

void loop() {
  updateHeartRate();
  if (hasMotion) {
    mpu.update();
  }

  const unsigned long now = millis();
  if (now - lastSerialMs >= SERIAL_INTERVAL_MS) {
    lastSerialMs = now;
    String payload = buildTelemetryJson();
    Serial.println(payload);
  }

  if (bleClientConnected && now - lastBleMs >= BLE_INTERVAL_MS) {
    lastBleMs = now;
    String payload = buildTelemetryJson();
    telemetryCharacteristic->setValue(payload.c_str());
    telemetryCharacteristic->notify();
  }
}

void setupBle() {
  BLEDevice::init(DEVICE_NAME);
  BLEServer *server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService *service = server->createService(SERVICE_UUID);
  telemetryCharacteristic = service->createCharacteristic(
    TELEMETRY_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  telemetryCharacteristic->addDescriptor(new BLE2902());
  telemetryCharacteristic->setValue("{\"status\":\"waiting\"}");
  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
}

void updateHeartRate() {
  if (!hasPpg) {
    return;
  }

  long irValue = ppg.getIR();
  if (irValue < 50000) {
    return;
  }

  if (checkForBeat(irValue)) {
    long delta = millis() - lastBeatMs;
    lastBeatMs = millis();
    float instantBpm = 60.0 / (delta / 1000.0);
    if (instantBpm > 35 && instantBpm < 220) {
      bpm = instantBpm;
      if (bpmSamples == 0) {
        bpmAverage = bpm;
      } else {
        bpmAverage = (bpmAverage * 0.8) + (bpm * 0.2);
      }
      bpmSamples = min<byte>(bpmSamples + 1, 25);
    }
  }
}

String buildTelemetryJson() {
  StaticJsonDocument<384> doc;
  doc["time"] = millis();
  doc["hr"] = bpmSamples > 0 ? round(bpmAverage) : 0;
  doc["temp"] = hasTemp ? tempSensor.readTempC() : 0;
  doc["lux"] = hasLight ? lightSensor.readLightLevel() : 0;

  float ax = hasMotion ? mpu.getAccX() : 0;
  float ay = hasMotion ? mpu.getAccY() : 0;
  float az = hasMotion ? mpu.getAccZ() : 0;
  float motion = sqrt((ax * ax) + (ay * ay) + ((az - 1.0) * (az - 1.0)));

  doc["ax"] = ax;
  doc["ay"] = ay;
  doc["az"] = az;
  doc["motion"] = motion;
  doc["activity"] = classifyActivity(motion);
  doc["battery"] = readBatteryPercent();
  doc["quality"] = bpmSamples > 0 ? min<int>(100, bpmSamples * 4) : 0;

  String output;
  serializeJson(doc, output);
  return output;
}

int classifyActivity(float motion) {
  if (motion < 0.08) return 0;  // still
  if (motion < 0.35) return 1;  // walking
  if (motion < 0.75) return 3;  // restless
  return 2;                     // running
}

int readBatteryPercent() {
  int raw = analogRead(BATTERY_ADC_PIN);
  if (raw <= 0) {
    return -1;
  }

  // Assumes a 2:1 voltage divider into GPIO34. Calibrate these values for your cell.
  float voltage = (raw / 4095.0) * 3.3 * 2.0;
  int percent = round((voltage - 3.3) * 100.0 / (4.2 - 3.3));
  return constrain(percent, 0, 100);
}
