iOS Instruments 性能排查实验室（UIKit）

三个独立页面 A 首次加载卡顿、B 快速滚动卡顿、C 图片出现时卡顿。每个页面都能在「故障版 / 优化版」之间切换。使用 Xcode 16+、iOS 16+，无第三方依赖。

克隆：git clone --branch ios-instruments-lab --single-branch https://github.com/huhood/TestHHDemo.git ios-instruments-lab
打开：cd ios-instruments-lab && open InstrumentsLab.xcodeproj

运行：在 Xcode 选择真机，Signing & Capabilities 中设置个人 Team，必要时修改 Bundle Identifier，按 Command+R。
性能分析：Product → Profile（Command+I），使用 Animation Hitches、Time Profiler、Allocations；详见 docs/实验记录.md。

实验 A：首次进入自动执行约 450ms 主线程 CPU 任务；优化版转后台执行。Time Profiler 找 LabCPU.busyWork、FirstLoadWork。
实验 B：故障版每次 cellForRowAt 同步增加约 12ms CPU 工作；优化版移除。快速上下滚动，对比 Animation Hitches；找 CellConfigurationWork。
实验 C：首次进入先在后台生成离线 2600px JPEG，等提示「素材准备完成」再录制。故障版主线程同步解大图，优化版后台降采样和 NSCache 缩略图缓存。找 ImageDecodeOnMain、ImageDownsampleOffMain。

首次测试推荐：先 Command+I → Animation Hitches 找卡顿发生时间，再 Command+I → Time Profiler 找主线程耗时函数；在相同设备、相同操作下对比优化前后。静止页面主线程阻塞也可查看 Hangs。

故障版为教学故意制造性能问题，不能用于商业代码。当前环境无法运行 Xcode 真机编译，仅做 Swift 语法与文件结构检查。
