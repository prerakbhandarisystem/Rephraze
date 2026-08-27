import os

public enum Log {
    public static let hotkey = Logger(subsystem: "com.prerak.rephraze", category: "hotkey")
    public static let capture = Logger(subsystem: "com.prerak.rephraze", category: "capture")
    public static let rewrite = Logger(subsystem: "com.prerak.rephraze", category: "rewrite")
    public static let app = Logger(subsystem: "com.prerak.rephraze", category: "app")
}
