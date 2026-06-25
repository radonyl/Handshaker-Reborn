import Foundation

enum L {
    private static var isChinese: Bool {
        Locale.preferredLanguages.first?
            .lowercased()
            .hasPrefix("zh") == true
    }

    static func text(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }

    static let appTitle = text("ADB 导入", "ADB Import")
    static let albums = text("相册", "Albums")
    static let media = text("媒体", "Media")
    static let refresh = text("刷新", "Refresh")
    static let refreshDevice = text("刷新设备", "Refresh Device")
    static let refreshDeviceHelp = text("刷新设备连接", "Refresh device connection")
    static let transfer = text("传输", "Transfer")
    static let transferSelectedHelp = text("传输选中的媒体", "Transfer selected media")
    static let transferRunning = text("传输中", "Transferring")
    static let alertTitle = text("提示", "Notice")
    static let ok = text("好", "OK")
    static let selectAllCurrentAlbum = text("全选当前相册", "Select All in Current Album")
    static let currentAlbumOnly = text("当前版本仅传输当前相册内选择的文件", "This version only transfers selected files from the current album.")
    static let chooseAlbum = text("选择相册", "Choose an Album")
    static let chooseAlbumFromSidebar = text("从左侧选择一个手机相册目录", "Choose a phone album from the sidebar")
    static let selectAllLoaded = text("全选已加载", "Select Loaded")
    static let clearSelection = text("取消选择", "Clear Selection")
    static let connectionFallback = text("连接 Android 手机并在手机上允许 USB 调试后，点击工具栏刷新。", "Connect your Android phone, allow USB debugging on the phone, then click Refresh.")
    static let scanningPhoneAlbums = text("正在扫描手机相册", "Scanning Phone Albums")
    static let scanningPhoneAlbumsDetail = text("正在查找手机里实际包含图片或视频的目录。", "Finding folders on the phone that contain photos or videos.")
    static let chooseAlbumDescription = text("从左侧选择一个相册目录开始浏览。", "Choose an album from the sidebar to start browsing.")
    static let scanningAlbum = text("正在扫描相册", "Scanning Album")
    static let scanningAlbumDetail = text("正在从手机读取图片和视频文件。", "Reading photos and videos from the phone.")
    static let scanFailed = text("扫描失败", "Scan Failed")
    static let retry = text("重试", "Retry")
    static let noMedia = text("没有找到媒体", "No Media Found")
    static let noMediaDescription = text("此相册暂时没有可导入的图片或视频。", "This album does not contain importable photos or videos.")
    static let unknownSize = text("未知大小", "Unknown size")
    static let image = text("图片", "Image")
    static let video = text("视频", "Video")
    static let checkingDevice = text("正在检测设备", "Checking Device")
    static let noAuthorizedDevice = text("没有检测到已授权的 Android 设备。请检查 USB 连接和手机上的调试授权。", "No authorized Android device was detected. Check the USB connection and USB debugging authorization on the phone.")
    static let adbMissingError = text("未安装 Android platform-tools。请先安装 adb。", "Android platform-tools is not installed. Install adb first.")
    static let adbMissingTitle = text("未安装 Android platform-tools", "Android platform-tools Not Installed")
    static let adbMissingDetail = text("这台 Mac 没有找到 adb。可用 Homebrew 安装：brew install android-platform-tools。", "This Mac could not find adb. Install it with Homebrew: brew install android-platform-tools.")
    static let adbCannotRun = text("无法运行 adb", "Could Not Run adb")
    static let authorizationDetail = text("请解锁手机，并在 USB 调试授权弹窗中选择允许。", "Unlock the phone and tap Allow in the USB debugging authorization prompt.")
    static let configuredDeviceMissing = text("指定设备未连接", "Configured Device Not Connected")
    static let configuredDeviceMissingDetail = text("配置文件固定了 device_id，但当前 adb 没有看到这台设备。", "The config file pins a device_id, but adb cannot see that device.")
    static let phoneNotConnected = text("未连接手机", "Phone Not Connected")
    static let phoneNotConnectedDetail = text("请连接 USB 数据线，并确认手机 USB 连接模式和 USB 调试已开启。", "Connect the USB cable and confirm the phone USB mode and USB debugging are enabled.")
    static let chooseDestinationTitle = text("选择保存位置", "Choose Save Location")
    static let chooseDestinationMessage = text("将选中的媒体文件保存到这个文件夹。", "Save the selected media files to this folder.")
    static let choose = text("选择", "Choose")
    static let showInFinder = text("在 Finder 中显示", "Show in Finder")
    static let selectFilesToTransfer = text("选择文件后开始传输", "Select files to start transferring")
    static let choosingDestination = text("正在选择保存位置", "Choosing save location")
    static let preparingTransfer = text("准备传输", "Preparing transfer")

    static func connected(_ id: String) -> String {
        text("已连接：\(id)", "Connected: \(id)")
    }

    static func waitingAuthorization(_ id: String? = nil) -> String {
        if let id {
            return text("等待手机授权：\(id)", "Waiting for Phone Authorization: \(id)")
        }
        return text("等待手机授权", "Waiting for Phone Authorization")
    }

    static func transferFailed(_ filename: String) -> String {
        text("传输失败：\(filename)", "Transfer failed: \(filename)")
    }

    static func thumbnailCacheFailed(_ filename: String) -> String {
        text("缩略图缓存失败：\(filename)", "Thumbnail cache failed: \(filename)")
    }

    static func thumbnailGenerationFailed(_ filename: String) -> String {
        text("无法生成缩略图：\(filename)", "Could not generate thumbnail: \(filename)")
    }

    static func unableToScanAlbums(_ message: String) -> String {
        text("无法扫描相册：\(message)", "Could not scan albums: \(message)")
    }

    static func selectedCount(_ count: Int) -> String {
        text("\(count) 个已选择", "\(count) selected")
    }

    static func completedSummary(completed: Int, failed: Int) -> String {
        text("完成 \(completed)，失败 \(failed)", "Completed \(completed), failed \(failed)")
    }

    static func loadedCount(_ loaded: Int, total: Int) -> String {
        text("已加载 \(loaded) / \(total)", "Loaded \(loaded) / \(total)")
    }

    static func loadedMoreAvailable(_ loaded: Int) -> String {
        text("已加载 \(loaded)，继续滚动加载", "Loaded \(loaded). Scroll to load more.")
    }

    static func loadedCount(_ loaded: Int) -> String {
        text("已加载 \(loaded)", "Loaded \(loaded)")
    }
}
