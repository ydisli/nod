#!/usr/bin/env swift
// Sends a command to a Nod started with NOD_DEV=1. See Sources/Nod/App/DevHooks.swift.
//
//   scripts/devctl.swift settings clicking
//   scripts/devctl.swift snapshot /tmp/nod-shots
import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !command.isEmpty else {
    print("usage: devctl.swift <settings PANE|popover|onboarding|palette|calibrate|enable|disable|snapshot DIR|quit>")
    exit(1)
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.slipperysign.nod.dev"), object: command, userInfo: nil, deliverImmediately: true)
