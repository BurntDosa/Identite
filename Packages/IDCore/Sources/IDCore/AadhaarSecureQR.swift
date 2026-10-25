import Foundation
import Compression

/// Demographic extraction only; this does not authenticate UIDAI's signature.
public struct AadhaarSecureQR: Sendable, Equatable {
    public let fields: [FieldKey: String]
    public let last4: String

    public static func decode(_ text: String) -> Self? {
        // A numeric QR cannot exceed 7,089 digits. Bound conversion and inflated image data.
        let digits = Array(text.utf8)
        guard !digits.isEmpty, digits.count <= 7_089, digits.allSatisfy({ (48...57).contains($0) }) else { return nil }
        var bytes: [UInt8] = [0]
        for digit in digits {
            var carry = Int(digit - 48)
            for index in bytes.indices {
                carry += Int(bytes[index]) * 10
                bytes[index] = UInt8(carry & 255)
                carry >>= 8
            }
            while carry > 0 { bytes.append(UInt8(carry & 255)); carry >>= 8 }
        }
        guard let data = gunzip(Array(bytes.reversed())) else { return nil }
        // Read only the fixed demographic prefix: binary photos/signatures can contain 0xFF.
        var cursor = 0
        func next() -> String? {
            guard cursor < data.count, let end = data[cursor...].firstIndex(of: 255),
                  let value = String(bytes: data[cursor..<end], encoding: .utf8) else { return nil }
            cursor = end + 1
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = next(), let indicator = first == "V2" ? next() : first,
              ["0", "1", "2", "3"].contains(indicator) else { return nil }
        var values: [String] = []
        for _ in 0..<15 { guard let value = next() else { return nil }; values.append(value) }
        let reference = values[0]
        guard reference.count == 21, reference.utf8.allSatisfy({ (48...57).contains($0) }), !values[1].isEmpty,
              let gender = ["M": "Male", "F": "Female", "T": "Transgender"][values[3]] else { return nil }
        var fields: [FieldKey: String] = [.name: values[1], .gender: gender]
        let date = DateFormatter()
        date.locale = Locale(identifier: "en_US_POSIX")
        date.calendar = Calendar(identifier: .gregorian)
        date.timeZone = TimeZone(secondsFromGMT: 0)
        date.dateFormat = "dd-MM-yyyy"
        date.isLenient = false
        if let birth = date.date(from: values[2]), date.string(from: birth) == values[2] {
            date.dateFormat = "yyyy-MM-dd"
            fields[.dateOfBirth] = date.string(from: birth)
        }
        // UIDAI wire order: care-of, district, landmark, house, location, PIN, PO, state, street, subdistrict, VTC.
        let address = [4, 7, 12, 6, 8, 14, 10, 13, 5, 11, 9].map { values[$0] }.filter { !$0.isEmpty }
        if !address.isEmpty { fields[.address] = address.joined(separator: ", ") }
        return Self(fields: fields, last4: String(reference.prefix(4)))
    }

    /// QR demographics win; a full OCR number is retained only when its suffix agrees.
    public func merging(ocr: [FieldKey: String]) -> [FieldKey: String] {
        var result = ocr.merging(fields) { _, qr in qr }
        if let number = result[.aadhaarNumber], number.count != 12 || !number.hasSuffix(last4) {
            result[.aadhaarNumber] = nil
        }
        return result
    }

    private static func gunzip(_ bytes: [UInt8]) -> [UInt8]? {
        guard bytes.count >= 18, bytes[0...2] == [0x1f, 0x8b, 8], bytes[3] & 0xe0 == 0 else { return nil }
        let end = bytes.count - 8
        var start = 10
        let flags = bytes[3]
        if flags & 4 != 0 {
            guard start + 2 <= end else { return nil }
            let length = Int(bytes[start]) | Int(bytes[start + 1]) << 8
            start += 2 + length
        }
        for flag: UInt8 in [8, 16] where flags & flag != 0 {
            guard start < end, let zero = bytes[start..<end].firstIndex(of: 0) else { return nil }
            start = zero + 1
        }
        if flags & 2 != 0 {
            guard start + 2 <= end else { return nil }
            let expected = UInt32(bytes[start]) | UInt32(bytes[start + 1]) << 8
            guard crc32(Array(bytes[..<start])) & 0xffff == expected else { return nil }
            start += 2
        }
        guard start < end else { return nil }
        func word(_ offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
        }
        let size = Int(word(end + 4))
        guard size > 0, size <= 262_144 else { return nil }
        var output = [UInt8](repeating: 0, count: size + 1)
        let count = bytes.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, size + 1, source.baseAddress! + start,
                                          end - start, nil, COMPRESSION_ZLIB)
            }
        }
        guard count == size else { return nil }
        output.removeLast()
        guard crc32(output) == word(end) else { return nil }
        return output
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = .max
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
}
