import Foundation

/// Apple delivers its reports gzipped. Foundation inflates raw DEFLATE, so the gzip wrapper
/// (header, optional fields, and the 8-byte trailer) is taken off first. RFC 1952.
public enum Gzip {
    public static func unzip(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return data }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 { offset += 2 + Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }
        if flags & 0x08 != 0 { while bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x10 != 0 { while bytes[offset] != 0 { offset += 1 }; offset += 1 }
        if flags & 0x02 != 0 { offset += 2 }
        let deflated = Data(bytes[offset..<(bytes.count - 8)])
        return try (deflated as NSData).decompressed(using: .zlib) as Data
    }
}
