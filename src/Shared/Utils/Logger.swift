import Foundation
import os.log

// MARK: - Log Level

enum LogLevel: String {
    case debug = "DEBUG"
    case info  = "INFO"
    case warn  = "WARN"
    case error = "ERROR"

    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info:  return .info
        case .warn:  return .default
        case .error: return .error
        }
    }

    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info:  return "📌"
        case .warn:  return "⚠️"
        case .error: return "❌"
        }
    }
}

// MARK: - Log Category

enum LogCategory: String {
    case general    = "General"
    case network    = "Network"
    case database   = "Database"
    case ui         = "UI"
    case business   = "Business"
}

// MARK: - Logger

final class Logger {
    static let shared = Logger()

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.summerspark.app"
    private var loggers: [LogCategory: os.Logger] = [:]
    private var isEnabled: Bool = true
    private var minLevel: LogLevel = .debug

    private init() {
        setupLoggers()
    }

    private func setupLoggers() {
        for category in [LogCategory.general, .network, .database, .ui, .business] {
            let logger = os.Logger(subsystem: subsystem, category: category.rawValue)
            loggers[category] = logger
        }
    }

    // MARK: - Configuration

    func configure(minLevel: LogLevel = .debug, enabled: Bool = true) {
        self.minLevel = minLevel
        self.isEnabled = enabled
    }

    // MARK: - Logging

    func log(
        _ message: String,
        level: LogLevel = .info,
        category: LogCategory = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard isEnabled else { return }
        guard shouldLog(level: level) else { return }

        let logger = loggers[category] ?? os.Logger(subsystem: subsystem, category: LogCategory.general.rawValue)
        let fileName = (file as NSString).lastPathComponent
        let formattedMessage = "\(fileName):\(line) \(function) → \(message)"

        switch level {
        case .debug:
            logger.debug("\(formattedMessage, privacy: .public)")
        case .info:
            logger.info("\(formattedMessage, privacy: .public)")
        case .warn:
            logger.warning("\(formattedMessage, privacy: .public)")
        case .error:
            logger.error("\(formattedMessage, privacy: .public)")
        }

        #if DEBUG
        print("\(level.emoji) [\(level.rawValue)] [\(category.rawValue)] \(formattedMessage)")
        #endif
    }

    func debug(_ message: String, category: LogCategory = .general,
               file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    func info(_ message: String, category: LogCategory = .general,
              file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func warn(_ message: String, category: LogCategory = .general,
              file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warn, category: category, file: file, function: function, line: line)
    }

    func error(_ message: String, category: LogCategory = .general,
               file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    func error(_ error: Error, category: LogCategory = .general,
               file: String = #file, function: String = #function, line: Int = #line) {
        log(error.localizedDescription, level: .error, category: category, file: file, function: function, line: line)
    }

    // MARK: - Private

    private func shouldLog(level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warn, .error]
        guard let currentIndex = levels.firstIndex(of: level),
              let minIndex = levels.firstIndex(of: minLevel) else { return true }
        return currentIndex >= minIndex
    }
}

// MARK: - Global Convenience

func Log(_ message: String, level: LogLevel = .info, category: LogCategory = .general) {
    Logger.shared.log(message, level: level, category: category)
}

func LogDebug(_ message: String, category: LogCategory = .general) {
    Logger.shared.debug(message, category: category)
}

func LogInfo(_ message: String, category: LogCategory = .general) {
    Logger.shared.info(message, category: category)
}

func LogWarn(_ message: String, category: LogCategory = .general) {
    Logger.shared.warn(message, category: category)
}

func LogError(_ message: String, category: LogCategory = .general) {
    Logger.shared.error(message, category: category)
}

func LogError(_ error: Error, category: LogCategory = .general) {
    Logger.shared.error(error, category: category)
}