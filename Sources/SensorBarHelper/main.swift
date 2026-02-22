// main.swift
// SensorBarHelper — Privileged XPC daemon for reading SMC sensor data
// Runs as a LaunchDaemon and serves sensor data to the sandboxed SensorBar app

import Foundation
import SensorBarShared

NSLog("SensorBarHelper: Starting (pid: %d)", ProcessInfo.processInfo.processIdentifier)

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: sensorBarHelperMachServiceName)
listener.delegate = delegate
listener.resume()

NSLog("SensorBarHelper: Listening on %@", sensorBarHelperMachServiceName)

// Run forever
RunLoop.current.run()
