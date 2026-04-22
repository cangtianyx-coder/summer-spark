import Foundation

// MARK: - 积分优先级消息调度器
// 依赖文件：CreditEngine.swift, CreditCalculator.swift, QoSModels.swift, SharedModels.swift

// MARK: - 调度周期配置
enum SchedulerCycle: TimeInterval, CaseIterable {
    case fast = 0.010      // 10ms
    case normal = 0.050    // 50ms
    case slow = 0.100      // 100ms

    var milliseconds: Int {
        return Int(self.rawValue * 1000)
    }
}

// MARK: - 调度任务状态
enum ScheduledTaskState {
    case pending
    case delayed(remainingDelay: TimeInterval)
    case ready
    case executing
    case completed
    case failed(reason: String)
    case cancelled
}

// MARK: - 调度任务封装
final class SchedulableTask {
    let id: String
    let taskType: ScheduledTask.TaskType
    let priority: MessagePriority
    let creditCost: Int
    let createdAt: Date
    let deadline: Date?
    var state: ScheduledTaskState
    var retryCount: Int
    let maxRetries: Int
    let sourceNodeId: String
    let targetNodeId: String?
    let payload: Data?
    var dynamicPriority: Double
    let creditTier: CreditAccount.CreditTier

    init(
        id: String = UUID().uuidString,
        taskType: ScheduledTask.TaskType,
        priority: MessagePriority,
        creditCost: Int,
        createdAt: Date = Date(),
        deadline: Date? = nil,
        maxRetries: Int = 3,
        sourceNodeId: String,
        targetNodeId: String? = nil,
        payload: Data? = nil,
        creditTier: CreditAccount.CreditTier = .bronze
    ) {
        self.id = id
        self.taskType = taskType
        self.priority = priority
        self.creditCost = creditCost
        self.createdAt = createdAt
        self.deadline = deadline
        self.state = .pending
        self.retryCount = 0
        self.maxRetries = maxRetries
        self.sourceNodeId = sourceNodeId
        self.targetNodeId = targetNodeId
        self.payload = payload
        self.dynamicPriority = Double(priority.rawValue)
        self.creditTier = creditTier
    }

    var isExpired: Bool {
        if let deadline = deadline {
            return Date() > deadline
        }
        return false
    }

    var canRetry: Bool {
        return retryCount < maxRetries
    }

    func calculateDynamicPriority(creditEngine: CreditEngine, elapsedTime: TimeInterval) -> Double {
        let basePriority = Double(priority.rawValue)

        // 信用等级调整
        let tierMultiplier: Double
        switch creditTier {
        case .platinum: tierMultiplier = 1.5
        case .gold: tierMultiplier = 1.3
        case .silver: tierMultiplier = 1.1
        case .bronze: tierMultiplier = 1.0
        }

        // 等待时间衰减（越等越优先，但不能超过原优先级的2倍）
        let waitTimeBonus = min(elapsedTime / 60.0, 1.0) * 0.5

        // 信用余额调整
        let balance = creditEngine.getBalance()
        let balanceFactor: Double
        if balance >= 1000 {
            balanceFactor = 1.2
        } else if balance >= 500 {
            balanceFactor = 1.0
        } else if balance >= 100 {
            balanceFactor = 0.8
        } else {
            balanceFactor = 0.5
        }

        let finalPriority = (basePriority + waitTimeBonus) * tierMultiplier * balanceFactor
        return min(finalPriority, Double(MessagePriority.critical.rawValue) * 2.0)
    }
}

// MARK: - 优先级队列
final class PriorityTaskQueue {
    private var tasks: [SchedulableTask] = []
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return tasks.count
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tasks.isEmpty
    }

    func enqueue(_ task: SchedulableTask) {
        lock.lock()
        defer { lock.unlock() }

        // 按优先级插入，保持队列有序
        let insertIndex = tasks.firstIndex { $0.dynamicPriority < task.dynamicPriority } ?? tasks.count
        tasks.insert(task, at: insertIndex)
    }

    func dequeue() -> SchedulableTask? {
        lock.lock()
        defer { lock.unlock() }

        guard !tasks.isEmpty else { return nil }
        return tasks.removeFirst()
    }

    func peek() -> SchedulableTask? {
        lock.lock()
        defer { lock.unlock() }

        return tasks.first
    }

    func remove(taskId: String) -> SchedulableTask? {
        lock.lock()
        defer { lock.unlock() }

        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return nil }
        return tasks.remove(at: index)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        tasks.removeAll()
    }

    func allTasks() -> [SchedulableTask] {
        lock.lock()
        defer { lock.unlock() }
        return tasks
    }

    func tasksForNode(_ nodeId: String) -> [SchedulableTask] {
        lock.lock()
        defer { lock.unlock() }
        return tasks.filter { $0.targetNodeId == nodeId || $0.sourceNodeId == nodeId }
    }
}

