# Navi Beacon ESP32 Firmware

Upload `navi_beacon.ino` to an ESP32-WROOM from Arduino IDE or Arduino CLI.

Default wiring assumes all sensors share I2C:

| ESP32-WROOM | Sensor pins |
| --- | --- |
| `3V3` | `VIN` / `VCC` |
| `GND` | `GND` |
| `GPIO21` | `SDA` |
| `GPIO22` | `SCL` |
| `GPIO34` | optional battery divider |

Required Arduino libraries:

- `ArduinoJson`
- `ESP32 BLE Arduino`
- `SparkFun MAX3010x Pulse and Proximity Sensor Library`
- `Adafruit MCP9808 Library`
- `Adafruit BH1750`
- `MPU6050_light`

The sketch prints one JSON record per second over Serial and notifies the Navi
Flutter app every five seconds over BLE using:

- Service UUID: `6e400001-b5a3-f393-e0a9-e50e24dcca9e`
- Telemetry characteristic UUID: `6e400003-b5a3-f393-e0a9-e50e24dcca9e`

Telemetry example:

```json
{"time":12345,"hr":72,"temp":36.4,"lux":220,"ax":0.12,"ay":-0.03,"az":0.98,"motion":0.14,"activity":1,"battery":84,"quality":80}
```

Activity values are `0 = still`, `1 = walking`, `2 = running`, and
`3 = restless`.
