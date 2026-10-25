// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import IOKit.graphics
import IOKit.i2c

#if arch(x86_64)
/// DDC/CI on Intel Macs. Apple Silicon reaches a monitor through its
/// DCPAVServiceProxy; an Intel GPU exposes the same I2C bus through the
/// framebuffer driving the display, with the public IOI2C interface. `read`
/// and `write` take the arguments of IOAVServiceReadI2C/WriteI2C, so the
/// packets, pacing, probing and channel verdicts above them are shared.
enum IntelDDC {
    /// The I2C endpoint handed around as the service of an external display.
    final class Channel {
        let framebuffer: io_service_t

        init(_ framebuffer: io_service_t) {
            IOObjectRetain(framebuffer)
            self.framebuffer = framebuffer
        }

        deinit { IOObjectRelease(framebuffer) }
    }

    /// Every external display with the framebuffer driving it. The IODisplay's
    /// registry path is what CoreDisplay reports as the display's location,
    /// which pairs the two on its own.
    static func externalServices() -> [(identity: BrightnessSupport.ServiceIdentity, channel: Channel)] {
        var results: [(identity: BrightnessSupport.ServiceIdentity, channel: Channel)] = []
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOFramebuffer"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var ordinal = 0
        while case let framebuffer = IOIteratorNext(iterator), framebuffer != 0 {
            defer { IOObjectRelease(framebuffer) }
            ordinal += 1
            guard let display = attachedDisplay(of: framebuffer) else { continue }
            defer { IOObjectRelease(display) }
            // The built-in panel's backlight is DisplayServices' job.
            guard IOObjectConformsTo(display, "AppleBacklightDisplay") == 0 else { continue }
            var identity = BrightnessSupport.ServiceIdentity()
            identity.ordinal = ordinal
            var path = [CChar](repeating: 0, count: 512)
            if IORegistryEntryGetPath(display, kIOServicePlane, &path) == KERN_SUCCESS {
                identity.ioDisplayLocation = String(cString: path)
            }
            if let names = IORegistryEntryCreateCFProperty(display, "DisplayProductName" as CFString,
                                                           kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: String] {
                identity.productName = names["en_US"] ?? names.first?.value ?? ""
            }
            results.append((identity, Channel(framebuffer)))
        }
        return results
    }

    /// framebuffer → IODisplayConnect → IODisplay, retained for the caller.
    private static func attachedDisplay(of framebuffer: io_service_t) -> io_service_t? {
        var connects = io_iterator_t()
        guard IORegistryEntryGetChildIterator(framebuffer, kIOServicePlane, &connects) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(connects) }
        while case let connect = IOIteratorNext(connects), connect != 0 {
            defer { IOObjectRelease(connect) }
            guard IOObjectConformsTo(connect, "IODisplayConnect") != 0 else { continue }
            var displays = io_iterator_t()
            guard IORegistryEntryGetChildIterator(connect, kIOServicePlane, &displays) == KERN_SUCCESS
            else { continue }
            defer { IOObjectRelease(displays) }
            while case let display = IOIteratorNext(displays), display != 0 {
                if IOObjectConformsTo(display, "IODisplay") != 0 { return display }
                IOObjectRelease(display)
            }
        }
        return nil
    }

    /// IOAVService takes the 7-bit chip address and sends the sub-address
    /// ahead of the bytes; IOI2C takes the 8-bit bus address and the whole
    /// message.
    static func write(_ service: CFTypeRef, chipAddress: UInt32, dataAddress: UInt32,
                      bytes: UnsafeMutableRawPointer, count: UInt32) -> IOReturn {
        guard let channel = service as? Channel else { return kIOReturnBadArgument }
        var message = [UInt8(truncatingIfNeeded: dataAddress)]
            + Array(UnsafeRawBufferPointer(start: bytes, count: Int(count)))
        return message.withUnsafeMutableBytes { buffer in
            var request = IOI2CRequest()
            request.sendAddress = chipAddress << 1
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBuffer = vm_address_t(UInt(bitPattern: buffer.baseAddress))
            request.sendBytes = UInt32(buffer.count)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            return send(&request, on: channel)
        }
    }

    /// The reply arrives as IOAVServiceReadI2C returns it: the monitor's
    /// source address first, then the DDC/CI reply and its checksum.
    static func read(_ service: CFTypeRef, chipAddress: UInt32,
                     bytes: UnsafeMutableRawPointer, count: UInt32) -> IOReturn {
        guard let channel = service as? Channel else { return kIOReturnBadArgument }
        var request = IOI2CRequest()
        request.sendTransactionType = IOOptionBits(kIOI2CNoTransactionType)
        request.replyAddress = (chipAddress << 1) | 1
        request.replyTransactionType = IOOptionBits(kIOI2CDDCciReplyTransactionType)
        request.replyBuffer = vm_address_t(UInt(bitPattern: bytes))
        request.replyBytes = count
        return send(&request, on: channel)
    }

    /// A transaction counts only when the bus itself reports success.
    private static func send(_ request: inout IOI2CRequest, on channel: Channel) -> IOReturn {
        var buses: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(channel.framebuffer, &buses) == KERN_SUCCESS
        else { return kIOReturnNotFound }
        for bus in 0..<buses {
            var interface: io_service_t = 0
            guard IOFBCopyI2CInterfaceForBus(channel.framebuffer, IOOptionBits(bus),
                                             &interface) == KERN_SUCCESS else { continue }
            var connect: IOI2CConnectRef?
            let opened = IOI2CInterfaceOpen(interface, 0, &connect)
            IOObjectRelease(interface)
            guard opened == KERN_SUCCESS, let connect else { continue }
            defer { IOI2CInterfaceClose(connect, 0) }
            let status = IOI2CSendRequest(connect, 0, &request)
            return status == KERN_SUCCESS ? request.result : status
        }
        return kIOReturnNotFound
    }
}
#endif