// MARK: - 延迟任务记录
struct DelayedTaskRecord {
    let task: SchedulableTask
    let delayedUntil: Date
    let originalPriority: MessagePriority
    let reason: String

    var isReady: Bool {
        return Date() >= delayedUntil
    }
}

// MARK: - 调度统计
struct SchedulerStatistics {
    var totalScheduled: Int = 0
    var totalExecuted: Int = 0
    var totalFailed: Int = 0
    var totalDelayed: Int = 0
    var totalCancelled: Int = 0
    var totalCreditsConsumed: Double = 0
    var totalCreditsRefunded: Double = 0
    var averageQueueWaitTime: TimeInterval = 0
    var peakQueueSize: Int = 0
    var lastResetDate: Date = Date()

    mutating func recordExecution(creditCost: Double) {
        totalExecuted += 1
        totalCreditsConsumed += creditCost
    }

    mutating func recordDelay() {
        totalDelayed += 1
    }

    mutating func recordFailure() {
        totalFailed += 1
    }

    mutating func recordCancellation() {
        totalCancelled += 1
    }

    mutating func recordRefund(amount: Double) {
        totalCreditsRefunded += amount
    }

    mutating func updatePeakQueueSize(_ size: Int) {
        if size > peakQueueSize {
            peakQueueSize = size
        }
    }

    mutating func reset() {
        totalScheduled = 0
        totalExecuted = 0
        totalFailed = 0
        totalDelayed = 0
        totalCancelled = 0
        totalCreditsConsumed = 0
        totalCreditsRefunded = 0
        averageQueueWaitTime = 0
        peakQueueSize = 0
        lastResetDate = Date()
    }
}

// MARK: - 调度器委托协议
protocol PrioritySchedulerDelegate: AnyObject {
    func scheduler(_ scheduler: PriorityScheduler, didScheduleTask task: SchedulableTask)
    func scheduler(_ scheduler: PriorityScheduler, didExecuteTask task: SchedulableTask)
    func scheduler(_ scheduler: PriorityScheduler, didFailTask task: SchedulableTask, reason: String)
    func scheduler(_ scheduler: PriorityScheduler, didDelayTask task: SchedulableTask, delay: TimeInterval, reason: String)
    func scheduler(_ scheduler: PriorityScheduler, didCancelTask task: SchedulableTask)
    func schedulerDidUpdateStatistics(_ scheduler: PriorityScheduler, statistics: SchedulerStatistics)
}

// MARK: - 默认实现
extension PrioritySchedulerDelegate {
    func scheduler(_ scheduler: PriorityScheduler, didScheduleTask task: SchedulableTask) {}
    func scheduler(_ scheduler: PriorityScheduler, didExecuteTask task: SchedulableTask) {}
    func scheduler(_ scheduler: PriorityScheduler, didFailTask task: SchedulableTask, reason: String) {}
    func scheduler(_ scheduler: PriorityScheduler, didDelayTask task: SchedulableTask, delay: TimeInterval, reason: String) {}
    func scheduler(_ scheduler: PriorityScheduler, didCancelTask task: SchedulableTask) {}
    func schedulerDidUpdateStatistics(_ scheduler: PriorityScheduler, statistics: SchedulerStatistics) {}
}

// MARK: - PriorityScheduler 主类
final class PriorityScheduler {
    static let shared = PriorityScheduler()

    // MARK: - 属性
    private let taskQueue = PriorityTaskQueue()
    private var delayedTasks: [DelayedTaskRecord] = []
    private let delayedTasksLock = NSLock()

    private let creditEngine: CreditEngine
    private let creditCalculator: CreditCalculator

    private var schedulerCycle: SchedulerCycle = .normal
    private var timer: DispatchSourceTimer?
    private let schedulerQueue = DispatchQueue(label: "com.summerspark.priorityscheduler", qos: .userInitiated)

