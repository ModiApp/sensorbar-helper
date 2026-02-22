// SMCReader.swift
// Low-level SMC access via IOKit for reading hardware sensors
// Based on patterns from exelban/stats (MIT License)

import Foundation
import IOKit
import SensorBarShared

// MARK: - SMC Constants

private let KERNEL_INDEX_SMC: UInt32 = 2
private let SMC_CMD_READ_KEYINFO: UInt8 = 9
private let SMC_CMD_READ_KEY: UInt8 = 5
private let SMC_CMD_READ_INDEX: UInt8 = 8

// MARK: - SMC Data Structures

struct SMCKeyData {
    struct vers_t {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct pLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    struct keyInfo_t {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    var key: UInt32 = 0
    var vers: vers_t = vers_t()
    var pLimitData: pLimitData = pLimitData()
    var keyInfo: keyInfo_t = keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

// MARK: - Sensor Reading Result

struct SensorReading {
    let key: String
    let name: String
    let type: SensorType
    let value: Double
    let unit: String

    func toDictionary() -> [String: Any] {
        return [
            "key": key,
            "name": name,
            "type": type.rawValue,
            "value": value,
            "unit": unit
        ]
    }
}

// MARK: - Known Sensor Keys

/// Well-known SMC keys with human-readable names
private let knownTemperatureKeys: [(key: String, name: String)] = [
    // CPU - Intel
    ("TC0P", "CPU Proximity"),
    ("TC0E", "CPU Core 0"),
    ("TC0D", "CPU Die"),
    ("TC1C", "CPU Core 1"),
    ("TC2C", "CPU Core 2"),
    ("TC3C", "CPU Core 3"),
    ("TC4C", "CPU Core 4"),
    ("TC5C", "CPU Core 5"),
    ("TC6C", "CPU Core 6"),
    ("TC7C", "CPU Core 7"),
    ("TC8C", "CPU Core 8"),
    ("TCXC", "CPU Core Max"),
    // CPU - Apple Silicon
    ("Tp09", "CPU Efficiency Core 1"),
    ("Tp0T", "CPU Efficiency Core 2"),
    ("Tp01", "CPU Performance Core 1"),
    ("Tp05", "CPU Performance Core 2"),
    ("Tp0D", "CPU Performance Core 3"),
    ("Tp0H", "CPU Performance Core 4"),
    ("Tp0L", "CPU Performance Core 5"),
    ("Tp0P", "CPU Performance Core 6"),
    ("Tp0X", "CPU Performance Core 7"),
    ("Tp0b", "CPU Performance Core 8"),
    // GPU
    ("TG0P", "GPU Proximity"),
    ("TG0D", "GPU Die"),
    ("Tg05", "GPU Core 1"),
    ("Tg0D", "GPU Core 2"),
    ("Tg0L", "GPU Core 3"),
    ("Tg0T", "GPU Core 4"),
    // Memory
    ("Tm02", "Memory Module 1"),
    ("Tm06", "Memory Module 2"),
    ("TM0P", "Memory Proximity"),
    // Storage
    ("TH0A", "SSD 1"),
    ("TH0B", "SSD 2"),
    ("TH0x", "SSD"),
    // Ambient/Enclosure
    ("TA0P", "Ambient 1"),
    ("TA1P", "Ambient 2"),
    ("TaLP", "Airflow Left"),
    ("TaRP", "Airflow Right"),
    ("TB0T", "Battery"),
    ("TB1T", "Battery 1"),
    ("TB2T", "Battery 2"),
    ("Ts0P", "Palm Rest Left"),
    ("Ts1P", "Palm Rest Right"),
    // Thunderbolt
    ("TI0P", "Thunderbolt 1"),
    ("TI1P", "Thunderbolt 2"),
    // Power Supply
    ("Tp0C", "Power Supply"),
    ("TPCD", "Platform Controller"),
]

private let knownVoltageKeys: [(key: String, name: String)] = [
    ("VC0C", "CPU Core"),
    ("VCAC", "CPU HIA"),
    ("VCTC", "CPU GFX"),
    ("VG0C", "GPU Core"),
    ("VM0R", "Memory"),
    ("VN1R", "12V Rail"),
    ("VP0R", "12V Mainboard"),
    ("VD0R", "DC In"),
    ("VD2R", "DC In S0"),
    ("VBAT", "Battery"),
]

private let knownPowerKeys: [(key: String, name: String)] = [
    ("PC0C", "CPU Core"),
    ("PCAM", "CPU HIA"),
    ("PCPC", "CPU Package"),
    ("PCPG", "CPU GFX"),
    ("PCPT", "CPU Total"),
    ("PC0R", "CPU Rail"),
    ("PC1R", "CPU DRAM"),
    ("PCGC", "GPU Intel"),
    ("PG0R", "GPU Rail"),
    ("PPBR", "Battery"),
    ("PDTR", "DC In"),
    ("PSTR", "System Total"),
]

// MARK: - SMCReader

final class SMCReader {
    private var connection: io_connect_t = 0
    private var isConnected = false

