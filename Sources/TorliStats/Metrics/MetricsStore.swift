import Combine
import Foundation

private struct HighFrequencySnapshot {
    let cpu: Double
    let cpuPerCore: [Double]
    let gpu: Double
    let memory: Double
    let memoryUsed: String
    let memoryTotal: String
    let download: Double
    let upload: Double
    let cpuHistory: [Double]
    let gpuHistory: [Double]
    let memoryHistory: [Double]
    let networkDownloadHistory: [Double]
    let networkUploadHistory: [Double]
    let statusLine: StatusLine
}

private struct LowFrequencySnapshot {
    let diskUsage: Double
    let diskTotal: String
    let diskFree: String
    let battery: BatterySnapshot
    let bluetoothBatteries: [BluetoothBatterySnapshot]
    let processes: [ProcessRow]
    let deviceInfo: DeviceInfo?
}

final class MetricsStore: ObservableObject {
    // Publish one change after each completed snapshot instead of once per
    // field. This keeps SwiftUI from scheduling several redraws for one tick.
    let objectWillChange = ObservableObjectPublisher()

    private(set) var cpu = 0.0
    private(set) var cpuPerCore: [Double] = []
    private(set) var gpu = 0.0
    private(set) var memory = 0.0
    private(set) var memoryUsed = "—"
    private(set) var memoryTotal = "—"
    private(set) var diskUsage = 0.0
    private(set) var diskTotal = "—"
    private(set) var diskFree = "—"
    private(set) var download = 0.0
    private(set) var upload = 0.0
    private(set) var battery = BatterySnapshot(
        percentage: 0,
        health: nil,
        cycleCount: nil,
        adapterWatts: nil,
        isCharging: false,
        powerSource: "电池"
    )
    private(set) var deviceInfo = DeviceInfo.placeholder()
    private(set) var bluetoothBatteries: [BluetoothBatterySnapshot] = []
    private(set) var fanRPM: Int?
    private(set) var cpuTemperature: Double?
    private(set) var gpuTemperature: Double?
    private(set) var processes: [ProcessRow] = []
    private(set) var statusLine = StatusLine(
        cpu: "0%", memory: "0%", download: "0 KB/s", upload: "0 KB/s"
    )

    private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var gpuHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var memoryHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var networkDownloadHistory: [Double] = Array(repeating: 0, count: 24)
    private(set) var networkUploadHistory: [Double] = Array(repeating: 0, count: 24)

    // Sampling state is confined to background queues. UI-facing metrics are
    // only changed in apply* methods on the main queue. Keeping the high- and
    // low-frequency queues separate prevents a slow battery/Bluetooth/process
    // read from delaying CPU, GPU, or network updates.
    private let highMetricsQueue = DispatchQueue(label: "local.torli.stats.metrics.high", qos: .userInitiated)
    private let lowMetricsQueue = DispatchQueue(label: "local.torli.stats.metrics.low", qos: .utility)
    private var highTimer: DispatchSourceTimer?
    private var lowTimer: DispatchSourceTimer?
    private var cpuSampler = CPUSampler()
    private var previousNetwork: NetworkTotals?
    private var previousNetworkTime: TimeInterval?
    private var workerGPU = 0.0
    private var hasGPUSample = false
    private var gpuMonitoringEnabled = true
    private var lastGPUSampleTime: TimeInterval?
    // GPU usage is sourced from an `ioreg` subprocess. Ten seconds keeps the
    // dashboard informative while avoiding an expensive process launch on
    // every general metrics tick.
    private let gpuSampleInterval: TimeInterval = 10
    private var recentGPUSamples: [Double] = []
    private var workerCPUHistory = Array(repeating: 0.0, count: 24)
    private var workerGPUHistory = Array(repeating: 0.0, count: 24)
    private var workerMemoryHistory = Array(repeating: 0.0, count: 24)
    private var workerDownloadHistory = Array(repeating: 0.0, count: 24)
    private var workerUploadHistory = Array(repeating: 0.0, count: 24)
    private var workerIntervalSeconds = 3
    private var batteryRefreshIntervalSeconds = 10
    private var lowBatterySavingEnabled = true
    private var lowBatteryThreshold = 20
    private var isUsingBatteryPower = false
    private var batteryPercentage = 100.0
    private var processLimit = 5
    private var processSort: ProcessSortOption = .cpu
    private var powerSavingMode = false
    private var sensorHelperEnabled = false
    private var sensorPollingStopped = false
    private var deviceInfoLoaded = false
    private let sensorClient = SensorClient()
    private(set) var intervalSeconds: Int