    private(set) var statistics = SchedulerStatistics()
    private let statisticsLock = NSLock()

    private var isRunning = false
    private let runningLock = NSLock()

    weak var delegate: PrioritySchedulerDelegate?

    // 积分不足延迟配置
    private var insufficientCreditDelay: TimeInterval = 5.0
    private var maxDelayAttempts = 3

    // 任务执行回调
    var taskExecutionHandler: ((SchedulableTask) -> Bool)?

    // MARK: - 初始化
    init(creditEngine: CreditEngine = .shared, creditCalculator: CreditCalculator = .shared) {
        self.creditEngine = creditEngine
        self.creditCalculator = creditCalculator
    }

    deinit {
        stop()
    }

    // MARK: - 生命周期
    func start() {
        runningLock.lock()
        guard !isRunning else {
            runningLock.unlock()
            return
        }
        isRunning = true
        runningLock.unlock()

        startTimer()
    }

    func stop() {
        runningLock.lock()
        isRunning = false
        runningLock.unlock()

        timer?.cancel()
        timer = nil
    }

    // MARK: - 调度周期配置
    func setSchedulerCycle(_ cycle: SchedulerCycle) {
        schedulerCycle = cycle
        if isRunning {
            stop()
            start()
        }
    }

    func getSchedulerCycle() -> SchedulerCycle {
        return schedulerCycle
    }

    // MARK: - 积分不足延迟配置
    func setInsufficientCreditDelay(_ delay: TimeInterval, maxAttempts: Int) {
        insufficientCreditDelay = delay
        maxDelayAttempts = maxAttempts
    }

    // MARK: - 任务调度
    @discardableResult
    func scheduleTask(
        taskType: ScheduledTask.TaskType,
        priority: MessagePriority,
        creditCost: Int,
        sourceNodeId: String,
        targetNodeId: String? = nil,
        deadline: Date? = nil,
        payload: Data? = nil
    ) -> String? {
        guard creditCost >= 0 else { return nil }

        let account = creditEngine.getAccount()
        let task = SchedulableTask(
            taskType: taskType,
            priority: priority,
            creditCost: creditCost,
            deadline: deadline,
            maxRetries: 3,
            sourceNodeId: sourceNodeId,
            targetNodeId: targetNodeId,
            payload: payload,
            creditTier: account.tier
        )

        taskQueue.enqueue(task)

        statisticsLock.lock()
        statistics.totalScheduled += 1
        statistics.updatePeakQueueSize(taskQueue.count)
        statisticsLock.unlock()

        delegate?.scheduler(self, didScheduleTask: task)

        return task.id
    }

    @discardableResult
    func scheduleTask(_ task: SchedulableTask) -> Bool {
        taskQueue.enqueue(task)

        statisticsLock.lock()
        statistics.totalScheduled += 1
        statistics.updatePeakQueueSize(taskQueue.count)
        statisticsLock.unlock()

        delegate?.scheduler(self, didScheduleTask: task)

        return true
    }

    // MARK: - 任务管理
    func cancelTask(taskId: String) -> Bool {
        guard let task = taskQueue.remove(taskId: taskId) else {
            return false
        }

        // 如果任务已执行部分逻辑，尝试退还积分
        if task.state == .executing {
            let refundAmount = Double(task.creditCost) * 0.5
            _ = creditEngine.earn(refundAmount, reason: "Task cancellation refund")
            statisticsLock.lock()
            statistics.recordRefund(amount: refundAmount)
            statisticsLock.unlock()
        }

        statisticsLock.lock()
        statistics.recordCancellation()
        statisticsLock.unlock()

        delegate?.scheduler(self, didCancelTask: task)

        return true
    }

    func getTask(taskId: String) -> SchedulableTask? {
        return taskQueue.allTasks().first { $0.id == taskId }
    }

    func getPendingTasks() -> [SchedulableTask] {
        return taskQueue.allTasks().filter {
            if case .pending = $0.state { return true }
            return false
        }
    }

    func getDelayedTasks() -> [DelayedTaskRecord] {
        delayedTasksLock.lock()
        defer { delayedTasksLock.unlock() }
        return delayedTasks
    }

