//
//  Installation.swift
//  TrollInstallerX
//
//  Created by Alfie on 22/03/2024.
//

import SwiftUI

let fileManager = FileManager.default
let docsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0].path
let kernelPath = docsDir + "/kernelcache"


func checkForMDCUnsandbox() -> Bool {
    return fileManager.fileExists(atPath: docsDir + "/full_disk_access_sandbox_token.txt")
}

func getKernel(_ device: Device) -> Bool {
    if !fileManager.fileExists(atPath: kernelPath) {
        if fileManager.fileExists(atPath: Bundle.main.path(forResource: "kernelcache", ofType: "") ?? "") {
            try? fileManager.copyItem(atPath: Bundle.main.path(forResource: "kernelcache", ofType: "")!, toPath: kernelPath)
            if fileManager.fileExists(atPath: kernelPath) { return true }
        }
        if MacDirtyCow.supports(device) && checkForMDCUnsandbox() {
            let fd = open(docsDir + "/full_disk_access_sandbox_token.txt", O_RDONLY)
            if fd > 0 {
                let tokenData = get_NSString_from_file(fd)
                sandbox_extension_consume(tokenData)
                Logger.log("Copying kernelcache")
                let path = get_kernelcache_path()
                do {
                    try fileManager.copyItem(atPath: path!, toPath: kernelPath)
                    return true
                } catch {
                    Logger.log("Failed to copy kernelcache", type: .error)
                    NSLog("Failed to copy kernelcache - \(error)")
                }
            }
        }
        Logger.log("Downloading kernel")
        if !grab_kernelcache(kernelPath) {
            Logger.log("Failed to download kernel", type: .error)
            return false
        }
    }
    
    return true
}


func cleanupPrivatePreboot() -> Bool {
    // Remove /private/preboot/tmp
    let fileManager = FileManager.default
    do {
        try fileManager.removeItem(atPath: "/private/preboot/tmp")
    } catch let e {
        print("Failed to remove /private/preboot/tmp! \(e.localizedDescription)")
        return false
    }
    return true
}

func selectExploit(_ device: Device) -> KernelExploit {
    let flavour = (TIXDefaults().string(forKey: "exploitFlavour") ?? (physpuppet.supports(device) ? "physpuppet" : "landa"))
    if flavour == "landa" { return landa }
    if flavour == "physpuppet" { return physpuppet }
    if flavour == "smith" { return smith }
    return landa
}

func getCandidates() -> [InstalledApp] {
    var apps = [InstalledApp]()
    for candidate in persistenceHelperCandidates {
        if candidate.isInstalled { apps.append(candidate) }
    }
    return apps
}

