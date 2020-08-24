//
//  OSLogStream.swift
//  LoggingTest
//
//  Created by Peter Steinberger on 24.08.20.
//

// Requires importing https://github.com/apple/llvm-project/blob/apple/master/lldb/tools/debugserver/source/MacOSX/DarwinLog/ActivityStreamSPI.h via bridging header
import Foundation

class OSLogStream {
    private var stream: os_activity_stream_t!
    private let filterPid = ProcessInfo.processInfo.processIdentifier;
    private let logHandler: (LogMessage) -> Void

    private let OSActivityStreamForPID: os_activity_stream_for_pid_t
    private let OSActivityStreamResume: os_activity_stream_resume_t
    private let OSActivityStreamCancel: os_activity_stream_cancel_t
    private let OSLogCopyFormattedMessage: os_log_copy_formatted_message_t

    struct LogMessage {
        let msg: String
        let date: Date
    }

    init?(logHandler: @escaping (LogMessage) -> Void) {
        self.logHandler = logHandler

        guard let handle = dlopen("/System/Library/PrivateFrameworks/LoggingSupport.framework/LoggingSupport", RTLD_NOW) else { return nil }
        OSActivityStreamForPID = unsafeBitCast(dlsym(handle, "os_activity_stream_for_pid"), to: os_activity_stream_for_pid_t.self)
        OSActivityStreamResume = unsafeBitCast(dlsym(handle, "os_activity_stream_resume"), to: os_activity_stream_resume_t.self)
        OSActivityStreamCancel = unsafeBitCast(dlsym(handle, "os_activity_stream_cancel"), to: os_activity_stream_cancel_t.self)
        OSLogCopyFormattedMessage = unsafeBitCast(dlsym(handle, "os_log_copy_formatted_message"), to: os_log_copy_formatted_message_t.self)

        let activity_stream_flags = os_activity_stream_flag_t(OS_ACTIVITY_STREAM_HISTORICAL | OS_ACTIVITY_STREAM_PROCESS_ONLY) // NSLog, ASL
        stream = OSActivityStreamForPID(filterPid, activity_stream_flags, { entryPointer, error in
            guard error == 0, let entry = entryPointer?.pointee else { return false }
            return self.handleStreamEntry(entry)
        })
        guard stream != nil else { return nil }
        OSActivityStreamResume(stream)
    }

    deinit {
        if let stream = stream {
            OSActivityStreamCancel(stream)
        }
    }

    private func handleStreamEntry(_ entry: os_activity_stream_entry_s) -> Bool {
        guard entry.type == OS_ACTIVITY_STREAM_TYPE_LOG_MESSAGE || entry.type == OS_ACTIVITY_STREAM_TYPE_LEGACY_LOG_MESSAGE else { return true }

        var osLogMessage = entry.log_message
        guard let messageTextC = OSLogCopyFormattedMessage(&osLogMessage) else { return false }
        let message = String(utf8String: messageTextC)
        free(messageTextC)
        let date = Date(timeIntervalSince1970: TimeInterval(osLogMessage.tv_gmt.tv_sec))
        let logMessage = LogMessage(msg: message ?? "", date: date)
        DispatchQueue.main.async { self.logHandler(logMessage) }
        return true
    }
}