    func clearAllTasks() {
        let tasks = taskQueue.allTasks()
        taskQueue.clear()

        delayedTasksLock.lock()
        delayedTasks.removeAll()
        delayedTasksLock.unlock()

        for task in tasks {
            delegate?.scheduler(self, didCancelTask: task)
        }
    }

    // MARK: - 队列状态
    var queueSize: Int {
        return taskQueue.count
    }

    var currentStatistics: SchedulerStatistics {
        statisticsLock.lock()
        defer { statisticsLock.unlock() }
        return statistics
    }

    func resetStatistics() {
        statisticsLock.lock()
        statistics.reset()
        statisticsLock.unlock()
    }

    // MARK: - 定时器管理
    private func startTimer() {
        timer?.cancel()

        timer = DispatchSource.makeTimerSource(queue: schedulerQueue)
        timer?.schedule(deadline: .now(), repeating: schedulerCycle)
        timer?.setEventHandler { [weak self] in
            self?.processScheduledTasks()
        }
        timer?.resume()
    }

    // MARK: - 任务处理
    private func processScheduledTasks() {
        // 处理延迟任务
        processDelayedTasks()

        // 处理队列任务
        while let task = taskQueue.peek() {
            // 更新动态优先级
            let elapsedTime = Date().timeIntervalSince(task.createdAt)
            task.dynamicPriority = task.calculateDynamicPriority(creditEngine: creditEngine, elapsedTime: elapsedTime)

            // 检查是否过期
            if task.isExpired {
                _ = taskQueue.dequeue()
                task.state = .failed(reason: "Task expired")
                statisticsLock.lock()
                statistics.recordFailure()
                statisticsLock.unlock()
                delegate?.scheduler(self, didFailTask: task, reason: "Task expired")
                continue
            }

            // 检查积分是否足够
            let balance = creditEngine.getBalance()
            if balance < Double(task.creditCost) {
                handleInsufficientCredit(for: task)
                break
            }

            // 尝试执行任务
            if executeTask(task) {
                _ = taskQueue.dequeue()
            } else {
                break
            }
        }

        // 通知统计更新
        notifyStatisticsUpdate()
    }

    private func processDelayedTasks() {
        delayedTasksLock.lock()
        defer { delayedTasksLock.unlock() }

        var readyTasks: [DelayedTaskRecord] = []
        var remainingTasks: [DelayedTaskRecord] = []

        for record in delayedTasks {
            if record.isReady {
                readyTasks.append(record)
            } else {
                remainingTasks.append(record)
            }
        }

        delayedTasks = remainingTasks

        // 将就绪的任务重新加入队列
        for record in readyTasks {
            var task = record.task
            task.state = .pending
            task.dynamicPriority = Double(record.originalPriority.rawValue)
            taskQueue.enqueue(task)

            delegate?.scheduler(self, didDelayTask: task, delay: insufficientCreditDelay, reason: record.reason)
        }
    }

    private func handleInsufficientCredit(for task: SchedulableTask) {
        var mutableTask = task

        if mutableTask.retryCount >= maxDelayAttempts {
            // 达到最大延迟次数，标记失败
            _ = taskQueue.dequeue()
            mutableTask.state = .failed(reason: "Insufficient credit after max retries")

            statisticsLock.lock()
            statistics.recordFailure()
            statisticsLock.unlock()

            delegate?.scheduler(self, didFailTask: mutableTask, reason: "Insufficient credit after max retries")
        } else {
            // 延迟任务
            _ = taskQueue.dequeue()
            mutableTask.retryCount += 1
            mutableTask.state = .delayed(remainingDelay: insufficientCreditDelay)

            let record = DelayedTaskRecord(
                task: SchedulableTask(
                    id: mutableTask.id,
                    taskType: mutableTask.taskType,
                    priority: mutableTask.priority,
                    creditCost: mutableTask.creditCost,
                    createdAt: mutableTask.createdAt,
                    deadline: mutableTask.deadline,
                    maxRetries: mutableTask.maxRetries,
                    sourceNodeId: mutableTask.sourceNodeId,
                    targetNodeId: mutableTask.targetNodeId,
                    payload: mutableTask.payload,
                    creditTier: mutableTask.creditTier
                ),
                delayedUntil: Date().addingTimeInterval(insufficientCreditDelay),
                originalPriority: mutableTask.priority,
                reason: "Insufficient credit balance"
            )

            delayedTasksLock.lock()
            delayedTasks.append(record)
            delayedTasksLock.unlock()

            statisticsLock.lock()
            statistics.recordDelay()
            statisticsLock.unlock()

            delegate?.scheduler(self, didDelayTask: mutableTask, delay: insufficientCreditDelay, reason: "Insufficient credit")
        }
    }

