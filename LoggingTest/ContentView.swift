//
//  ContentView.swift
//  LoggingTest
//
//  Created by Peter Steinberger on 23.08.20.
//

import SwiftUI
import OSLog
import Combine

let subsystem = "com.steipete.LoggingTest"

func getLogEntries() throws -> [OSLogEntryLog] {
    // FB8269189: OSLogStore does not work iOS.
    let logStore = try OSLogStore(scope: .currentProcessIdentifier)
    let oneHourAgo = logStore.position(date: Date().addingTimeInterval(-3600))

    #if os(macOS)
        let allEntries = try logStore.getEntries(at: oneHourAgo)
    #else
        // FB8518476: The Swift shims for for the entries enumerator are missing.
        let allEntries = try Array(logStore.__entriesEnumerator(position: oneHourAgo, predicate: nil))
    #endif

    // FB8518539: Using NSPredicate to filter the subsystem doesn't seem to work.
    return allEntries
        .compactMap { $0 as? OSLogEntryLog }
        .filter { $0.subsystem == subsystem }
}

func printLogEntries() -> Future<[OSLogEntryLog], Error> {
    return Future { promise in
        DispatchQueue.global(qos: .utility).async {
            do {
                let logEntries = try getLogEntries()
                DispatchQueue.main.async {
                    promise(.success(logEntries))
                }
            } catch {
                DispatchQueue.main.async {
                    promise(.failure(error))
                }
            }
        }
    }
}

func printOSLog() {
    let lookback = Date().addingTimeInterval(-36000) // one hour ago
    //let searchPredicate = NSPredicate(format: "(subsystem contains %@) AND (date > %@)", subsystem, lookback as NSDate)
    let searchPredicate = NSPredicate(format: "(subsystem contains %@)", subsystem)

    do {
        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        //let logPosition = logStore.position(timeIntervalSinceEnd: 0.0)
        let oneHourAgo = logStore.position(date: lookback)
        let enumerator = try logStore.__entriesEnumerator(position: oneHourAgo, predicate: searchPredicate)
        var next: Any?
        repeat {
            next = enumerator.nextObject()
            //dump(next)

            guard let entry = next as? OSLogEntryLog else { return }
            print("Timestamp \(entry.date), sender: \(entry.sender), contents: \(entry.composedMessage)")


        } while next != nil

        //let result = try store.getEntries(with: .reverse, at: logPosition, matching: searchPredicate)
        //        result.forEach {
        //        }
    } catch {
        print("Error: \(error)")
    }
}

var logStream: OSLogStream?

func setupFlexHandler() {
    guard logStream == nil else { return }

    logStream = OSLogStream { msg in
        print("Log Handler: \(msg)")
    }
}


var subscriber: AnyCancellable?

struct ContentView: View {
    let logger = Logger(subsystem: subsystem, category: "main")

    var logLevels = ["Default", "Info", "Debug", "Error", "Fault"]
    @State private var selectedLogLevel = 0

    @State private var logMessages: [OSLogEntryLog] = []

    private func updateLog() {
        setupFlexHandler()
        
        subscriber = printLogEntries().sink { completion in
            print("\(completion)")
        } receiveValue: { value in
            if logMessages.count != value.count {
                logMessages = value
            }
        }
    }
    init() {
        logger.log("SwiftUI is initializing the main ContentView")
    }

    var body: some View {
        updateLog()

        return VStack {
            Text("This is a sample project to test the new logging features of iOS 14.")
                .padding()

            Picker(selection: $selectedLogLevel, label: Text("Choose Log Level")) {
                ForEach(0 ..< logLevels.count) {
                    Text(self.logLevels[$0])
                }
            }.frame(width: 400, height: 150, alignment: .center)

            Button(action: {
                switch(selectedLogLevel) {
                case 0:
                    logger.log("Default log message")
                case 1:
                    logger.info("Info log message")
                case 2:
                    logger.debug("Debug log message")
                case 3:
                    logger.error("Error log message")
                default: // 4
                    logger.fault("Fault log message")
                }

                updateLog()
            }) {
                Text("Log with Log Level \(logLevels[selectedLogLevel])")
            }.padding()

            Button(action: {
                updateLog()
            }) {
                Text("Collect Log Messages")
            }

            List {
                ForEach(logMessages, id: \.self) { entry in
                    Text("[\(entry.level.rawValue)] \(entry.date): \(entry.subsystem)-\(entry.category): \(entry.composedMessage)")
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
