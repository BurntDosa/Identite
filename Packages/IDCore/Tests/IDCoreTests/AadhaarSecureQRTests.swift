import Foundation
import Compression
import Testing
@testable import IDCore

struct AadhaarSecureQRTests {
    @Test(arguments: [false, true]) func demographics(v2: Bool) throws {
        let qr = try #require(AadhaarSecureQR.decode(try fixture(v2: v2)))
        #expect(qr.last4 == "2346")
        #expect(qr.fields[.name] == "Fake Person")
        #expect(qr.fields[.dateOfBirth] == "1990-03-02")
        #expect(qr.fields[.gender] == "Transgender")
        #expect(qr.fields[.address] == "C/O Fake Parent, 12, Fake Street, Fake Area, Fake Town, Fake PO, Fake Subdistrict, Fake District, Fake State, 560001")
        #expect(qr.merging(ocr: [.name: "OCR error", .aadhaarNumber: "234123412346"])[.name] == "Fake Person")
        #expect(qr.merging(ocr: [.aadhaarNumber: "234123412346"])[.aadhaarNumber] == "234123412346")
        #expect(qr.merging(ocr: [.aadhaarNumber: "234123412347"])[.aadhaarNumber] == nil)
        #expect(qr.merging(ocr: [:])[.aadhaarNumber] == nil)
    }
    @Test func rejectsGarbage() throws {
        for value in ["", "abc", "12345", "-123", "１２３", String(repeating: "9", count: 7090)] {
            #expect(AadhaarSecureQR.decode(value) == nil)
        }
        #expect(AadhaarSecureQR.decode(try fixture(v2: true, corrupt: true)) == nil)
        #expect(AadhaarSecureQR.decode(try fixture(v2: true, version: "V9")) == nil)
    }
    private func fixture(v2: Bool, corrupt: Bool = false, version: String = "V2") throws -> String {
        let fields = (v2 ? [version] : []) + ["0", "234622102026120000000", "Fake Person", "02-03-1990", "T",
            "C/O Fake Parent", "Fake District", "", "12", "Fake Area", "560001", "Fake PO", "Fake State", "Fake Street", "Fake Subdistrict", "Fake Town"]
        var data = fields.flatMap { Array($0.utf8) + [UInt8(255)] }
        // Delimiter bytes and non-UTF8 in the fake photo/signature must not be parsed as text.
        data += [0, 255, 128, 217] + Array(repeating: UInt8(128), count: 256)
        var compressed = [UInt8](repeating: 0, count: data.count * 2)
        let count = data.withUnsafeBufferPointer { input in
            compressed.withUnsafeMutableBufferPointer { output in
                compression_encode_buffer(output.baseAddress!, output.count, input.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        #expect(count > 0)
        var gzip: [UInt8] = [31, 139, 8, 0, 0, 0, 0, 0, 0, 3] + compressed.prefix(count)
        var crc: UInt32 = .max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320 }
        }
        for word in [~crc ^ (corrupt ? 1 : 0), UInt32(data.count)] {
            gzip += (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
        }
        // Independent inverse: multiply decimal digits by 256 for each big-endian byte.
        var decimal = [0]
        for byte in gzip {
            var carry = Int(byte)
            for index in decimal.indices {
                let value = decimal[index] * 256 + carry
                decimal[index] = value % 10; carry = value / 10
            }
            while carry > 0 { decimal.append(carry % 10); carry /= 10 }
        }
        return decimal.reversed().map(String.init).joined()
    }
}
