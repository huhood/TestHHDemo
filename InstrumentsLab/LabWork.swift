import Foundation
import QuartzCore
import os

// 用 Instruments 的 Points of Interest 跟踪关键业务操作。
// 配合 Animation Hitches / Time Profiler 观察，不能只凭这个标记断定卡顿原因。
enum LabSignpost {
    static let signposter = OSSignposter(
        subsystem: "com.example.InstrumentsLab",
        category: "PerformanceExperiments"
    )

    static func firstLoad(_ operation: () -> Void) {
        let interval = signposter.beginInterval("FirstLoadWork")
        operation()
        signposter.endInterval("FirstLoadWork", interval)
    }

    static func scrollCell(_ operation: () -> Void) {
        let interval = signposter.beginInterval("CellConfigurationWork")
        operation()
        signposter.endInterval("CellConfigurationWork", interval)
    }

    static func imageDecode(_ operation: () -> Void) {
        let interval = signposter.beginInterval("ImageDecodeOnMain")
        operation()
        signposter.endInterval("ImageDecodeOnMain", interval)
    }

    static func imageDownsample(_ operation: () -> Void) {
        let interval = signposter.beginInterval("ImageDownsampleOffMain")
        operation()
        signposter.endInterval("ImageDownsampleOffMain", interval)
    }
}

// 【故意制造 CPU 忙碌】模拟真实项目中在主线程执行了昂贵的同步工作。
// 不使用 sleep：sleep 不占 CPU，Time Profiler 不容易观察真实计算开销。
enum LabCPU {
    private static var sink = 0.0

    static func busyWork(milliseconds: Double) {
        let deadline = CACurrentMediaTime() + milliseconds / 1000.0
        var value = 0.0
        var counter = 1.0

        while CACurrentMediaTime() < deadline {
            value += sqrt(counter)
            counter += 1.0
            if counter > 4096.0 { counter = 1.0 }
        }

        // 将结果写入静态属性，避免编译器把计算视作无用代码。
        sink = value
    }
}