@discardableResult
func doDirectInstall(_ device: Device) async -> Bool {
    
    let exploit = selectExploit(device)
    
    let iOS14 = device.version < Version("15.0")
    let supportsFullPhysRW = !(device.cpuFamily == .A8 && device.version > Version("15.1.1")) && ((device.isArm64e && device.version >= Version(major: 15, minor: 2)) || (!device.isArm64e && device.version >= Version("15.0")))
    
    Logger.log("Running on an \(device.modelIdentifier) on iOS \(device.version.readableString)")
    
    if !iOS14 {
        if !(getKernel(device)) {
            Logger.log("Failed to get kernel", type: .error)
            return false
        }
    }
    
    Logger.log("Gathering kernel information")
    if !initialise_kernel_info(kernelPath, iOS14) {
        Logger.log("Failed to patchfind kernel", type: .error)
        return false
    }
    
    Logger.log("Exploiting kernel (\(exploit.name))")
    if !exploit.initialise() {
        Logger.log("Failed to exploit the kernel", type: .error)
        return false
    }
    Logger.log("Successfully exploited the kernel", type: .success)
    post_kernel_exploit(iOS14)
    
    var trollstoreTarData: Data?
    if FileManager.default.fileExists(atPath: docsDir + "/TrollStore.tar") {
        trollstoreTarData = try? Data(contentsOf: docsURL.appendingPathComponent("TrollStore.tar"))
    }
    
    if supportsFullPhysRW {
        if device.isArm64e {
            Logger.log("Bypassing PPL (\(dmaFail.name))")
            if !dmaFail.initialise() {
                Logger.log("Failed to bypass PPL", type: .error)
                return false
            }
            Logger.log("Successfully bypassed PPL", type: .success)
        }
        
        if #available(iOS 16, *) {
            libjailbreak_kalloc_pt_init()
        }
        
        if !build_physrw_primitive() {
            Logger.log("Failed to build physical R/W primitive", type: .error)
            return false
        }
        
        if device.isArm64e {
            if !dmaFail.deinitialise() {
                Logger.log("Failed to deinitialise \(dmaFail.name)", type: .error)
                return false
            }
        }
        
        if !exploit.deinitialise() {
            Logger.log("Failed to deinitialise \(exploit.name)", type: .error)
            return false
        }
        
        Logger.log("Unsandboxing")
        if !unsandbox() {
            Logger.log("Failed to unsandbox", type: .error)
            return false
        }
        
        Logger.log("Escalating privileges")
        if !get_root_pplrw() {
            Logger.log("Failed to escalate privileges", type: .error)
            return false
        }
        if !platformise() {
            Logger.log("Failed to platformise", type: .error)
            return false
        }
    } else {
        
        Logger.log("Unsandboxing and escalating privileges")
        if !get_root_krw(iOS14) {
            Logger.log("Failed to unsandbox and escalate privileges", type: .error)
            return false
        }
    }
    
    remount_private_preboot()
    
    if let data = trollstoreTarData {
        do {
            try FileManager.default.createDirectory(atPath: "/private/preboot/tmp", withIntermediateDirectories: false)
            FileManager.default.createFile(atPath: "/private/preboot/tmp/TrollStore.tar", contents: nil)
            try data.write(to: URL(string: "file:///private/preboot/tmp/TrollStore.tar")!)
        } catch {
            print("Failed to write out TrollStore.tar - \(error.localizedDescription)")
        }
    }
    
    // Prevents download finishing between extraction and installation
    let useLocalCopy = FileManager.default.fileExists(atPath: "/private/preboot/tmp/TrollStore.tar")

    if !fileManager.fileExists(atPath: "/private/preboot/tmp/trollstorehelper") {
        Logger.log("Extracting TrollStore.tar")
        if !extractTrollStore(useLocalCopy) {
            Logger.log("Failed to extract TrollStore.tar", type: .error)
            return false
        }
    }
    
    let newCandidates = getCandidates()
    persistenceHelperCandidates = newCandidates
    
    DispatchQueue.main.sync {
        HelperAlert.shared.showAlert = true
        HelperAlert.shared.objectWillChange.send()
    }
    while HelperAlert.shared.showAlert { }
    let persistenceID = TIXDefaults().string(forKey: "persistenceHelper")
    
    if persistenceID != "" {
        if install_persistence_helper(persistenceID) {
            Logger.log("Successfully installed persistence helper!", type: .success)
        } else {
            Logger.log("Failed to install persistence helper", type: .error)
        }
    }
    
    Logger.log("Installing TrollStore")
    if !install_trollstore(useLocalCopy ? "/private/preboot/tmp/TrollStore.tar" : Bundle.main.bundlePath + "/TrollStore.tar") {
        Logger.log("Failed to install TrollStore", type: .error)
    } else {
        Logger.log("Successfully installed TrollStore!", type: .success)
    }
    
    if !cleanupPrivatePreboot() {
        Logger.log("Failed to clean up /private/preboot", type: .error)
    }
    
    if !supportsFullPhysRW {
        if !drop_root_krw(iOS14) {
            Logger.log("Failed to drop root privileges", type: .error)
            return false
        }
        if !exploit.deinitialise() {
            Logger.log("Failed to deinitialise \(exploit.name)", type: .error)
            return false
        }
    }
    
    return true
}

