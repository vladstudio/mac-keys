import AppKit

protocol ConfigManagerDelegate: AnyObject {
    func configDidUpdate(_ config: Config)
    func configDidFail(_ error: String)
}

class ConfigManager {
    weak var delegate: ConfigManagerDelegate?

    let configPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.keys"
    }()

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?

    func load() {
        do {
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            let config = try ConfigParser.parse(content)
            delegate?.configDidUpdate(config)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            createDefault()
            delegate?.configDidFail("Created default config at \(configPath)")
        } catch {
            delegate?.configDidFail("\(error)")
        }
    }

    func startWatching() {
        watchFile()
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
        pollTimer?.cancel()
        pollTimer = nil
    }

    func openInEditor() {
        let url = URL(fileURLWithPath: configPath)
        NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private func createDefault() {
        let content = """
        # Keys — https://keys.vlad.studio
        #
        # [[remap]]
        # caps_lock f20
        #
        # [[snippet]]
        # ":hi" "Hello world"
        """
        FileManager.default.createFile(atPath: configPath, contents: content.data(using: .utf8))
    }

    private func watchFile() {
        stopWatching()

        let fd = Darwin.open(configPath, O_EVTONLY)
        if fd == -1 {
            startPolling()
            return
        }

        fileDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            self.load()
            if flags.contains(.delete) || flags.contains(.rename) {
                self.stopWatching()
                self.startPolling()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.fileDescriptor != -1 {
                Darwin.close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        dispatchSource = source
        source.resume()
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if FileManager.default.fileExists(atPath: self.configPath) {
                self.pollTimer?.cancel()
                self.pollTimer = nil
                self.load()
                self.watchFile()
            }
        }
        pollTimer = timer
        timer.resume()
    }
}