    init() {
        open()
    }

    deinit {
        close()
    }

    // MARK: - Connection Management

    func open() {
        guard !isConnected else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            log("SMCReader: AppleSMC service not found")
            return
        }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        IOObjectRelease(service)
        if result == kIOReturnSuccess {
            isConnected = true
            log("SMCReader: Connected to AppleSMC")
        } else {
            log("SMCReader: Failed to open AppleSMC, error: \(result)")
        }
    }

    func close() {
        if isConnected {
            IOServiceClose(connection)
            isConnected = false
        }
    }

    // MARK: - Public API

    func getAllSensors() -> [SensorReading] {
        guard isConnected else { return [] }
        var results: [SensorReading] = []
        results.append(contentsOf: getTemperatures())
        results.append(contentsOf: getFanSpeeds())
        results.append(contentsOf: getVoltages())
        results.append(contentsOf: getPower())
        return results
    }

    func getTemperatures() -> [SensorReading] {
        guard isConnected else { return [] }
        var results: [SensorReading] = []
        for (key, name) in knownTemperatureKeys {
            if let val = readValue(key), val > 0 && val < 150 {
                results.append(SensorReading(key: key, name: name, type: .temperature, value: val, unit: "°C"))
            }
        }
        return results
    }

    func getFanSpeeds() -> [SensorReading] {
        guard isConnected else { return [] }
        var results: [SensorReading] = []

        // Get fan count
        let fanCount: Int
        if let count = readValue("FNum") {
            fanCount = Int(count)
        } else {
            fanCount = 2 // default guess
        }

        for i in 0..<fanCount {
            let actualKey = "F\(i)Ac"
            let minKey = "F\(i)Mn"
            let maxKey = "F\(i)Mx"

            if let actual = readValue(actualKey), actual >= 0 {
                results.append(SensorReading(key: actualKey, name: "Fan \(i)", type: .fan, value: actual, unit: "RPM"))
            }
            if let min = readValue(minKey), min >= 0 {
                results.append(SensorReading(key: minKey, name: "Fan \(i) Min", type: .fan, value: min, unit: "RPM"))
            }
            if let max = readValue(maxKey), max >= 0 {
                results.append(SensorReading(key: maxKey, name: "Fan \(i) Max", type: .fan, value: max, unit: "RPM"))
            }
        }
        return results
    }

    func getVoltages() -> [SensorReading] {
        guard isConnected else { return [] }
        var results: [SensorReading] = []
        for (key, name) in knownVoltageKeys {
            if let val = readValue(key), val > 0 {
                results.append(SensorReading(key: key, name: name, type: .voltage, value: val, unit: "V"))
            }
        }
        return results
    }

    func getPower() -> [SensorReading] {
        guard isConnected else { return [] }
        var results: [SensorReading] = []
        for (key, name) in knownPowerKeys {
            if let val = readValue(key), val > 0 {
                results.append(SensorReading(key: key, name: name, type: .power, value: val, unit: "W"))
            }
        }
        return results
    }

