// SensorBarHelperProtocol.swift
// Shared XPC protocol between SensorBar (sandboxed) and SensorBarHelper (privileged)

import Foundation

/// Mach service name for the XPC connection
public let sensorBarHelperMachServiceName = "com.ikeybenz.sensorbar.helper"

/// Sensor type categories
@objc public enum SensorType: Int {
    case temperature = 0
    case fan = 1
    case voltage = 2
    case power = 3
    case current = 4
}

/// XPC protocol exposed by the helper daemon
@objc public protocol SensorBarHelperProtocol {
    /// Returns all sensor readings as an array of dictionaries.
    /// Each dict contains: "key" (String), "name" (String), "type" (Int/SensorType raw),
    /// "value" (Double), "unit" (String)
    func getAllSensors(reply: @escaping ([[String: Any]]) -> Void)

    /// Returns only temperature sensors
    func getTemperatures(reply: @escaping ([[String: Any]]) -> Void)

    /// Returns only fan speed sensors
    func getFanSpeeds(reply: @escaping ([[String: Any]]) -> Void)

    /// Returns only voltage sensors
    func getVoltages(reply: @escaping ([[String: Any]]) -> Void)

    /// Returns only power sensors
    func getPower(reply: @escaping ([[String: Any]]) -> Void)

    /// Ping to check if the helper is alive
    func ping(reply: @escaping (Bool) -> Void)

    /// Get helper version
    func getVersion(reply: @escaping (String) -> Void)
}
