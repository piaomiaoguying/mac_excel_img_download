//
//  ContentView.swift
//  pic_down
//
//  Created by 张三儿 on 2024/10/6.
//

import SwiftUI
import UniformTypeIdentifiers
import CoreXLSX
import Network
import Foundation

// 创建一个下载管理器
class DownloadManager: ObservableObject {
    @Published var progress: Double = 0
    @Published var logs: [String] = []
    @Published var isDownloading = false
    @Published var previewImagePath: String?
    private var totalItems = 0
    private var completedItems = 0
    private let queue = DispatchQueue(label: "com.yourapp.downloadQueue", attributes: .concurrent)
    private var startTime: Date?
    private var downloadTasks: [URLSessionDataTask] = []
    private var isTaskCancelled = false
    private var retryCount: [URL: Int] = [:]
    private let maxRetries = 3
    private var activeDownloads = 0
    
    func startDownload(rows: [CoreXLSX.Row], urlColumnIndex: Int, nameColumnIndex: Int, sharedStrings: SharedStrings?, savePath: String) {
        isDownloading = true
        totalItems = rows.count
        completedItems = 0
        progress = 0
        startTime = Date()
        isTaskCancelled = false
        activeDownloads = 0
        
        addLog("开始下载任务")
        
        queue.async { [weak self] in
            let semaphore = DispatchSemaphore(value: 10) // 限制并发数
            
            for (index, row) in rows.enumerated() {
                if self?.isTaskCancelled == true {
                    break
                }
                
                semaphore.wait()
                
                self?.queue.async {
                    do {
                        try self?.processRow(row: row, urlColumnIndex: urlColumnIndex, nameColumnIndex: nameColumnIndex, rowIndex: index, sharedStrings: sharedStrings, savePath: savePath)
                    } catch {
                        self?.addLog("处理第\(index + 2)行时出错: \(error.localizedDescription)")
                        self?.decrementActiveDownloads()
                    }
                    
                    semaphore.signal()
                }
            }
            
            // 等待所有下载完成
            self?.queue.async {
                while self?.activeDownloads ?? 0 > 0 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                self?.finishDownload()
            }
        }
    }
    
    private func processRow(row: CoreXLSX.Row, urlColumnIndex: Int, nameColumnIndex: Int, rowIndex: Int, sharedStrings: SharedStrings?, savePath: String) {
        let urlCell = row.cells[safe: urlColumnIndex - 1]
        let nameCell = row.cells[safe: nameColumnIndex - 1]
        
        guard let urlValue = getCellValue(urlCell, sharedStrings: sharedStrings) else {
            addLog("URL单元格为空，跳过第\(rowIndex + 2)行")
            return
        }
        
        guard let rawNameValue = getCellValue(nameCell, sharedStrings: sharedStrings) else {
            addLog("文件名单元格为空，跳过第\(rowIndex + 2)行")
            return
        }
        
        let nameValue = sanitizeFileName(rawNameValue)
        
        addLog("处理第\(rowIndex + 2)行: URL=\(urlValue), 文件名=\(nameValue)")
        
        if isValidURL(urlValue) {
            guard let url = URL(string: urlValue) else {
                addLog("无效的URL: \(urlValue)")
                return
            }
            incrementActiveDownloads()
            downloadImage(url: url, fileName: nameValue, savePath: savePath) { result in
                switch result {
                case .success(let filePath):
                    self.addLog("图片下载成功: \(filePath)")
                case .failure(let error):
                    self.addLog("图片下载失败: \(error.localizedDescription)")
                }
                self.decrementActiveDownloads()
            }
        } else {
            addLog("无效的URL: \(urlValue)")
        }
    }
    
    private func incrementActiveDownloads() {
        DispatchQueue.main.async {
            self.activeDownloads += 1
        }
    }
    
    private func decrementActiveDownloads() {
        DispatchQueue.main.async {
            self.activeDownloads -= 1
            self.completedItems += 1
            self.progress = Double(self.completedItems) / Double(self.totalItems)
        }
    }
    
