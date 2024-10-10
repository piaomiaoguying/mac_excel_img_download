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

struct ContentView: View {
    @State private var excelPath: String = "文件路径：请选择Excel文件"
    @State private var imageUrlColumn: String = "4"
    @State private var imageNameColumn: String = "2"
    @State private var savePath: String = "保存路径：请选择保存位置"
    @State private var logMessages: [String] = []
    @State private var previewImage: Image?
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var isDownloading = false
    @State private var isCancelling = false
    @State private var needsReset = false // 新添加的状态变量
    @State private var scrollProxy: ScrollViewProxy?
    @State private var downloadTask: Task<Void, Never>?
    @State private var logText: String = ""  // 新增这行

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
                        Text("图片下载址")
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
                        downloadTask = Task {
                            await startDownload()
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle")
                            Text("开始载")
                        }
                        .frame(minWidth: 100, minHeight: 30)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isDownloading || needsReset)
                    
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
                    .disabled(!isDownloading || isCancelling)
                    
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
                    .disabled(isDownloading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 15) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("运行日志").font(.body)
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(logText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .padding(5)
                                .id("logBottom") // 添加一个 ID 用于滚动
                        }
                        .frame(height: 180)
                        .border(Color.gray, width: 1)
                        .onChange(of: logText) { _ in
                            withAnimation {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .frame(width: 350)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("图片预览").font(.body)
                    if let previewImage = previewImage {
                        previewImage
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
                .frame(width: 180, height: 200)
            }
        }
        .padding(.horizontal, 15) // 将水平内边距从 20 减少到 15
        .padding(.vertical, 15)
        .frame(width: 590, height: 430) // 将宽度从 600 减少到 590
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
                addLog("已选择Excel文件: \(url.lastPathComponent)")
            }
        } else {
            addLog("取消选择Excel文")
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
                addLog("已选择保存路径: \(url.path)")
            }
        } else {
            addLog("取消选择保存路径")
        }
    }
    
    func addLog(_ message: String) {
        let cleanedMessage = message.replacingOccurrences(of: "\\p{Cn}", with: "?", options: .regularExpression)
        DispatchQueue.main.async {
            self.logMessages.append(cleanedMessage)
            if self.logMessages.count > 10000 {
                self.logMessages.removeFirst(self.logMessages.count - 10000)
            }
            self.updateLogText()
        }
    }
    
    func addLogBatch(_ messages: [String]) async {
        let cleanedMessages = messages.map { $0.replacingOccurrences(of: "\\p{Cn}", with: "?", options: .regularExpression) }
        await MainActor.run {
            self.logMessages.append(contentsOf: cleanedMessages)
            if self.logMessages.count > 10000 {
                self.logMessages.removeFirst(self.logMessages.count - 10000)
            }
            self.updateLogText()
        }
    }
    
    private func updateLogText() {
        logText = logMessages.joined(separator: "\n\n")
    }
    
    func resetAll() {
        excelPath = "文件路径：请选择Excel文件"
        imageUrlColumn = "4"
        imageNameColumn = "2"
        savePath = "保存路径：请选择保存位置"
        logMessages = []
        previewImage = nil
        downloadTask?.cancel()
        isDownloading = false
        isCancelling = false
        needsReset = false // 重置时将 needsReset 设置为 false
        addLog("所有设置已重置")
    }
    
    func startDownload() async {
        isDownloading = true
        defer { 
            isDownloading = false
            needsReset = true // 任务结束后设置需要重置
        }

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
        
        addLog("开始下载图片...")
        
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
            
            addLog("URL列索引: \(urlColumnIndex), 件名列索引: \(nameColumnIndex)")
            
            // 在 startDownload 函数内，替换处理每一行的循环部分
            if let rows = worksheet.data?.rows {
                for (rowIndex, row) in rows.dropFirst().enumerated() {
                    if Task.isCancelled {
                        addLog("下载任务已取消")
                        return
                    }
                    
                    let urlCell = row.cells[safe: urlColumnIndex - 1]
                    let nameCell = row.cells[safe: nameColumnIndex - 1]
                    
                    guard let urlValue = getCellValue(urlCell, sharedStrings: sharedStrings) else {
                        addLog("URL单元格为空跳过第\(rowIndex + 2)行")
                        continue
                    }
                    
                    guard let rawNameValue = getCellValue(nameCell, sharedStrings: sharedStrings) else {
                        addLog("文件名单元格为空，跳过第\(rowIndex + 2)行")
                        continue
                    }
                    
                    let nameValue = sanitizeFileName(rawNameValue)
                    
                    addLog("处理第\(rowIndex + 2)行: URL=\(urlValue), 文件名=\(nameValue)")
                    
                    if isValidURL(urlValue) {
                        do {
                            guard let url = URL(string: urlValue) else {
                                addLog("无效的URL: \(urlValue)")
                                continue
                            }
                            let filePath = try await downloadImage(url: url, fileName: nameValue)
                            addLog("图片下载成功: \(filePath)")
                            await updatePreviewImage(filePath: filePath)
                        } catch {
                            addLog("图片下载失败: \(error.localizedDescription)")
                        }
                    } else {
                        addLog("效的URL: \(urlValue)")
                    }
                    
                    // 在每次循环中检查否取消
                    try Task.checkCancellation()
                }
            } else {
                addLog("工作表中没有数据")
            }
        } catch is CancellationError {
            addLog("下载任务已取消")
        } catch {
            showError("解析Excel文件时出错: \(error.localizedDescription)")
        }
        
        addLog("下载任务完成")
    }

    func downloadImage(url: URL, fileName: String) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        let fileManager = FileManager.default
        var filePath = (self.savePath as NSString).appendingPathComponent(fileName)
        
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
        
        // 文件已经包扩展名就添
        if !fileName.lowercased().hasSuffix(".\(fileExtension)") {
            filePath += ".\(fileExtension)"
        }
        
        let fileURL = URL(fileURLWithPath: filePath)
        
        try data.write(to: fileURL)
        return filePath
    }
    
    func columnNameToIndex(_ name: String) -> Int? {
        let uppercaseName = name.uppercased()
        var result = 0
        
        // 如果输入是纯数字，直接返回该数字（不需要减1
        if let number = Int(name) {
            addLog("列名 '\(name)' 解析为索引: \(number)")
            return number
        }
        
        for char in uppercaseName {
            guard let asciiValue = char.asciiValue, asciiValue >= 65, asciiValue <= 90 else {
                addLog("无效的列名字符: \(char) in \(name)")
                return nil // 非法字符
            }
            result = result * 26 + Int(asciiValue - 64)
            if result > Int.max / 26 {
                addLog("列名索引溢出: \(name)")
                return nil // 溢出
            }
        }
        addLog("列名 '\(name)' 解析为索引: \(result)")
        return result // 不再减1，因为Excel列索从1始
    }
    
    func isValidURL(_ urlString: String) -> Bool {
        if let url = URL(string: urlString) {
            return url.scheme != nil && url.host != nil
        }
        return false
    }
    
    func showError(_ message: String) {
        alertMessage = message
        showAlert = true
        addLog("错误: \(message)")
    }
    
    func getCellValue(_ cell: Cell?, sharedStrings: SharedStrings?) -> String? {
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
            return "日期值: \(dateValue)"
        } else {
            return nil
        }
    }
    
    func updatePreviewImage(filePath: String) async {
        if let image = NSImage(contentsOfFile: filePath) {
            await MainActor.run {
                self.previewImage = Image(nsImage: image)
            }
        }
    }

    func cancelDownload() {
        isCancelling = true
        downloadTask?.cancel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.isCancelling = false
            self.isDownloading = false
            self.needsReset = true // 取消后也设置需要重置
        }
        addLog("正在取消下载任务...")
    }

    func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return fileName.components(separatedBy: invalidCharacters).joined()
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