func doIndirectInstall(_ device: Device) async -> Bool {
    let exploit = selectExploit(device)
    
    Logger.log("Running on an \(device.modelIdentifier) on iOS \(device.version.readableString)")
    
    if !extractTrollStoreIndirect() {
        return false
    }
    defer {
        cleanupIndirectInstall()
    }
    
    if !(getKernel(device)) {
        Logger.log("Failed to get kernel", type: .error)
    }
    
    Logger.log("Gathering kernel information")
    if !initialise_kernel_info(kernelPath, false) {
        Logger.log("Failed to patchfind kernel", type: .error)
        return false
    }
    
    Logger.log("Exploiting kernel (\(exploit.name))")
    if !exploit.initialise() {
        Logger.log("Failed to exploit the kernel", type: .error)
        return false
    }
    defer {
        if !exploit.deinitialise() {
            Logger.log("Failed to deinitialise \(exploit.name)", type: .error)
        }
    }
    Logger.log("Successfully exploited the kernel", type: .success)
    post_kernel_exploit(false)
    
    var path: UnsafePointer<CChar>? = nil
    let pathPointer = withUnsafeMutablePointer(to: &path) { ptr in
        UnsafeMutablePointer<UnsafePointer<CChar>?>.init(ptr)
    }
    if is_persistence_helper_installed(pathPointer) {
        Logger.log("Persistence helper already installed! (\(path == nil ? "unknown" : String(cString: path!)))", type: .warning)
        return false
    }
    
    let apps = get_installed_apps() as? [String]
    var candidates = [InstalledApp]()
    for app in apps ?? [String]() {
        print(app)
        for candidate in persistenceHelperCandidates {
            if app.components(separatedBy: "/")[1].replacingOccurrences(of: ".app", with: "") == candidate.bundleName {
                candidates.append(candidate)
                candidates[candidates.count - 1].isInstalled = true
                candidates[candidates.count - 1].bundlePath = "/var/containers/Bundle/Application/" + app
            }
        }
    }
    
    persistenceHelperCandidates = candidates
    
    DispatchQueue.main.sync {
        HelperAlert.shared.showAlert = true
        HelperAlert.shared.objectWillChange.send()
    }
    while HelperAlert.shared.showAlert { }
    let persistenceID = TIXDefaults().string(forKey: "persistenceHelper")
    
    var pathToInstall = ""
    for candidate in persistenceHelperCandidates {
        if persistenceID == candidate.bundleIdentifier {
            pathToInstall = candidate.bundlePath!
        }
    }
    var success = false
    if !install_persistence_helper_via_vnode(pathToInstall) {
        Logger.log("Failed to install persistence helper", type: .error)
    } else {
        Logger.log("Successfully installed persistence helper!", type: .success)
        success = true
    }
    
    if success {
        let verbose = TIXDefaults().bool(forKey: "verbose")
        Logger.log("Respringing in \(verbose ? "15" : "5") seconds")
        DispatchQueue.global().async {
            sleep(verbose ? 15 : 5)
            restartBackboard()
        }
    }
    
    return true
}


/// 越狱安装：不跑 exploit，直接借越狱 root 走 TrollStore Helper 的流程。
@discardableResult
func doJailbreakInstall(_ device: Device) async -> Bool {
    let jb = JailbreakDetector.check()
    Logger.log("越狱检测：\(jb.summary)")
    guard jb.isJailbroken else {
        Logger.log("未检测到越狱，越狱安装不可用；请用普通安装", type: .error)
        return false
    }
    do {
        let payload = try JBInstaller.stagePayload()
        Logger.log("payload：\(payload)")
        let dir = (payload as NSString).deletingLastPathComponent
        JBInstaller.spellingEnsureEntitlements(at: dir)
        let script = JBInstaller.installScript(payload: payload, rootless: jb.rootless)
        let (ok, out) = try JBInstaller.run(script: script, rootless: jb.rootless)
        for line in out.split(separator: "\n") where !line.isEmpty {
            Logger.log(String(line), type: line.contains("STEP_FAIL") ? .error : .info)
        }
        if ok { Logger.log("TrollStore 已装入，用 uicache 刷图标后桌面出现", type: .success) }
        return ok
    } catch {
        Logger.log("越狱安装失败：\(error.localizedDescription)", type: .error)
        return false
    }
}


