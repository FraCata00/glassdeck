import Foundation
import IOKit

/// Minimal read-only client for the Apple System Management Controller.
///
/// The SMC is what knows about fans (and temperatures); it is reached through an
/// `AppleSMC` user client with a fixed request struct. Only reads are implemented
/// here — GlassDeck never writes to the SMC, so it can never change fan behaviour.
final class SMCService {
    /// The 32-byte payload every SMC response carries.
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    /// Mirrors `SMCParamStruct` from Apple's kernel extension; the layout is fixed
    /// and must stay byte-for-byte identical (80 bytes) or the driver rejects the call.
    private struct ParamStruct {
        var key: UInt32 = 0
        var version = Version()
        var pLimitData = PLimitData()
        var keyInfo = KeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private enum Selector {
        /// `kSMCHandleYPCEvent`, the only user-client method needed for reads.
        static let handleEvent: UInt32 = 2
        static let readKey: UInt8 = 5
        static let getKeyInfo: UInt8 = 9
    }

    private var connection: io_connect_t = 0

    /// `nil` when no SMC user client could be opened (virtual machines, future OSes).
    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else { return nil }
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    /// Reads a four-character SMC key and decodes it as a number.
    /// - Returns: `nil` when the key does not exist on this machine.
    func readNumber(_ key: String) -> Double? {
        guard let value = read(key) else { return nil }
        return Self.decode(type: value.type, bytes: value.bytes)
    }

    private func read(_ key: String) -> (type: String, bytes: [UInt8])? {
        var info = ParamStruct()
        info.key = Self.fourCharCode(key)
        info.data8 = Selector.getKeyInfo
        guard let metadata = call(info) else { return nil }

        var request = ParamStruct()
        request.key = info.key
        request.keyInfo.dataSize = metadata.keyInfo.dataSize
        request.data8 = Selector.readKey
        guard let response = call(request) else { return nil }

        let payload = withUnsafeBytes(of: response.bytes) { Array($0) }
        return (
            Self.string(from: metadata.keyInfo.dataType),
            Array(payload.prefix(Int(metadata.keyInfo.dataSize)))
        )
    }

    private func call(_ input: ParamStruct) -> ParamStruct? {
        var input = input
        var output = ParamStruct()
        var outputSize = MemoryLayout<ParamStruct>.stride

        let status = IOConnectCallStructMethod(
            connection,
            Selector.handleEvent,
            &input,
            MemoryLayout<ParamStruct>.stride,
            &output,
            &outputSize
        )
        // `result != 0` means the key is unknown on this hardware, which is normal.
        guard status == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    /// SMC values are typed by a four-character code; these are the numeric types
    /// fan and temperature keys use across Intel and Apple silicon Macs.
    private static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type.trimmingCharacters(in: .whitespaces) {
        case "flt":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(
                UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3])
            )
        default:
            return nil
        }
    }

    private static func fourCharCode(_ key: String) -> UInt32 {
        key.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff), UInt8(code & 0xff),
        ]
        return String(decoding: bytes, as: UTF8.self)
    }
}