    @discardableResult
    private func executeTask(_ task: SchedulableTask) -> Bool {
        task.state = .executing

        // 扣除积分
        let consumed = creditEngine.consume(Double(task.creditCost), reason: "Task execution: \(task.taskType.rawValue)")

        guard consumed else {
            task.state = .failed(reason: "Failed to consume credits")
            statisticsLock.lock()
            statistics.recordFailure()
            statisticsLock.unlock()
            delegate?.scheduler(self, didFailTask: task, reason: "Failed to consume credits")
            return false
        }

        // 执行任务回调
        if let handler = taskExecutionHandler {
            let success = handler(task)
            if success {
                task.state = .completed
                statisticsLock.lock()
                statistics.recordExecution(creditCost: Double(task.creditCost))
                statisticsLock.unlock()
                delegate?.scheduler(self, didExecuteTask: task)
                return true
            } else {
                task.state = .failed(reason: "Execution handler returned failure")
                // 退还积分
                _ = creditEngine.earn(Double(task.creditCost), reason: "Task execution failed refund")
                statisticsLock.lock()
                statistics.recordFailure()
                statistics.recordRefund(amount: Double(task.creditCost))
                statisticsLock.unlock()
                delegate?.scheduler(self, didFailTask: task, reason: "Execution handler returned failure")
                return false
            }
        }

        // 默认成功
        task.state = .completed
        statisticsLock.lock()
        statistics.recordExecution(creditCost: Double(task.creditCost))
        statisticsLock.unlock()
        delegate?.scheduler(self, didExecuteTask: task)

        return true
    }

    private func notifyStatisticsUpdate() {
        statisticsLock.lock()
        let stats = statistics
        statisticsLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.schedulerDidUpdateStatistics(self, statistics: stats)
        }
    }

    // MARK: - 批量操作
    func scheduleBatch(tasks: [(type: ScheduledTask.TaskType, priority: MessagePriority, cost: Int, source: String, target: String?)]) {
        for taskInfo in tasks {
            scheduleTask(
                taskType: taskInfo.type,
                priority: taskInfo.priority,
                creditCost: taskInfo.cost,
                sourceNodeId: taskInfo.source,
                targetNodeId: taskInfo.target
            )
        }
    }

    func getTasksBySourceNode(_ nodeId: String) -> [SchedulableTask] {
        return taskQueue.tasksForNode(nodeId)
    }

    func getTasksByPriority(_ priority: MessagePriority) -> [SchedulableTask] {
        return taskQueue.allTasks().filter { $0.priority == priority }
    }

    // MARK: - 优先级调整
    func boostPriority(taskId: String, boostAmount: Double) -> Bool {
        guard let task = taskQueue.allTasks().first(where: { $0.id == taskId }) else {
            return false
        }

        task.dynamicPriority += boostAmount
        return true
    }

    func reducePriority(taskId: String, reductionAmount: Double) -> Bool {
        guard let task = taskQueue.allTasks().first(where: { $0.id == taskId }) else {
            return false
        }

        task.dynamicPriority = max(0, task.dynamicPriority - reductionAmount)
        return true
    }

    // MARK: - 紧急调度
    func scheduleUrgentTask(
        taskType: ScheduledTask.TaskType,
        creditCost: Int,
        sourceNodeId: String,
        targetNodeId: String? = nil,
        payload: Data? = nil
    ) -> String? {
        return scheduleTask(
            taskType: taskType,
            priority: .critical,
            creditCost: creditCost,
            sourceNodeId: sourceNodeId,
            targetNodeId: targetNodeId,
            deadline: Date().addingTimeInterval(5.0),
            payload: payload
        )
    }

    // MARK: - 队列重组（用于动态优先级更新）
    func reorganizeQueue() {
        let allTasks = taskQueue.allTasks()
        taskQueue.clear()

        for task in allTasks {
            let elapsedTime = Date().timeIntervalSince(task.createdAt)
            task.dynamicPriority = task.calculateDynamicPriority(creditEngine: creditEngine, elapsedTime: elapsedTime)
            taskQueue.enqueue(task)
        }
    }
}
