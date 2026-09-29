import Foundation

/// Plain text of a legacy binary Word 97–2003 document (`.doc`) — iOS has no
/// system API for this format (`NSAttributedString`'s `.docFormat` reader is
/// macOS-only), so this reads it directly per Microsoft's published specs:
///
/// 1. [MS-CFB] Compound File Binary: the `.doc` is a small FAT file system;
///    find the `WordDocument` stream and the table stream (`0Table`/`1Table`).
/// 2. [MS-DOC] File Information Block at the start of `WordDocument`: where
///    the piece table (`Clx`) is and how many characters the main text has.
/// 3. The piece table maps character runs to byte ranges in `WordDocument`,
///    each either "compressed" (1 byte/char, Windows-1252) or UTF-16LE.
/// 4. Word's control characters become plain whitespace; field instructions
///    are dropped while their visible results (e.g. a date) are kept.
///
/// Only the main document text is returned (no headers, footnotes or
/// comments) — that's where an invitation's date, place and title live.
/// Encrypted documents are rejected. Pure Foundation, no UI or actor needs.
nonisolated enum WordDocTextExtractor {
    enum ExtractionError: Error, Equatable {
        case notACompoundFile
        case notAWordDocument
        case encrypted
        case malformed
    }

    static func text(fromFileAt url: URL) throws -> String {
        try text(from: Data(contentsOf: url))
    }

    static func text(from data: Data) throws -> String {
        let file = try CompoundFile(bytes: [UInt8](data))
        guard let wordDocument = try file.stream(named: "WordDocument") else {
            throw ExtractionError.notAWordDocument
        }
        let fib = try FileInformationBlock(wordDocument)
        guard !fib.isEncrypted else { throw ExtractionError.encrypted }
        guard let table = try file.stream(named: fib.usesTable1 ? "1Table" : "0Table") else {
            throw ExtractionError.malformed
        }
        let pieces = try Piece.table(in: table, offset: fib.clxOffset, length: fib.clxLength)
        let raw = try decode(pieces, from: wordDocument, characterCount: fib.mainTextLength)
        return plainText(fromWordCharacters: raw)
    }

    // MARK: - Piece table → characters

    private static func decode(_ pieces: [Piece], from wordDocument: [UInt8], characterCount: Int) throws -> [UInt16] {
        var characters: [UInt16] = []
        characters.reserveCapacity(characterCount)
        for piece in pieces where piece.cpStart < characterCount {
            let count = min(piece.cpEnd, characterCount) - piece.cpStart
            guard count > 0 else { continue }
            if piece.isCompressed {
                let start = piece.fileOffset / 2
                guard start >= 0, start + count <= wordDocument.count else { throw ExtractionError.malformed }
                let bytes = Array(wordDocument[start..<(start + count)])
                guard let string = String(bytes: bytes, encoding: .windowsCP1252) else { throw ExtractionError.malformed }
                characters.append(contentsOf: string.utf16)
            } else {
                let start = piece.fileOffset
                guard start >= 0, start + count * 2 <= wordDocument.count else { throw ExtractionError.malformed }
                for index in 0..<count {
                    characters.append(UInt16(wordDocument[start + index * 2]) | UInt16(wordDocument[start + index * 2 + 1]) << 8)
                }
            }
        }
        return characters
    }

    /// Word's in-text control characters → plain text.
    private static func plainText(fromWordCharacters characters: [UInt16]) -> String {
        // One entry per open field: true while still inside its instruction
        // part (between 0x13 begin and 0x14 separator).
        var fieldStack: [Bool] = []
        var output: [UInt16] = []
        output.reserveCapacity(characters.count)
        for character in characters {
            switch character {
            case 0x13: fieldStack.append(true)          // field begin
            case 0x14: if !fieldStack.isEmpty { fieldStack[fieldStack.count - 1] = false } // separator
            case 0x15: _ = fieldStack.popLast()         // field end
            default:
                guard !fieldStack.contains(true) else { continue }
                switch character {
                case 0x0D, 0x0B, 0x0C: output.append(0x0A)     // paragraph, line, page break
                case 0x07: output.append(0x09)                  // table cell / row mark
                case 0x1E: output.append(0x2D)                  // non-breaking hyphen
                case 0xA0: output.append(0x20)                  // non-breaking space
                case 0x00...0x08, 0x0E...0x1F: break            // objects, soft hyphen, other controls
                default: output.append(character)
                }
            }
        }
        return String(decoding: output, as: UTF16.self)
    }

    // MARK: - [MS-DOC] File Information Block

    private struct FileInformationBlock {
        let isEncrypted: Bool
        let usesTable1: Bool
        let mainTextLength: Int
        let clxOffset: Int
        let clxLength: Int

        init(_ stream: [UInt8]) throws {
            let reader = ByteReader(stream)
            guard try reader.uint16(at: 0) == 0xA5EC else { throw ExtractionError.notAWordDocument }
            let flags = try reader.uint16(at: 0x0A)
            isEncrypted = flags & 0x0100 != 0
            usesTable1 = flags & 0x0200 != 0

            // FibBase (32 bytes), then three length-prefixed arrays.
            let csw = Int(try reader.uint16(at: 32))
            let cslwOffset = 34 + csw * 2
            let cslw = Int(try reader.uint16(at: cslwOffset))
            let fibRgLw = cslwOffset + 2
            mainTextLength = Int(try reader.uint32(at: fibRgLw + 3 * 4))   // ccpText
            let cbRgFcLcbOffset = fibRgLw + cslw * 4
            let cbRgFcLcb = Int(try reader.uint16(at: cbRgFcLcbOffset))
            guard cbRgFcLcb >= 68 else { throw ExtractionError.malformed }
            let fcLcb = cbRgFcLcbOffset + 2
            clxOffset = Int(try reader.uint32(at: fcLcb + 66 * 4))          // fcClx
            clxLength = Int(try reader.uint32(at: fcLcb + 67 * 4))          // lcbClx
        }
    }

    // MARK: - Piece table (Clx → PlcPcd)

    private struct Piece {
        let cpStart: Int
        let cpEnd: Int
        let fileOffset: Int
        let isCompressed: Bool

        static func table(in stream: [UInt8], offset: Int, length: Int) throws -> [Piece] {
            let reader = ByteReader(stream)
            let end = offset + length
            guard offset >= 0, length > 0, end <= stream.count else { throw ExtractionError.malformed }
            var position = offset
            while position < end {
                switch stream[position] {
                case 0x01: // Prc: property modifiers — skip
                    let size = Int(Int16(bitPattern: try reader.uint16(at: position + 1)))
                    guard size >= 0 else { throw ExtractionError.malformed }
                    position += 3 + size
                case 0x02: // Pcdt: the piece table itself
                    let plcLength = Int(try reader.uint32(at: position + 1))
                    let plc = position + 5
                    guard plcLength >= 16, (plcLength - 4) % 12 == 0, plc + plcLength <= stream.count else {
                        throw ExtractionError.malformed
                    }
                    let count = (plcLength - 4) / 12
                    let descriptors = plc + (count + 1) * 4
                    return try (0..<count).map { index in
                        let raw = try reader.uint32(at: descriptors + index * 8 + 2)
                        return Piece(
                            cpStart: Int(try reader.uint32(at: plc + index * 4)),
                            cpEnd: Int(try reader.uint32(at: plc + (index + 1) * 4)),
                            fileOffset: Int(raw & 0x3FFF_FFFF),
                            isCompressed: raw & 0x4000_0000 != 0
                        )
                    }
                default:
                    throw ExtractionError.malformed
                }
            }
            throw ExtractionError.malformed
        }
    }

    // MARK: - [MS-CFB] Compound File Binary

    private struct CompoundFile {
        private static let signature: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        private static let endOfChain: UInt32 = 0xFFFF_FFFE
        private static let freeSector: UInt32 = 0xFFFF_FFFF

        private struct DirectoryEntry {
            let name: String
            let type: UInt8
            let startSector: UInt32
            let size: Int
        }

        private let bytes: [UInt8]
        private let reader: ByteReader
        private let sectorSize: Int
        private let miniSectorSize: Int
        private let miniStreamCutoff: Int
        private let fat: [UInt32]
        private let miniFat: [UInt32]
        private let entries: [DirectoryEntry]
        private let miniStream: [UInt8]

        init(bytes: [UInt8]) throws {
            guard bytes.count >= 512, Array(bytes[0..<8]) == Self.signature else {
                throw ExtractionError.notACompoundFile
            }
            self.bytes = bytes
            let reader = ByteReader(bytes)
            self.reader = reader
            let sectorShift = Int(try reader.uint16(at: 0x1E))
            let miniSectorShift = Int(try reader.uint16(at: 0x20))
            guard (9...12).contains(sectorShift), miniSectorShift == 6 else { throw ExtractionError.malformed }
            sectorSize = 1 << sectorShift
            miniSectorSize = 1 << miniSectorShift
            miniStreamCutoff = Int(try reader.uint32(at: 0x38))

            // FAT sector list: 109 entries in the header, then the DIFAT chain.
            var fatSectors: [UInt32] = []
            for index in 0..<109 {
                let sector = try reader.uint32(at: 0x4C + index * 4)
                if sector != Self.freeSector { fatSectors.append(sector) }
            }
            var difatSector = try reader.uint32(at: 0x44)
            var difatSeen = 0
            let perDifat = sectorSize / 4 - 1
            while difatSector != Self.endOfChain, difatSector != Self.freeSector {
                difatSeen += 1
                guard difatSeen <= bytes.count / sectorSize else { throw ExtractionError.malformed }
                let base = (Int(difatSector) + 1) * sectorSize
                for index in 0..<perDifat {
                    let sector = try reader.uint32(at: base + index * 4)
                    if sector != Self.freeSector { fatSectors.append(sector) }
                }
                difatSector = try reader.uint32(at: base + perDifat * 4)
            }
            var fat: [UInt32] = []
            for sector in fatSectors {
                let base = (Int(sector) + 1) * sectorSize
                for index in 0..<(sectorSize / 4) { fat.append(try reader.uint32(at: base + index * 4)) }
            }
            self.fat = fat

            let directory = try Self.chain(from: try reader.uint32(at: 0x30), fat: fat, sectorSize: sectorSize, bytes: bytes)
            var entries: [DirectoryEntry] = []
            for offset in stride(from: 0, to: directory.count - 127, by: 128) {
                let entryReader = ByteReader(directory)
                let nameLength = Int(try entryReader.uint16(at: offset + 0x40))
                let nameBytes = Array(directory[offset..<(offset + max(0, min(64, nameLength) - 2))])
                entries.append(DirectoryEntry(
                    name: String(decoding: stride(from: 0, to: nameBytes.count - 1, by: 2).map {
                        UInt16(nameBytes[$0]) | UInt16(nameBytes[$0 + 1]) << 8
                    }, as: UTF16.self),
                    type: directory[offset + 0x42],
                    startSector: try entryReader.uint32(at: offset + 0x74),
                    size: Int(try entryReader.uint32(at: offset + 0x78))
                ))
            }
            self.entries = entries

            let miniFatBytes = try Self.chain(from: try reader.uint32(at: 0x3C), fat: fat, sectorSize: sectorSize, bytes: bytes)
            let miniFatReader = ByteReader(miniFatBytes)
            miniFat = try stride(from: 0, to: miniFatBytes.count, by: 4).map { try miniFatReader.uint32(at: $0) }
            if let root = entries.first, root.type == 5 {
                let stream = try Self.chain(from: root.startSector, fat: fat, sectorSize: sectorSize, bytes: bytes)
                miniStream = Array(stream.prefix(root.size))
            } else {
                miniStream = []
            }
        }

        /// The named stream's bytes, or nil if the file has no such stream.
        func stream(named name: String) throws -> [UInt8]? {
            guard let entry = entries.first(where: { $0.type == 2 && $0.name == name }) else { return nil }
            if entry.size < miniStreamCutoff {
                var result: [UInt8] = []
                var sector = entry.startSector
                var steps = 0
                while sector != Self.endOfChain, result.count < entry.size {
                    steps += 1
                    guard Int(sector) < miniFat.count, steps <= miniFat.count else { throw ExtractionError.malformed }
                    let start = Int(sector) * miniSectorSize
                    guard start + miniSectorSize <= miniStream.count else { throw ExtractionError.malformed }
                    result.append(contentsOf: miniStream[start..<(start + miniSectorSize)])
                    sector = miniFat[Int(sector)]
                }
                return Array(result.prefix(entry.size))
            }
            let stream = try Self.chain(from: entry.startSector, fat: fat, sectorSize: sectorSize, bytes: bytes)
            return Array(stream.prefix(entry.size))
        }

        private static func chain(from start: UInt32, fat: [UInt32], sectorSize: Int, bytes: [UInt8]) throws -> [UInt8] {
            var result: [UInt8] = []
            var sector = start
            var steps = 0
            while sector != endOfChain, sector != freeSector {
                steps += 1
                guard Int(sector) < fat.count, steps <= fat.count else { throw ExtractionError.malformed }
                let offset = (Int(sector) + 1) * sectorSize
                guard offset + sectorSize <= bytes.count else { throw ExtractionError.malformed }
                result.append(contentsOf: bytes[offset..<(offset + sectorSize)])
                sector = fat[Int(sector)]
            }
            return result
        }
    }

    // MARK: - Little-endian reads with bounds checks

    private struct ByteReader {
        let bytes: [UInt8]
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func uint16(at offset: Int) throws -> UInt16 {
            guard offset >= 0, offset + 2 <= bytes.count else { throw ExtractionError.malformed }
            return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        }

        func uint32(at offset: Int) throws -> UInt32 {
            guard offset >= 0, offset + 4 <= bytes.count else { throw ExtractionError.malformed }
            return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
                | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
    }
}
