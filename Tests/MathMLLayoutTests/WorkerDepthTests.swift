import CoreGraphics
import Darwin
import Foundation
@testable import MathMLLayout
import XCTest

final class WorkerDepthTests: MathTestCase {
    private struct Snapshot: Equatable, Sendable {
        let metrics: [CGFloat]
        let items: Int
        let ink: CGRect?
        let readings: [MathReading]
        let pixels: [UInt8]
    }

    private static func snapshot(_ node: MathMLNode) -> Result<Snapshot, MathLayoutError> {
        do {
            let style = MathStyle(fontSize: 12, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            let layout = try MathLayout(node, style: style)
            let box = try LayoutEngine(fontName: nil).layoutRoot(node, style: style)
            let canvas = CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                                   bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            box.draw(in: canvas, at: CGPoint(x: 4, y: 64))
            let pixels = Array(UnsafeBufferPointer(start: canvas.data!.assumingMemoryBound(to: UInt8.self),
                                                  count: 128 * 512))
            return .success(Snapshot(metrics: [layout.width, layout.ascent, layout.descent, box.width, box.ascent, box.descent],
                                     items: box.itemCount, ink: box.inkBounds,
                                     readings: MathReading.languages.map { node.accessibilityDescription(locale: Locale(identifier: $0)) },
                                     pixels: pixels))
        } catch let error as MathLayoutError { return .failure(error) }
        catch { XCTFail("unexpected layout error: \(error)"); return .failure(.invalidMarkup("unexpected error")) }
    }

    private final class Worker: @unchecked Sendable {
        let operation: @Sendable () -> Void
        init(_ operation: @escaping @Sendable () -> Void) { self.operation = operation }
    }

    private func onWorker<T: Sendable>(stack: Int = 512 * 1024,
                                      _ operation: @escaping @Sendable () -> T) -> T {
        nonisolated(unsafe) var result: T?
        let work = Worker {
            XCTAssertEqual(pthread_get_stacksize_np(pthread_self()), stack)
            result = operation()
        }
        var attributes = pthread_attr_t()
        XCTAssertEqual(pthread_attr_init(&attributes), 0)
        defer { pthread_attr_destroy(&attributes) }
        // Supply the allocation ourselves. New Darwin pthreads otherwise add 12 KB to the
        // requested size; the experiment must actually have exactly 512 KB available.
        let page = Int(getpagesize())
        let allocation = mmap(nil, stack + 2 * page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0)!
        XCTAssertNotEqual(allocation, MAP_FAILED)
        defer { munmap(allocation, stack + 2 * page) }
        XCTAssertEqual(mprotect(allocation, page, PROT_NONE), 0)
        XCTAssertEqual(mprotect(allocation.advanced(by: page + stack), page, PROT_NONE), 0)
        XCTAssertEqual(pthread_attr_setstack(&attributes, allocation.advanced(by: page), stack), 0)
        var worker: pthread_t?
        let started = pthread_create(&worker, &attributes, { pointer in
            Unmanaged<Worker>.fromOpaque(pointer).takeUnretainedValue().operation()
            return nil
        }, Unmanaged.passUnretained(work).toOpaque())
        XCTAssertEqual(started, 0)
        if let worker { withExtendedLifetime(work) { XCTAssertEqual(pthread_join(worker, nil), 0) } }
        return result!
    }

    private var shapes: [(String, Int, @Sendable (MathMLNode) -> MathMLNode)] {
        let one = MathMLNode(name: "mn", text: "1")
        return [
            ("row", 1, { MathMLNode(name: "mrow", children: [$0]) }),
            ("fraction", 1, { MathMLNode(name: "mfrac", children: [$0, one]) }),
            ("superscript", 1, { MathMLNode(name: "msup", children: [$0, one]) }),
            ("subscript", 1, { MathMLNode(name: "msub", children: [one, $0]) }),
            ("under-over", 1, { MathMLNode(name: "munderover", children: [$0, one, one]) }),
            ("square-root", 1, { MathMLNode(name: "msqrt", children: [$0]) }),
            ("root", 1, { MathMLNode(name: "mroot", children: [$0, one]) }),
            ("style", 1, { MathMLNode(name: "mstyle", children: [$0]) }),
            ("padded", 1, { MathMLNode(name: "mpadded", children: [$0]) }),
            ("semantics", 1, { MathMLNode(name: "semantics", children: [$0]) }),
            ("table", 3, { MathMLNode(name: "mtable", children: [MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: [$0])])]) }),
        ]
    }

    private func nested(_ count: Int, leaf: MathMLNode = MathMLNode(name: "mi", text: "x"),
                        _ wrap: (MathMLNode) -> MathMLNode) -> MathMLNode {
        (0..<count).reduce(leaf) { node, _ in wrap(node) }
    }

    func testCoveredShapesAt64LevelsHaveIdenticalGeometryItemsAndReadings() throws {
        for (name, step, wrap) in shapes {
            // Pure subscript/under-over chains still use more stack. The documented 64-level
            // coverage for those is 48 structural wrappers and 15 outer single-child rows.
            let structural = ["subscript", "under-over"].contains(name) ? 48 : 63 / step
            var root = nested(structural, wrap)
            root = nested(63 - structural * step, leaf: root) { MathMLNode(name: "mrow", children: [$0]) }
            let node = root
            let reference = onWorker(stack: 8 * 1024 * 1024) { Self.snapshot(node) }
            guard case .success = reference else { XCTFail("invalid reference shape: \(name)"); continue }
            let first = onWorker { Self.snapshot(node) }
            let second = onWorker { Self.snapshot(node) }
            XCTAssertEqual(first, reference, name)
            XCTAssertEqual(second, first, "deterministic \(name)")
        }
    }

    func testThe65thLevelStillExceedsTheBound() {
        for (name, step, wrap) in shapes {
            let structural = ["subscript", "under-over"].contains(name) ? 48 : 63 / step
            var root = nested(structural, wrap)
            root = nested(64 - structural * step, leaf: root) { MathMLNode(name: "mrow", children: [$0]) }
            let node = root
            XCTAssertEqual(onWorker { Self.snapshot(node) }, .failure(.limitExceeded), name)
        }
    }

    func testRTLSchemataAt64LevelsMatchOnAnExact512KBWorker() {
        for (name, step, wrap) in shapes {
            let structural = ["subscript", "under-over"].contains(name) ? 48 : 63 / step
            var root = nested(structural, wrap)
            root = nested(63 - structural * step, leaf: root) { MathMLNode(name: "mrow", children: [$0]) }
            root.attributes["dir"] = "rtl"
            let node = root
            let reference = onWorker(stack: 8 * 1024 * 1024) { Self.snapshot(node) }
            guard case .success = reference else { XCTFail("invalid RTL reference shape: \(name)"); continue }
            XCTAssertEqual(onWorker { Self.snapshot(node) }, reference, name)
            XCTAssertEqual(onWorker { Self.snapshot(node) }, reference, "repeat RTL \(name)")
        }
    }

    func testSmallerStacksRetainTheSafetyGuard() {
        for (name, step, wrap) in shapes {
            let root = nested(63 / step, wrap)
            XCTAssertEqual(onWorker(stack: 128 * 1024) { Self.snapshot(root) }, .failure(.limitExceeded), name)
            XCTAssertEqual(onWorker(stack: 128 * 1024) { root.accessibilityDescription }, "", name)
            let bounded = onWorker(stack: 256 * 1024) { Self.snapshot(root) }
            if case .failure(let error) = bounded { XCTAssertEqual(error, .limitExceeded, name) }
        }
    }

    private static func outcome(_ node: MathMLNode) -> MathLayoutError? {
        do {
            _ = try MathLayout(node, style: MathStyle(fontSize: 1, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)))
            return nil
        } catch let error as MathLayoutError { return error }
        catch { XCTFail("unexpected error: \(error)"); return .invalidMarkup("unexpected error") }
    }

    func testBoundsAndSkippedAnnotationCountingThroughHeapWrappers() {
        func wrap(_ node: MathMLNode) -> MathMLNode {
            nested(62, leaf: node) { MathMLNode(name: "mrow", children: [$0]) }
        }
        for extra in [0, 1] {
            let tokens = Array(repeating: MathMLNode(name: "mi", text: "x"), count: MathLimits.nodes - 63 + extra)
            let wide = wrap(MathMLNode(name: "mrow", children: tokens))
            XCTAssertEqual(onWorker { Self.outcome(wide) }, extra == 0 ? nil : .limitExceeded)
            let annotations = Array(repeating: MathMLNode(name: "annotation"), count: MathLimits.nodes - 64 + extra)
            let selected = wrap(MathMLNode(name: "semantics", children: annotations + [MathMLNode(name: "mi", text: "x")]))
            XCTAssertEqual(onWorker { Self.outcome(selected) }, extra == 0 ? nil : .limitExceeded)
            XCTAssertEqual(onWorker { selected.accessibilityDescription }, extra == 0 ? "x" : "")
            let text = wrap(MathMLNode(name: "mtext", text: String(repeating: "i", count: MathLimits.textLength + extra)))
            XCTAssertEqual(onWorker { Self.outcome(text) }, extra == 0 ? nil : .limitExceeded)
            let extent = wrap(MathMLNode(name: "mspace", attributes: ["height": "\(Int(MathLimits.extent) + extra)px", "mathsize": "1000px"]))
            XCTAssertEqual(onWorker { Self.outcome(extent) }, extra == 0 ? nil : .limitExceeded)
        }
    }

    func testRTLAlignmentGroupsAt64LevelsMatchOnAnExact512KBWorker() {
        func cell(_ first: Int, _ second: Int) -> MathMLNode {
            var row = MathMLNode(name: "mrow", children: [
                MathMLNode(name: "maligngroup"),
                MathMLNode(name: "mspace", attributes: ["width": "\(first)em", "height": "1em", "mathbackground": "red"]),
                MathMLNode(name: "maligngroup"),
                MathMLNode(name: "mspace", attributes: ["width": "\(second)em", "height": "1em", "mathbackground": "blue"]),
            ])
            for _ in 0..<58 { row = MathMLNode(name: "mrow", attributes: ["dir": "rtl"], children: [row]) }
            return MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: [row])])
        }
        let root = MathMLNode(name: "math", attributes: ["dir": "rtl"], children: [
            MathMLNode(name: "mtable", children: [cell(1, 2), cell(3, 1)])
        ])
        let main = Self.snapshot(root)
        guard case .success(let snapshot) = main else { return XCTFail("64-level RTL groups must lay out") }
        XCTAssertEqual(snapshot.metrics[0], 60, accuracy: 0.001)
        XCTAssertEqual(onWorker { Self.snapshot(root) }, main)
    }

    func testWrappedNeighborTargetsAt64LevelsMatchOnAnExact512KBWorker() {
        let targetLeaf = MathMLNode(name: "mrow", children: [
            MathMLNode(name: "mspace", attributes: ["width": "1em", "height": "1em", "mathbackground": "red"]),
            MathMLNode(name: "mspace", attributes: ["linebreak": "newline", "indentalign": "left", "indentshift": "0px"]),
            MathMLNode(name: "mspace", attributes: ["width": "2em", "height": "1em", "mathbackground": "blue"]),
        ])
        let target = nested(58, leaf: targetLeaf) { MathMLNode(name: "mrow", children: [$0]) }
        func row(_ children: [MathMLNode]) -> MathMLNode {
            MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: children)])
        }
        let root = MathMLNode(name: "math", attributes: ["dir": "rtl"], children: [
            MathMLNode(name: "mtable", children: [
                row([MathMLNode(name: "maligngroup"), MathMLNode(name: "malignmark", attributes: ["edge": "right"]), target]),
                row([MathMLNode(name: "maligngroup"),
                     MathMLNode(name: "mspace", attributes: ["width": "3em", "height": "1em", "mathbackground": "lime"]),
                     MathMLNode(name: "malignmark", attributes: ["edge": "left"])]),
            ])
        ])
        let reference = onWorker(stack: 8 * 1024 * 1024) { Self.snapshot(root) }
        guard case .success = reference else { return XCTFail("64-level wrapped neighbor target must lay out") }
        XCTAssertEqual(onWorker { Self.snapshot(root) }, reference)
        XCTAssertEqual(onWorker { Self.snapshot(root) }, reference)
    }

    func testMeasureWorkerDepth() throws {
        guard ProcessInfo.processInfo.environment["MATHML_MEASURE_WORKER_DEPTH"] == "1" else {
            throw XCTSkip("Set MATHML_MEASURE_WORKER_DEPTH=1 to report maximum covered depths")
        }
        for (name, step, wrap) in shapes {
            let maximum = 63 / step
            var last = 0
            for depth in 1...maximum {
                var node = MathMLNode(name: "mi", text: "x")
                for _ in 0..<depth { node = wrap(node) }
                let root = node
                let succeeded = onWorker {
                    do {
                        _ = try MathLayout(root, style: MathStyle(fontSize: 12,
                            color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)))
                        return true
                    } catch { return false }
                }
                if !succeeded { break }
                last = depth
            }
            print("WORKER DEPTH \(name): \(last * step + 1) levels (\(last) wrappers)")
        }
    }
}