    // MARK: - Low-level SMC Access

    private func readValue(_ keyStr: String) -> Double? {
        guard isConnected else { return nil }

        // Step 1: Get key info (data type + size)
        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = fourCharCode(keyStr)
        input.data8 = SMC_CMD_READ_KEYINFO

        guard callSMC(&input, &output) else { return nil }

        let dataType = output.keyInfo.dataType
        let dataSize = output.keyInfo.dataSize
        guard dataSize > 0 && dataSize <= 32 else { return nil }

        // Step 2: Read the value
        input = SMCKeyData()
        input.key = fourCharCode(keyStr)
        input.keyInfo.dataSize = dataSize
        input.data8 = SMC_CMD_READ_KEY

        guard callSMC(&input, &output) else { return nil }

        // Step 3: Parse based on type
        return parseValue(output.bytes, dataType: dataType, dataSize: dataSize)
    }

    private func callSMC(_ input: inout SMCKeyData, _ output: inout SMCKeyData) -> Bool {
        var inputSize = MemoryLayout<SMCKeyData>.stride
        var outputSize = MemoryLayout<SMCKeyData>.stride
        let result = IOConnectCallStructMethod(
            connection, KERNEL_INDEX_SMC,
            &input, inputSize,
            &output, &outputSize
        )
        return result == kIOReturnSuccess
    }

    private func parseValue(_ bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                                       UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
                             dataType: UInt32, dataSize: UInt32) -> Double? {
        let typeStr = typeToString(dataType)

        switch typeStr {
        case "flt " where dataSize >= 4:
            let raw = (UInt32(bytes.0) << 24) | (UInt32(bytes.1) << 16) | (UInt32(bytes.2) << 8) | UInt32(bytes.3)
            let val = Double(Float(bitPattern: raw))
            return val.isFinite ? val : nil

        case "sp78" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 256.0

        case "sp87" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 256.0

        case "sp4b" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 2048.0

        case "sp5a" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 1024.0

        case "sp69" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 512.0

        case "sp96" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 64.0

        case "spa5" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 32.0

        case "spb4" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw) / 16.0

        case "spf0" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw)

        case "ui8 " where dataSize >= 1:
            return Double(bytes.0)

        case "ui16" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw)

        case "ui32" where dataSize >= 4:
            let raw = (UInt32(bytes.0) << 24) | (UInt32(bytes.1) << 16) | (UInt32(bytes.2) << 8) | UInt32(bytes.3)
            return Double(raw)

        case "si8 " where dataSize >= 1:
            return Double(Int8(bitPattern: bytes.0))

        case "si16" where dataSize >= 2:
            let raw = (Int16(bytes.0) << 8) | Int16(bytes.1)
            return Double(raw)

        case "fp1f" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw) / 32768.0

        case "fp2e" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw) / 16384.0

        case "fp4c" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw) / 4096.0

        case "fp6a" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw) / 1024.0

        case "fp88" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw) / 256.0

        case "fpe2" where dataSize >= 2:
            let raw = (UInt16(bytes.0) << 8) | UInt16(bytes.1)
            return Double(raw) / 4.0

        default:
            return nil
        }
    }

    private func fourCharCode(_ s: String) -> UInt32 {
        var result: UInt32 = 0
        for char in s.utf8.prefix(4) {
            result = (result << 8) | UInt32(char)
        }
        return result
    }

    private func typeToString(_ type: UInt32) -> String {
        let chars = [
            Character(UnicodeScalar((type >> 24) & 0xFF)!),
            Character(UnicodeScalar((type >> 16) & 0xFF)!),
            Character(UnicodeScalar((type >> 8) & 0xFF)!),
            Character(UnicodeScalar(type & 0xFF)!)
        ]
        return String(chars)
    }
}

// MARK: - Logging

private func log(_ message: String) {
    NSLog("SensorBarHelper: %@", message)
}