    private func finishDownload() {
        DispatchQueue.main.async {
            self.isDownloading = false
            if let startTime = self.startTime {
                let duration = Date().timeIntervalSince(startTime)
                self.addLog("下载任务完成，总耗时: \(String(format: "%.2f", duration))秒")
            } else {
                self.addLog("下载任务完成")
            }
            self.startTime = nil
            self.addLog("所有下载任务执行完毕")
        }
    }
    
    private func downloadImage(url: URL, fileName: String, savePath: String, completion: @escaping (Result<String, Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.addLog("下载失败 (\(fileName)): \(error.localizedDescription)")
                if let urlError = error as? URLError, urlError.code == .cancelled {
                    self.addLog("下载被取消 (\(fileName))，尝试重新下载")
                    self.retryDownload(url: url, fileName: fileName, savePath: savePath, completion: completion)
                } else {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data, let response = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "DownloadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data or invalid response"])))
                return
            }
            
            let fileManager = FileManager.default
            var filePath = (savePath as NSString).appendingPathComponent(fileName)
            
            // 确定文件扩展名
            var fileExtension = "jpg" // 默认扩展名
            if let mimeType = response.mimeType {
                switch mimeType {
                case "image/jpeg":
                    fileExtension = "jpg"
                case "image/png":
                    fileExtension = "png"
                case "image/gif":
                    fileExtension = "gif"
                case "image/webp":
                    fileExtension = "webp"
                default:
                    fileExtension = "jpg"
                }
            } 
            
            // 如果文件名已经包含扩展名，就不再添加
            if !fileName.lowercased().hasSuffix(".\(fileExtension)") {
                filePath += ".\(fileExtension)"
            }
            
            let fileURL = URL(fileURLWithPath: filePath)
            
            do {
                try data.write(to: fileURL)
                DispatchQueue.main.async {
                    self.previewImagePath = filePath
                }
                completion(.success(filePath))
            } catch {
                completion(.failure(error))
            }
        }
        
        downloadTasks.append(task)
        task.resume()
    }
    
    private func retryDownload(url: URL, fileName: String, savePath: String, completion: @escaping (Result<String, Error>) -> Void) {
        let currentRetries = retryCount[url] ?? 0
        if currentRetries < maxRetries {
            retryCount[url] = currentRetries + 1
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(currentRetries + 1)) {
                self.downloadImage(url: url, fileName: fileName, savePath: savePath, completion: completion)
            }
        } else {
            addLog("下载失败 (\(fileName)): 已达到最大重试次数")
            completion(.failure(NSError(domain: "DownloadError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Max retries reached"])))
        }
    }
    
    func addLog(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = self.getCurrentTimestamp()
            let logMessage = "\(timestamp) - \(message)"
            self.logs.append(logMessage)
            if self.logs.count > 10000 {
                self.logs.removeFirst(self.logs.count - 10000)
            }
            self.objectWillChange.send()
        }
    }
    
    private func getCurrentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    func cancelDownload() {
        isTaskCancelled = true
        addLog("用户手动取消下载任务")
        // 不再立即取消所有任务，而是标记为取消状态
        
        queue.async { [weak self] in
            self?.isDownloading = false
            self?.addLog("下载任务已取消，正在完成当前进行中的下载")
        }
    }
    
    private func cancelAllDownloadTasks() {
        downloadTasks.forEach { $0.cancel() }
        downloadTasks.removeAll()
        retryCount.removeAll()
    }

    func reset() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 取消所有下载任务
            self?.cancelAllDownloadTasks()
            
            DispatchQueue.main.async {
                // 重置所有状态
                self?.progress = 0
                self?.logs.removeAll()
                self?.isDownloading = false
                self?.previewImagePath = nil
                self?.totalItems = 0
                self?.completedItems = 0
                self?.startTime = nil
                self?.isTaskCancelled = false
                self?.downloadTasks.removeAll()
                
                // 触发 UI 更新
                self?.objectWillChange.send()
            }
        }
    }

    private func getCellValue(_ cell: Cell?, sharedStrings: SharedStrings?) -> String? {
        guard let cell = cell else { return nil }
        
        if let value = cell.value {
            if let index = Int(value),
               let sharedStrings = sharedStrings,
               let string = sharedStrings.items[safe: index]?.text {
                return string
            }
            return value
        } else if let formula = cell.formula {
            return "公式: \(formula.value)"
        } else if let inlineString = cell.inlineString {
            return inlineString.text
        } else if let dateValue = cell.dateValue {
            return "期值: \(dateValue)"
        } else {
            return nil
        }
    }
    
    private func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return fileName.components(separatedBy: invalidCharacters).joined()
    }
    
    private func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return url.scheme != nil && url.host != nil
    }
}

