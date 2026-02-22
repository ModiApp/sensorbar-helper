// HelperDelegate.swift
// XPC service delegate and protocol implementation for SensorBarHelper

import Foundation
import SensorBarShared

// MARK: - XPC Service Provider

final class SensorBarHelperProvider: NSObject, SensorBarHelperProtocol {
    private let smcReader = SMCReader()
    private let helperVersion = "1.0.0"

    func getAllSensors(reply: @escaping ([[String: Any]]) -> Void) {
        let sensors = smcReader.getAllSensors()
        reply(sensors.map { $0.toDictionary() })
    }

    func getTemperatures(reply: @escaping ([[String: Any]]) -> Void) {
        let sensors = smcReader.getTemperatures()
        reply(sensors.map { $0.toDictionary() })
    }

    func getFanSpeeds(reply: @escaping ([[String: Any]]) -> Void) {
        let sensors = smcReader.getFanSpeeds()
        reply(sensors.map { $0.toDictionary() })
    }

    func getVoltages(reply: @escaping ([[String: Any]]) -> Void) {
        let sensors = smcReader.getVoltages()
        reply(sensors.map { $0.toDictionary() })
    }

    func getPower(reply: @escaping ([[String: Any]]) -> Void) {
        let sensors = smcReader.getPower()
        reply(sensors.map { $0.toDictionary() })
    }

    func ping(reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func getVersion(reply: @escaping (String) -> Void) {
        reply(helperVersion)
    }
}

// MARK: - XPC Listener Delegate

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let interface = NSXPCInterface(with: SensorBarHelperProtocol.self)

        let allowedClasses = NSSet(array: [
            NSArray.self,
            NSDictionary.self,
            NSString.self,
            NSNumber.self,
        ]) as! Set<AnyHashable>

        // Set allowed classes for the reply blocks that return [[String: Any]]
        let selectors: [Selector] = [
            #selector(SensorBarHelperProtocol.getAllSensors(reply:)),
            #selector(SensorBarHelperProtocol.getTemperatures(reply:)),
            #selector(SensorBarHelperProtocol.getFanSpeeds(reply:)),
            #selector(SensorBarHelperProtocol.getVoltages(reply:)),
            #selector(SensorBarHelperProtocol.getPower(reply:)),
        ]

        for selector in selectors {
            interface.setClasses(allowedClasses,
                                 for: selector,
                                 argumentIndex: 0,
                                 ofReply: true)
        }

        newConnection.exportedInterface = interface
        newConnection.exportedObject = SensorBarHelperProvider()

        newConnection.invalidationHandler = {
            NSLog("SensorBarHelper: Client connection invalidated")
        }

        newConnection.resume()
        NSLog("SensorBarHelper: Accepted new client connection (pid: %d)", newConnection.processIdentifier)
        return true
    }
}
