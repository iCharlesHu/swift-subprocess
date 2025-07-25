//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
@preconcurrency internal import Dispatch
#endif


extension AsyncBufferSequence {
    /// A immutable collection of bytes
    public struct Buffer: Sendable {
        #if os(Windows)
        internal let data: [UInt8]

        internal init(data: [UInt8]) {
            self.data = data
        }

        internal static func createFrom(_ data: [UInt8]) -> [Buffer] {
            return [.init(data: data)]
        }
        #else
        // We need to keep the backingData alive while _ContiguousBufferView is alive
        internal let backingData: DispatchData
        internal let data: DispatchData._ContiguousBufferView

        internal init(data: DispatchData._ContiguousBufferView, backingData: DispatchData) {
            self.data = data
            self.backingData = backingData
        }

        internal static func createFrom(_ data: DispatchData) -> [Buffer] {
            let slices = data.contiguousBufferViews
            // In most (all?) cases data should only have one slice
            if _fastPath(slices.count == 1) {
                return [.init(data: slices[0], backingData: data)]
            }
            return slices.map{ .init(data: $0, backingData: data) }
        }
        #endif
    }
}

// MARK: - Properties
extension AsyncBufferSequence.Buffer {
    /// Number of bytes stored in the buffer
    public var count: Int {
        return self.data.count
    }

    /// A Boolean value indicating whether the collection is empty.
    public var isEmpty: Bool {
        return self.data.isEmpty
    }
}

// MARK: - Accessors
extension AsyncBufferSequence.Buffer {
    /// Access the raw bytes stored in this buffer
    /// - Parameter body: A closure with an `UnsafeRawBufferPointer` parameter that
    ///   points to the contiguous storage for the type. If no such storage exists,
    ///   the method creates it. If body has a return value, this method also returns
    ///   that value. The argument is valid only for the duration of the
    ///   closure’s SequenceOutput.
    /// - Returns: The return value, if any, of the body closure parameter.
    public func withUnsafeBytes<ResultType>(
        _ body: (UnsafeRawBufferPointer) throws -> ResultType
    ) rethrows -> ResultType {
        return try self.data.withUnsafeBytes(body)
    }

    #if SubprocessSpan
    // Access the storage backing this Buffer
    public var bytes: RawSpan {
        @lifetime(borrow self)
        borrowing get {
            let ptr = self.data.withUnsafeBytes { $0 }
            let bytes = RawSpan(_unsafeBytes: ptr)
            return _overrideLifetime(of: bytes, to: self)
        }
    }
    #endif  // SubprocessSpan
}

// MARK: - Hashable, Equatable
extension AsyncBufferSequence.Buffer: Equatable, Hashable {
    #if os(Windows)
    // Compiler generated conformances
    #else
    public static func == (lhs: AsyncBufferSequence.Buffer, rhs: AsyncBufferSequence.Buffer) -> Bool {
        return lhs.data.elementsEqual(rhs.data)
    }

    public func hash(into hasher: inout Hasher) {
        self.data.withUnsafeBytes { ptr in
            hasher.combine(bytes: ptr)
        }
    }
    #endif
}

// MARK: - DispatchData.Block
#if canImport(Darwin) || canImport(Glibc) || canImport(Android) || canImport(Musl)
extension DispatchData {
    /// Unfortunately `DispatchData.Region` is not available on Linux, hence our own wrapper
    internal struct _ContiguousBufferView: @unchecked Sendable, RandomAccessCollection {
        typealias Element = UInt8

        internal let bytes: UnsafeBufferPointer<UInt8>

        internal var startIndex: Int { self.bytes.startIndex }
        internal var endIndex: Int { self.bytes.endIndex }

        internal init(bytes: UnsafeBufferPointer<UInt8>) {
            self.bytes = bytes
        }

        internal func withUnsafeBytes<ResultType>(_ body: (UnsafeRawBufferPointer) throws -> ResultType) rethrows -> ResultType {
            return try body(UnsafeRawBufferPointer(self.bytes))
        }

        subscript(position: Int) -> UInt8 {
            _read {
                yield self.bytes[position]
            }
        }
    }

    internal var contiguousBufferViews: [_ContiguousBufferView] {
        var slices = [_ContiguousBufferView]()
        enumerateBytes { (bytes, index, stop) in
            slices.append(_ContiguousBufferView(bytes: bytes))
        }
        return slices
    }
}

#endif