struct ContentView: View {
    @StateObject private var downloadManager = DownloadManager()
    @State private var excelPath: String = "文件路径：请选择Excel文件"
    @State private var imageUrlColumn: String = "4"
    @State private var imageNameColumn: String = "2"
    @State private var savePath: String = "保存路径：请选择保存位置"
    @State private var previewImage: Image?
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var needsReset = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Button(action: selectExcelFile) {
                        HStack {
                            Image(systemName: "doc.fill")
                            Text("选择Excel")
                        }
                        .frame(minWidth: 100, minHeight: 30)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(excelPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 10)
                }
                
                HStack {
                    Group {
                        Text("图片下载地址：第")
                        TextField("", text: $imageUrlColumn)
                            .frame(width: 40)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("列")
                    }
                    .foregroundColor(.blue)
                    
                    Spacer().frame(width: 20)
                    
                    Group {
                        Text("图片文件名：第")
                        TextField("", text: $imageNameColumn)
                            .frame(width: 40)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("列")
                    }
                    .foregroundColor(.green)
                }
                
                HStack {
                    Button(action: selectSaveFolder) {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text("选择保存路径")
                        }
                        .frame(minWidth: 120, minHeight: 30)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(savePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.leading, 10)
                }
                
                HStack(spacing: 15) {
                    Button(action: {
                        startDownload()
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("开始下载")  // 修正这里的文案
                        }
                        .frame(minWidth: 100, minHeight: 30)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(downloadManager.isDownloading || needsReset)
                    
                    Button(action: cancelDownload) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("结束任务")
                        }
                        .frame(minWidth: 100, minHeight: 30)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!downloadManager.isDownloading)
                    
