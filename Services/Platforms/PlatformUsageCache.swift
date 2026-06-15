import Foundation

// 线程安全的用量缓存, 给各 PlatformAPIService 使用.
// 各 service 被 PlatformManager 在 TaskGroup 里并发调用, cache 必须加锁.
final class PlatformUsageCache<T> {
    private var value: T?
    private var timestamp: Date?
    private let lock = NSLock()

    // 读取未过期的缓存. timeout 秒内有效, 过期返回 nil.
    func read(timeout: TimeInterval) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard let value, let timestamp else { return nil }
        if Date().timeIntervalSince(timestamp) < timeout {
            return value
        }
        return nil
    }

    // 写入缓存, 记录当前时间.
    func write(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
        self.timestamp = Date()
    }

    // 清除缓存.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        value = nil
        timestamp = nil
    }
}
