import Foundation

/// 轮询式连续出卡：按配置的卡位列表循环激活模拟卡槽
/// 适用于国内轮询版/大龙版固件"连续出卡"体验；官方固件同样可用（逐槽激活）。
@MainActor
final class PollingManager: ObservableObject {

    enum Mode {
        case off
        case cycle     // 循环切换（每张卡驻留固定时长）
        case sequence  // 按顺序逐张出卡，触发一次切下一张
    }

    @Published var mode: Mode = .off
    @Published var slotList: [Int] = []          // 逻辑卡位编号
    @Published var currentIndex = 0
    @Published var holdSeconds: Double = 1.0     // 每张卡驻留时长
    @Published var isRunning = false

    var onActivateSlot: ((Int) -> Void)?

    private var timer: Timer?
    private var pendingSequenceActivation = false

    /// 配置轮询卡位列表
    func configure(slots: [Int], hold: Double) {
        slotList = slots
        holdSeconds = max(0.2, hold)
        currentIndex = 0
    }

    /// 开始轮询
    func start() {
        guard !slotList.isEmpty, !isRunning else { return }
        isRunning = true
        currentIndex = 0
        activateCurrent()
        if mode == .cycle {
            startTimer()
        }
    }

    /// 停止轮询
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    /// 序列模式下：手动触发切到下一张（用户按键/接近感应）
    func next() {
        guard isRunning, mode == .sequence else { return }
        currentIndex = (currentIndex + 1) % slotList.count
        activateCurrent()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: holdSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRunning else { return }
                self.currentIndex = (self.currentIndex + 1) % self.slotList.count
                self.activateCurrent()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func activateCurrent() {
        guard !slotList.isEmpty else { return }
        let slot = slotList[currentIndex]
        onActivateSlot?(slot)
    }
}