    init(refreshInterval: Int = 3) {
        let resolvedInterval = AppSettings.supportedRefreshIntervals.contains(refreshInterval) ? refreshInterval : 3
        intervalSeconds = resolvedInterval
        workerIntervalSeconds = resolvedInterval
        startMonitoring()
    }

    func refreshNow() {
        highMetricsQueue.async { [weak self] in self?.collectHighFrequency() }
        lowMetricsQueue.async { [weak self] in self?.collectLowFrequency() }
    }

    func setRefreshInterval(_ seconds: Int) {
        guard AppSettings.supportedRefreshIntervals.contains(seconds), intervalSeconds != seconds else { return }
        intervalSeconds = seconds
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.workerIntervalSeconds = seconds
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
            self.collectHighFrequency()
        }
    }

    func setGPUMonitoringEnabled(_ enabled: Bool) {
        highMetricsQueue.async { [weak self] in
            guard let self, self.gpuMonitoringEnabled != enabled else { return }
            self.gpuMonitoringEnabled = enabled
            self.hasGPUSample = false
            self.lastGPUSampleTime = nil
            self.recentGPUSamples = []
            self.workerGPU = 0
            self.collectHighFrequency()
        }
    }

    func setPowerPolicy(
        batteryRefreshInterval: Int,
        enablesLowBatterySaving: Bool,
        lowBatteryThreshold: Int
    ) {
        guard AppSettings.supportedRefreshIntervals.contains(batteryRefreshInterval),
              [10, 20, 30].contains(lowBatteryThreshold) else { return }
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.batteryRefreshIntervalSeconds = batteryRefreshInterval
            self.lowBatterySavingEnabled = enablesLowBatterySaving
            self.lowBatteryThreshold = lowBatteryThreshold
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
        }
    }

    func setSensorHelperEnabled(_ enabled: Bool) {
        lowMetricsQueue.async { [weak self] in
            guard let self else { return }
            // AppDelegate also forwards unrelated settings changes here. Do
            // not restart a failed sensor session unless the enabled state
            // actually changed; otherwise a theme/toggle change would defeat
            // the no-retry rule for unavailable fan permissions.
            guard self.sensorHelperEnabled != enabled else { return }
            self.sensorHelperEnabled = enabled
            self.sensorPollingStopped = !enabled
            if enabled {
                self.pollSensorIfNeeded()
            } else {
                DispatchQueue.main.async {
                    self.fanRPM = nil
                    self.cpuTemperature = nil
                    self.gpuTemperature = nil
                }
            }
        }
    }

    func setProcessLimit(_ limit: Int) {
        guard [3, 5, 8, 10, 15].contains(limit) else { return }
        lowMetricsQueue.async { [weak self] in self?.processLimit = limit }
    }

    func setProcessSort(_ sort: ProcessSortOption) {
        lowMetricsQueue.async { [weak self] in self?.processSort = sort }
    }

    func setPowerSavingMode(_ enabled: Bool) {
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.powerSavingMode = enabled
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
            self.collectHighFrequency()
        }
        lowMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.powerSavingMode = enabled
            self.installLowTimer(interval: enabled ? 60 : 30)
        }
    }

    private func startMonitoring() {
        let initialInterval = TimeInterval(intervalSeconds)
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.installHighTimer(interval: self.effectiveHighRefreshInterval(fallback: initialInterval))
            self.collectHighFrequency()
        }
        lowMetricsQueue.async { [weak self] in
            guard let self else { return }
            self.installLowTimer(interval: self.powerSavingMode ? 60 : 30)
            self.collectLowFrequency()
        }
    }

    private func installHighTimer(interval: TimeInterval) {
        highTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: highMetricsQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.collectHighFrequency() }
        timer.resume()
        highTimer = timer
    }

    private func installLowTimer(interval: TimeInterval) {
        lowTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: lowMetricsQueue)
        // Battery, Bluetooth, disk, process and sensor reads are deliberately
        // kept out of the high-frequency path.
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.collectLowFrequency() }
        timer.resume()
        lowTimer = timer
    }

    deinit {
        highTimer?.cancel()
        lowTimer?.cancel()
    }

    private func collectHighFrequency() {
        let cpuSnapshot = cpuSampler.sample()
        let now = ProcessInfo.processInfo.systemUptime
        let stableGPU: Double
        if gpuMonitoringEnabled {
            if !hasGPUSample || lastGPUSampleTime.map({ now - $0 >= gpuSampleInterval }) == true {
                let rawGPU = GPUReader.usage()
                recentGPUSamples.append(rawGPU)
                if recentGPUSamples.count > 5 { recentGPUSamples.removeFirst() }
                lastGPUSampleTime = now
            }
            stableGPU = median(recentGPUSamples)
            // IORegistry 的 GPU 利用率是瞬时采样，偶尔会出现 0/100 的尖峰。
            workerGPU = hasGPUSample ? workerGPU * 0.7 + stableGPU * 0.3 : stableGPU
            hasGPUSample = true
        } else {
            stableGPU = 0
            workerGPU = 0
        }
        let memorySnapshot = MemoryReader.snapshot()
        let memory = memorySnapshot.percentage

        let totals = NetworkReader.totals()
        let elapsed = previousNetworkTime.map { max(now - $0, 0.001) } ?? 0
        let download: Double
        let upload: Double
        if let previousNetwork, elapsed > 0 {
            download = totals.received >= previousNetwork.received
                ? Double(totals.received - previousNetwork.received) / elapsed
                : 0
            upload = totals.sent >= previousNetwork.sent
                ? Double(totals.sent - previousNetwork.sent) / elapsed
                : 0
        } else {
            download = 0
            upload = 0
        }
        previousNetwork = totals
        previousNetworkTime = now

        append(&workerCPUHistory, cpuSnapshot.total)
        append(&workerGPUHistory, workerGPU)
        append(&workerMemoryHistory, memory)
        append(&workerDownloadHistory, download)
        append(&workerUploadHistory, upload)

        let snapshot = HighFrequencySnapshot(
            cpu: cpuSnapshot.total,
            cpuPerCore: cpuSnapshot.perCore,
            gpu: workerGPU,
            memory: memory,
            memoryUsed: memorySnapshot.used,
            memoryTotal: memorySnapshot.total,
            download: download,
            upload: upload,
            cpuHistory: workerCPUHistory,
            gpuHistory: workerGPUHistory,
            memoryHistory: workerMemoryHistory,
            networkDownloadHistory: workerDownloadHistory,
            networkUploadHistory: workerUploadHistory,
            statusLine: StatusLine(
                cpu: "\(Int(cpuSnapshot.total))%",
                memory: "\(Int(memory))%",
                download: formatRate(download),
                upload: formatRate(upload)
            )
        )
        DispatchQueue.main.async { [weak self] in self?.apply(snapshot) }
    }

    private func collectLowFrequency() {
        let disk = DiskReader.snapshot()
        let battery = BatteryReader.snapshot()
        let bluetooth = BluetoothReader.snapshot()
        let processes = ProcessReader.topProcesses(limit: processLimit, sort: processSort)
        let info: DeviceInfo?
        if deviceInfoLoaded {
            info = nil
        } else {
            info = DeviceInfo.current()
            deviceInfoLoaded = true
        }

        updatePowerSource(battery)

        let snapshot = LowFrequencySnapshot(
            diskUsage: disk.usage,
            diskTotal: formatBytes(disk.total),
            diskFree: formatBytes(disk.free),
            battery: battery,
            bluetoothBatteries: bluetooth,
            processes: processes,
            deviceInfo: info
        )
        DispatchQueue.main.async { [weak self] in self?.apply(snapshot) }

        pollSensorIfNeeded()
    }

    private func updatePowerSource(_ battery: BatterySnapshot) {
        highMetricsQueue.async { [weak self] in
            guard let self else { return }
            let wasUsingBattery = self.isUsingBatteryPower
            let wasLowBattery = self.isLowBattery
            self.isUsingBatteryPower = !battery.isCharging && battery.powerSource == "电池"
            self.batteryPercentage = battery.percentage

            guard wasUsingBattery != self.isUsingBatteryPower || wasLowBattery != self.isLowBattery else { return }
            self.installHighTimer(interval: self.effectiveHighRefreshInterval())
            self.collectHighFrequency()
        }
    }

    private var isLowBattery: Bool {
        isUsingBatteryPower && batteryPercentage <= Double(lowBatteryThreshold)
    }

    private func effectiveHighRefreshInterval(fallback: TimeInterval? = nil) -> TimeInterval {
        let pluggedInInterval = fallback ?? TimeInterval(workerIntervalSeconds)
        let baseInterval = isUsingBatteryPower ? TimeInterval(batteryRefreshIntervalSeconds) : pluggedInInterval
        if lowBatterySavingEnabled && isLowBattery {
            return max(baseInterval, 30)
        }
        if powerSavingMode {
            return max(baseInterval, 10)
        }
        return baseInterval
    }

    private func pollSensorIfNeeded() {
        guard sensorHelperEnabled, !sensorPollingStopped else { return }
        sensorClient.read { [weak self] values in
            guard let self else { return }
            self.lowMetricsQueue.async {
                guard self.sensorHelperEnabled, !self.sensorPollingStopped else { return }
                // A failed helper/permission read is not transient. Do not
                // keep waking the privileged helper every low-frequency tick.
                guard values.isAvailable else {
                    self.sensorPollingStopped = true
                    return
                }

                // A missing fan key is a capability limitation, not a failed
                // helper session. Continue polling so CPU/GPU temperatures can
                // still update on machines that do not expose fan RPM.
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                    if let fanRPM = values.fanRPM { self.fanRPM = fanRPM }
                    if let cpuTemperature = values.cpuTemperature { self.cpuTemperature = cpuTemperature }
                    if let gpuTemperature = values.gpuTemperature { self.gpuTemperature = gpuTemperature }
                }
            }
        }
    }

    private func apply(_ snapshot: HighFrequencySnapshot) {
        objectWillChange.send()
        cpu = snapshot.cpu
        cpuPerCore = snapshot.cpuPerCore
        gpu = snapshot.gpu
        memory = snapshot.memory
        memoryUsed = snapshot.memoryUsed
        memoryTotal = snapshot.memoryTotal
        download = snapshot.download
        upload = snapshot.upload
        cpuHistory = snapshot.cpuHistory
        gpuHistory = snapshot.gpuHistory
        memoryHistory = snapshot.memoryHistory
        networkDownloadHistory = snapshot.networkDownloadHistory
        networkUploadHistory = snapshot.networkUploadHistory
        statusLine = snapshot.statusLine
    }

    private func apply(_ snapshot: LowFrequencySnapshot) {
        objectWillChange.send()
        diskUsage = snapshot.diskUsage
        diskTotal = snapshot.diskTotal
        diskFree = snapshot.diskFree
        battery = snapshot.battery
        bluetoothBatteries = snapshot.bluetoothBatteries
        processes = snapshot.processes
        if var info = snapshot.deviceInfo {
            info.uptime = DeviceInfo.uptimeString()
            deviceInfo = info
        } else {
            deviceInfo.uptime = DeviceInfo.uptimeString()
        }
    }

    private func append(_ values: inout [Double], _ value: Double) {
        values.append(value)
        if values.count > 24 { values.removeFirst() }
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    private func formatRate(_ bytes: Double) -> String {
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB/s", bytes / 1024 / 1024) }
        return String(format: "%.0f KB/s", bytes / 1024)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gigabytes = Double(bytes) / 1_000_000_000
        if gigabytes >= 1 { return String(format: "%.0f GB", gigabytes) }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }
}