// MARK: - merged from Jailbreak.swift


struct JailbreakStatus {
    var isJailbroken = false
    var rootless = false
    var rootPrefix = ""
    var markers: [String] = []
    var schemes: [String] = []

    var hasTrollStore = false
    var hasSileo = false
    var hasFilza = false

    var summary: String {
        guard isJailbroken else { return "未越狱" }
        var s = "已越狱" + (rootless ? "（rootless）" : "")
        if !markers.isEmpty { s += " · 标记 \(markers.count) 项" }
        if hasSileo { s += " · Sileo" }
        if hasTrollStore { s += " · TrollStore" }
        if hasFilza { s += " · Filza" }
        return s
    }
}

enum JailbreakDetector {
    static let markers = [
        "/var/jb", "/var/jb/usr/bin/sileo", "/var/jb/usr/bin/bash", "/var/jb/usr/bin/ldid",
        "/var/jb/Library/MobileSubstrate", "/var/jb/usr/lib/libroot.dylib",
        "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
        "/bin/bash", "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/dpkg",
        "/.installed_dopamine", "/var/jb/.installed_dopamine"
    ]

    static func check() -> JailbreakStatus {
        var st = JailbreakStatus()
        for p in markers where FileManager.default.fileExists(atPath: p) { st.markers.append(p) }
        st.rootless = st.markers.contains { $0.hasPrefix("/var/jb") }
        st.rootPrefix = st.rootless ? "/var/jb" : ""

        for s in ["cydia://", "sileo://", "zbra://", "filza://", "trollstore://"] {
            if let u = URL(string: s), UIApplication.shared.canOpenURL(u) { st.schemes.append(s) }
        }
        st.hasSileo = st.schemes.contains("sileo://") || st.schemes.contains("zbra://")
        st.hasFilza = st.schemes.contains("filza://")
        st.hasTrollStore = st.schemes.contains("trollstore://")
            || FileManager.default.fileExists(atPath: "/Applications/TrollStore.app")
            || FileManager.default.fileExists(atPath: "/var/jb/Applications/TrollStore.app")

        // 沙盒逃逸试探
        let probe = "/var/mobile/.tix_jb_probe"
        if (try? "x".write(toFile: probe, atomically: true, encoding: .utf8)) != nil {
            try? FileManager.default.removeItem(atPath: probe)
            st.isJailbroken = true
        }
        st.isJailbroken = st.isJailbroken || !st.markers.isEmpty
            || st.schemes.contains { $0.hasPrefix("cydia") || $0.hasPrefix("sileo") || $0.hasPrefix("zbra") }
        return st
    }
}


// MARK: - merged from TrollStoreHelperInstall.swift


enum JBInstallError: LocalizedError {
    case notJailbroken
    case noPayload
    case spawnDenied(String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case .notJailbroken: return "本机未检测到越狱，越狱安装不可用"
        case .noPayload: return "包里没有 TrollStore.tar"
        case .spawnDenied(let s): return "越狱侧执行被拒：\(s)"
        case .stepFailed(let s): return s
        }
    }
}

enum JBInstaller {

