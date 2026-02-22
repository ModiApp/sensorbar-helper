# SensorBar Helper

Open-source privileged XPC helper for reading macOS SMC sensor data.

This is the helper daemon component of [SensorBar](https://sensorbar.app), a macOS menu bar system monitor. It runs as a LaunchDaemon with root privileges to access the System Management Controller (SMC) via IOKit, then serves sensor data to the sandboxed SensorBar app over XPC.

## What It Does

- Reads hardware sensor data directly from the SMC via IOKit
- Exposes temperature, fan speed, voltage, and power readings
- Communicates with the main SensorBar app via a secure XPC Mach service

## Sensors Supported

- **Temperature** — CPU cores (Intel & Apple Silicon), GPU, memory, SSD, ambient, battery
- **Fan Speed** — Current RPM, min/max for all fans
- **Voltage** — CPU, GPU, memory, battery, DC input
- **Power** — CPU package/cores, GPU, battery, system total

## Building

```bash
swift build
```

Requires macOS 13+ and Xcode 15+.

## Installation

The helper is normally installed automatically by SensorBar. For manual installation:

1. Build the helper: `swift build -c release`
2. Copy the binary to `/Library/PrivilegedHelperTools/com.ikeybenz.sensorbar.helper`
3. Install the LaunchDaemon plist to `/Library/LaunchDaemons/com.ikeybenz.sensorbar.helper.plist`

## Architecture

- **`main.swift`** — Entry point; sets up the XPC listener on the Mach service
- **`SMCReader.swift`** — Low-level SMC access via IOKit (based on patterns from [exelban/stats](https://github.com/exelban/stats), MIT License)
- **`HelperDelegate.swift`** — XPC delegate and protocol implementation
- **`SensorBarHelperProtocol.swift`** — Shared XPC protocol definition

## License

MIT