                    Button(action: resetAll) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重置")
                        }
                        .frame(minWidth: 100, minHeight: 30)
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(downloadManager.isDownloading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("运行日志").font(.body)
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(downloadManager.logs.enumerated()), id: \.offset) { index, log in
                                    Text(log)
                                        .font(.system(.caption, design: .monospaced))
                                        .id(index)
                                }
                            }
                        }
                        .frame(height: 180)
                        .border(Color.gray, width: 1)
                        .onChange(of: downloadManager.logs) { _ in
                            withAnimation {
                                proxy.scrollTo(downloadManager.logs.count - 1, anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(width: 365)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("图片预览").font(.body)
                    if let path = downloadManager.previewImagePath, let nsImage = NSImage(contentsOfFile: path) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .border(Color.gray, width: 1)
                    } else {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 180, height: 180)
                            .border(Color.gray, width: 1)
                            .overlay(Text("无预览图片").font(.body))
                    }
                }
                .frame(width: 180)
            }
            
            ProgressView(value: downloadManager.progress)
                .progressViewStyle(LinearProgressViewStyle())
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 15)
        .frame(width: 590, height: 430)
        .alert(isPresented: $showAlert) {
            Alert(title: Text("错误"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
        }
    }
    
    func selectExcelFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.spreadsheet]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                excelPath = url.path
                downloadManager.addLog("已选择Excel文件: \(url.lastPathComponent)")
            }
        } else {
            downloadManager.addLog("取消选择Excel文")
        }
    }
    
    func selectSaveFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                savePath = url.path
                downloadManager.addLog("已选择保存路径: \(url.path)")
            }
        } else {
            downloadManager.addLog("取消选择保存路径")
        }
    }
    
    func resetAll() {
        // 在后台队列执行重置操作
        DispatchQueue.global(qos: .userInitiated).async {
            // 重置 DownloadManager
            self.downloadManager.reset()
            
            DispatchQueue.main.async {
                // 重置所有 UI 相关的状态
                self.excelPath = "文件路径：请选择Excel文件"
                self.imageUrlColumn = "4"
                self.imageNameColumn = "2"
                self.savePath = "保存路径：请选择保存位置"
                self.previewImage = nil
                self.showAlert = false
                self.alertMessage = ""
                self.needsReset = false
                
                // 添加重置完成的日志
                self.downloadManager.addLog("所有设置已重置")
            }
        }
    }
    
    func startDownload() {
        // 前置检查
        if excelPath == "文件路径：请选择Excel文件" {
            showError("请选择Excel文件")
            return
        }
        
        if imageUrlColumn.isEmpty {
            showError("请设置图片下载地址列")
            return
        }
        
        if imageNameColumn.isEmpty {
            showError("请设置图片文件名列")
            return
        }
        
        if savePath == "保存路径：请选择保存位置" {
            showError("请选择保存路径")
            return
        }
        
        downloadManager.addLog("开始下载图片...")
        
        // 解析 Excel 文件
        guard let file = XLSXFile(filepath: excelPath) else {
            showError("无法打开Excel文件")
            return
        }
        
        do {
            let worksheetPaths = try file.parseWorksheetPaths()
            guard let firstWorksheetPath = worksheetPaths.first else {
                showError("Excel文件中没有工作表")
                return
            }
            
            let worksheet = try file.parseWorksheet(at: firstWorksheetPath)
            let sharedStrings = try file.parseSharedStrings()
            
            guard let urlColumnIndex = columnNameToIndex(imageUrlColumn),
                  let nameColumnIndex = columnNameToIndex(imageNameColumn) else {
                showError("无效的列名")
                return
            }
            
            downloadManager.addLog("URL列索引: \(urlColumnIndex), 文件名列索引: \(nameColumnIndex)")
            
            if let rows = worksheet.data?.rows {
                downloadManager.startDownload(rows: Array(rows.dropFirst()), urlColumnIndex: urlColumnIndex, nameColumnIndex: nameColumnIndex, sharedStrings: sharedStrings, savePath: savePath)
            } else {
                showError("工作表中没有数据")
            }
        } catch {
            showError("解析Excel文件时出错: \(error.localizedDescription)")
        }
    }
    
    func cancelDownload() {
        downloadManager.cancelDownload()
    }
    
    func columnNameToIndex(_ name: String) -> Int? {
        let uppercaseName = name.uppercased()
        var result = 0
        
        // 如果输入是纯数字，直接返回该数字（不需要减1
        if let number = Int(name) {
            downloadManager.addLog("列名 '\(name)' 解析为索引: \(number)")
            return number
        }
        
        for char in uppercaseName {
            guard let asciiValue = char.asciiValue, asciiValue >= 65, asciiValue <= 90 else {
                downloadManager.addLog("无效的列名字符: \(char) in \(name)")
                return nil // 非法字符
            }
            result = result * 26 + Int(asciiValue - 64)
            if result > Int.max / 26 {
                downloadManager.addLog("列名索引溢出: \(name)")
                return nil // 溢出
            }
        }
        downloadManager.addLog("列名 '\(name)' 解析为索引: \(result)")
        return result // 不再减1，因为Excel列索从1始
    }
    
    func showError(_ message: String) {
        alertMessage = message
        showAlert = true
        downloadManager.addLog("错误: \(message)")
    }
    
    func updatePreviewImage(filePath: String) async {
        if let image = NSImage(contentsOfFile: filePath) {
            await MainActor.run {
                self.previewImage = Image(nsImage: image)
            }
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// 添加一个新的辅助函数来将列索引转换为列名
func columnIndexToName(_ index: Int) -> String {
    var name = ""
    var index = index
    while index > 0 {
        index -= 1
        name = String(Character(UnicodeScalar(65 + index % 26)!)) + name
        index /= 26
    }
    return name
}

#Preview {
    ContentView()
}