    /// 把 TrollStore.tar 落到越狱可写目录；写不进就退回 App 沙盒，脚本里再拷。
    static func stagePayload() throws -> String {
        guard let src = Bundle.main.path(forResource: "TrollStore.tar", ofType: nil),
              let data = try? Data(contentsOf: URL(fileURLWithPath: src)) else {
            throw JBInstallError.noPayload
        }
        // 先在包内找，再找之前下载到 Documents 的那份
        if let bundled = Bundle.main.path(forResource: "TrollStore", ofType: "tar"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: bundled)) {
            let dir = "/var/jb/tmp/mst-trollstore"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if (try? data.write(to: URL(fileURLWithPath: dir + "/TrollStore.tar"))) != nil {
                return dir + "/TrollStore.tar"
            }
        }
        let candidates = ["/var/jb/tmp/mst-trollstore", "/private/preboot/tmp", docsDir]
        for dir in candidates {
            let path = dir + "/TrollStore.tar"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            if (try? data.write(to: URL(fileURLWithPath: path))) != nil {
                return path
            }
        }
        throw JBInstallError.stepFailed("TrollStore.tar 无处可写（沙盒与越狱目录都失败）")
    }

    /// 组脚本：rootless 与 rootful 路径都覆盖。
    static func installScript(payload: String, rootless: Bool) -> String {
        let jb = rootless ? "/var/jb" : ""
        return """
        #!/bin/bash
        set -u
        JB="\(jb)"
        export PATH="\(jb)/usr/bin:\(jb)/bin:\(jb)/usr/sbin:\(jb)/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        export HOME="/var/mobile"
        TMP="${JB}/tmp/mst-ts-$$"
        ENT="$TMP/ents.plist"
        mkdir -p "$TMP" || { echo "STEP_FAIL mkdir $TMP"; exit 11; }
        echo "STEP probe"
        id 2>&1
        echo "uid=$(id -u 2>/dev/null) euid=$(id -u 2>/dev/null)"
        for d in "$JB" "$JB/Applications" "/var/containers/Bundle/Application" "/var/mobile/Documents" "/var/mobile/Library"; do
          if [ -w "$d" ]; then W=yes; else W=no; fi
          printf "DIR %s writable=%s owner=%s\n" "$d" "$W" "$(ls -ld "$d" 2>/dev/null | awk '{print $3}')(raw)"
        done
        echo "STEP sudo probe"
        if command -v sudo >/dev/null 2>&1; then sudo -n id 2>&1 || echo "sudo: needs password"; else echo "sudo: not found"; fi
        echo "STEP ts-lite probe"
        ls -d "$JB/Applications"/*.app 2>/dev/null | head -20
        echo "STEP tar"
        tar xf "\(payload)" -C "$TMP" 2>&1 || { echo "STEP_FAIL tar"; exit 12; }
        chmod -R +x "$TMP/TrollStore.app" 2>/dev/null

        echo "STEP write ents"
        {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0"><dict>'
        echo '<key>platform-application</key><true/>'
        echo '<key>com.apple.private.security.no-sandbox</key><true/>'
        echo '<key>com.apple.private.security.container-required</key><false/>'
        echo '<key>com.apple.private.cs.debugger</key><true/>'
        echo '<key>get-task-allow</key><true/>'
        echo '</dict></plist>'
        } > "$ENT"
        [ -s "$ENT" ] || { echo "STEP_FAIL write ents.plist"; exit 13; }

        Ldid="$JB/usr/bin/ldid"
        [ -x "$Ldid" ] || Ldid="/usr/bin/ldid"
        if [ -x "$Ldid" ]; then
          echo "STEP ldid platform-application"
          "$Ldid" -S"$ENT" "$TMP/TrollStore.app/trollstorehelper" 2>&1 || echo "STEP note ldid helper"
          "$Ldid" -S"$ENT" "$TMP/TrollStore.app/TrollStore" 2>&1 || echo "STEP note ldid app"
          "$Ldid" -S"$ENT" "$TMP/TrollStore.app/PersistenceHelper" 2>&1 || echo "STEP note ldid ph"
        else
          echo "STEP ldid missing"
        fi

        echo "STEP install app"
        H="$TMP/TrollStore.app/trollstorehelper"
        "$H" install "$TMP/TrollStore.app" 2>&1
        RC=$?
        echo "STEP helper-rc $RC"
        DEST=""
        if [ $RC -eq 0 ]; then
          DEST="$TMP/TrollStore.app"
          "$H" refresh 2>&1 || true
        else
          # rootless 下 App 是 mobile，拿不到 root；改走 /var/jb/Applications（mobile 可写）
          echo "STEP rootless fallback"
          APPDIR="$JB/Applications"
          mkdir -p "$APPDIR" || { echo "STEP_FAIL mkdir $APPDIR"; exit 15; }
          DEST="$APPDIR/TrollStore.app"
          rm -rf "$DEST"
          cp -a "$TMP/TrollStore.app" "$DEST" || {
            echo "STEP note cp failed, retry container"
            DEST="/var/mobile/Documents/mst-apps/TrollStore.app"
            mkdir -p /var/mobile/Documents/mst-apps 2>&1
            rm -rf "$DEST"
            cp -a "$TMP/TrollStore.app" "$DEST" || { echo "STEP_FAIL cp $DEST"; exit 16; }
          }
          chown -R mobile:mobile "$DEST" 2>/dev/null
          chmod -R +x "$DEST" 2>/dev/null
          if [ -x "$Ldid" ]; then
            "$Ldid" -S"$ENT" "$DEST/trollstorehelper" 2>&1 || true
            "$Ldid" -S"$ENT" "$DEST/TrollStore" 2>&1 || true
            "$Ldid" -S"$ENT" "$DEST/PersistenceHelper" 2>&1 || true
          fi
          echo "STEP installed $DEST"
        fi

        echo "STEP uicache"
        UIC="$JB/usr/bin/uicache"
        [ -x "$UIC" ] || UIC="/usr/bin/uicache"
        if [ -x "$UIC" ]; then
          [ -n "$DEST" ] && "$UIC" -p "$DEST" 2>&1
          "$UIC" -a 2>&1
        fi
        echo "STEP icon-cache"
        rm -rf /var/mobile/Library/Caches/com.apple.IconsCache 2>/dev/null
        rm -rf /var/mobile/Library/Caches/com.apple.SpringBoard 2>/dev/null
        echo "STEP respring"
        killall -9 SpringBoard 2>/dev/null || sbreload 2>/dev/null || true
        rm -rf "$TMP"
        echo "STEP done"
        """
    }

    /// 用越狱侧 bash 执行脚本；返回 (是否成功, 输出)。
    static func run(script: String, rootless: Bool) throws -> (Bool, String) {
        let shells = rootless
            ? ["/var/jb/usr/bin/bash", "/var/jb/usr/bin/sh", "/bin/bash", "/bin/sh"]
            : ["/bin/bash", "/bin/sh"]
        let logPath = docsDir + "/mst-jb-install.log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        guard let logFH = FileHandle(forWritingAtPath: logPath) else {
            throw JBInstallError.stepFailed("日志文件打不开")
        }
        defer { try? logFH.close() }

        guard let shell = shells.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw JBInstallError.spawnDenied("找不到可执行的 shell（/var/jb 不可达或已失去越狱状态）")
        }

        var pid: pid_t = 0
        let wrapped = "export PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin\n" +
                      "exec > \(logPath) 2>&1\n" + script
        let argv: [String] = [shell, "-c", wrapped]
        var argvC: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) }
        argvC.append(nil)
        defer { for p in argvC where p != nil { free(UnsafeMutableRawPointer(p!)) } }

        var envpC: [UnsafeMutablePointer<CChar>?] = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") }
        envpC.append(nil)
        defer { for p in envpC where p != nil { free(UnsafeMutableRawPointer(p!)) } }

        var rc: Int32 = -1
        argvC.withUnsafeBufferPointer { buf in
            envpC.withUnsafeBufferPointer { ebuf in
                rc = posix_spawn(&pid, shell, nil, nil,
                                 UnsafeMutablePointer(mutating: buf.baseAddress),
                                 UnsafeMutablePointer(mutating: ebuf.baseAddress))
            }
        }
        guard rc == 0 else {
            throw JBInstallError.spawnDenied("posix_spawn 失败 rc=\(rc)（这个 App 没有越狱执行权限）")
        }
        // 输出重定向到日志：简单起见用 2>&1 到文件由 shell 自己做
        waitpid(pid, nil, 0)

        let out = (try? String(contentsOfFile: logPath, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(atPath: logPath)
        let ok = out.contains("STEP done")
        return (ok, out)
    }

    static func spellingEnsureEntitlements(at dir: String) {
        // platform-application + task_for_pid 权限，交给 ldid 打
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>platform-application</key><true/>
        <key>com.apple.private.security.no-sandbox</key><true/>
        <key>com.apple.private.security.container-required</key><false/>
        </dict></plist>
        """
        let p = dir + "/ents.plist"
        try? plist.write(toFile: p, atomically: true, encoding: .utf8)
    }
}
