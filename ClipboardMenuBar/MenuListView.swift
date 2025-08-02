import SwiftUI
import CryptoKit
import Foundation

struct Record: Identifiable, Equatable, Codable {
    let id = UUID()
    let type: RecordType
    
    enum CodingKeys: CodingKey {
        case id, type
    }
}

enum RecordType: Equatable, Codable {
    case text(String)
    case password(String, alias: String) // password value and alias
    case image(Data, alias: String) // image data and alias (changed from NSImage to Data for JSON)
    case link(String, alias: String) // link URL and alias
}

struct MenuListView: View {
    let closePopover: () -> Void
    
    // Records loaded from encrypted file
    @State private var records: [Record] = []
    @State private var hoveredRecord: Record?
    @State private var newTextInput: String = ""
    @State private var isPasswordToggle: Bool = false
    @State private var passwordAlias: String = ""
    @State private var isImageToggle: Bool = false
    @State private var imageAlias: String = ""
    @State private var isLinkToggle: Bool = false
    @State private var linkAlias: String = ""
    @State private var isScrolling: Bool = false
    @State private var scrollTimer: Timer?
    @State private var showImageConversionAlert: Bool = false
    @State private var searchText: String = ""
    
    // Encryption components
    private let encryptionKey: SymmetricKey
    private let fileManager = FileManager.default
    private var documentsURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ClipboardManager", isDirectory: true)
    }
    private var dataFileURL: URL {
        documentsURL.appendingPathComponent("clipboard_data.encrypted")
    }
    
    init(closePopover: @escaping () -> Void) {
        self.closePopover = closePopover
        
        // Generate or retrieve encryption key
        self.encryptionKey = Self.getOrCreateEncryptionKey()
    }

    // Computed property to filter records based on search text
    private var filteredRecords: [Record] {
        if searchText.isEmpty {
            return records
        } else {
            return records.filter { record in
                switch record.type {
                case .text(let text):
                    return text.localizedCaseInsensitiveContains(searchText)
                case .password(let password, let alias):
                    return alias.localizedCaseInsensitiveContains(searchText) || 
                           password.localizedCaseInsensitiveContains(searchText)
                case .image(_, let alias):
                    return alias.localizedCaseInsensitiveContains(searchText)
                case .link(let url, let alias):
                    return alias.localizedCaseInsensitiveContains(searchText) ||
                           url.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Search bar at the top
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search records...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            
            // Scrollable records section
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Show "No results" message if search returns no results
                    if !searchText.isEmpty && filteredRecords.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No results found")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Try adjusting your search terms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 40)
                            Spacer()
                        }
                    } else {
                        // Text Records Section
                        let textRecords = filteredRecords.filter { 
                            if case .text(_) = $0.type { return true }
                            return false
                        }
                        if !textRecords.isEmpty {
                            sectionHeader("Text")
                            ForEach(textRecords) { record in
                                recordView(record)
                            }
                        }
                        
                        // Password Records Section
                        let passwordRecords = filteredRecords.filter { 
                            if case .password(_, _) = $0.type { return true }
                            return false
                        }
                        if !passwordRecords.isEmpty {
                            sectionHeader("Passwords")
                            ForEach(passwordRecords) { record in
                                recordView(record)
                            }
                        }
                        
                        // Image Records Section
                        let imageRecords = filteredRecords.filter { 
                            if case .image(_, _) = $0.type { return true }
                            return false
                        }
                        if !imageRecords.isEmpty {
                            sectionHeader("Images")
                            ForEach(imageRecords) { record in
                                recordView(record)
                            }
                        }
                        
                        // Link Records Section
                        let linkRecords = filteredRecords.filter { 
                            if case .link(_, _) = $0.type { return true }
                            return false
                        }
                        if !linkRecords.isEmpty {
                            sectionHeader("Links")
                            ForEach(linkRecords) { record in
                                recordView(record)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .background(
                    // Invisible overlay to detect scroll events
                    GeometryReader { geometry in
                        Color.clear
                            .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didLiveScrollNotification)) { _ in
                                handleScrollStart()
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSScrollView.didEndLiveScrollNotification)) { _ in
                                handleScrollEnd()
                            }
                    }
                )
            }
            .frame(maxHeight: NSScreen.main?.frame.height != nil ? (NSScreen.main!.frame.height * 0.75) : 400)
            .onAppear {
                loadRecords()
            }

            // Divider
            Divider()
                .padding(.vertical, 8)
            
            // Add new text input section
            VStack(spacing: 8) {
                // Password toggle
                HStack {
                    Toggle("Mark as Password", isOn: $isPasswordToggle)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .onChange(of: isPasswordToggle) { newValue in
                            if newValue {
                                isImageToggle = false // Disable image toggle when password is selected
                                isLinkToggle = false // Disable link toggle when password is selected
                            }
                        }
                    Spacer()
                }
                
                // Image toggle
                HStack {
                    Toggle("Add Image from Clipboard", isOn: $isImageToggle)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .onChange(of: isImageToggle) { newValue in
                            if newValue {
                                isPasswordToggle = false // Disable password toggle when image is selected
                                isLinkToggle = false // Disable link toggle when image is selected
                            }
                        }
                    Spacer()
                }
                
                // Link toggle
                HStack {
                    Toggle("Add Link", isOn: $isLinkToggle)
                        .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                        .onChange(of: isLinkToggle) { newValue in
                            if newValue {
                                isPasswordToggle = false // Disable password toggle when link is selected
                                isImageToggle = false // Disable image toggle when link is selected
                            }
                        }
                    Spacer()
                }
                
                // Content based on selected mode
                if isImageToggle {
                    // Image mode
                    VStack(spacing: 8) {
                        TextField("Enter alias for image...", text: $imageAlias)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addImageFromClipboard()
                            }
                        
                        HStack {
                            Button("Paste Image from Clipboard") {
                                addImageFromClipboard()
                            }
                            .disabled(imageAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            
                            Spacer()
                        }
                    }
                } else if isLinkToggle {
                    // Link mode
                    VStack(spacing: 8) {
                        TextField("Enter alias for link...", text: $linkAlias)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addNewRecord()
                            }
                        
                        HStack {
                            TextField("Enter or paste URL...", text: $newTextInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    addNewRecord()
                                }
                            
                            Button("Add") {
                                addNewRecord()
                            }
                            .disabled(newTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                                      linkAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } else {
                    // Text/Password mode
                    HStack {
                        TextField(isPasswordToggle ? "Enter password..." : "Paste or type text to add...", text: $newTextInput)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addNewRecord()
                            }
                        
                        Button("Add") {
                            addNewRecord()
                        }
                        .disabled(newTextInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                                  (isPasswordToggle && passwordAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    }
                    
                    // Password alias field (only shown when password toggle is on)
                    if isPasswordToggle {
                        TextField("Enter alias for password...", text: $passwordAlias)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onSubmit {
                                addNewRecord()
                            }
                    }
                }
            }
            
            // Quit button at the bottom
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                Spacer()
                Button("Quit Clipboard Manager") {
                    NSApplication.shared.terminate(nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
                .foregroundColor(.red)
                .buttonStyle(PlainButtonStyle())
                .help("Exit the clipboard manager")
                Spacer()
            }
            .padding(.bottom, 4)
        }
        .padding()
        .frame(width: 400, height: 500)
        .alert("Image Conversion Failed", isPresented: $showImageConversionAlert) {
            Button("OK") { }
        } message: {
            Text("The image could not be converted to TIFF format. Please try a different image.")
        }
    }

    func copyToClipboard(_ record: Record) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch record.type {
        case .text(let text):
            pasteboard.setString(text, forType: .string)
        case .password(let str, _):
            pasteboard.setString(str, forType: .string)
        case .image(let image, _):
            let nsImage = NSImage(data: image)
            pasteboard.setData(nsImage?.tiffRepresentation, forType: .tiff)
        case .link(let url, _):
            // Copy link URL to clipboard
            pasteboard.setString(url, forType: .string)
        }
        
        // Clear search when copying a record for better UX
        searchText = ""
        
        // Close the popover after copying
        closePopover()
    }
    
    private func openLinkInBrowser(_ url: String) {
        if let nsUrl = URL(string: url) {
            NSWorkspace.shared.open(nsUrl)
        }
        
        // Clear search and close popover for better UX
        searchText = ""
        closePopover()
    }
    
    private func addNewRecord() {
        let trimmedText = newTextInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only add if there's actual text
        guard !trimmedText.isEmpty else { return }
        
        // For passwords, also check that alias is provided
        if isPasswordToggle {
            let trimmedAlias = passwordAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAlias.isEmpty else { return }
        }
        
        // For links, also check that alias is provided
        if isLinkToggle {
            let trimmedAlias = linkAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedAlias.isEmpty else { return }
        }
        
        // Create new record based on type
        let newRecord: Record
        if isPasswordToggle {
            let trimmedAlias = passwordAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            newRecord = Record(type: .password(trimmedText, alias: trimmedAlias))
        } else if isLinkToggle {
            let trimmedAlias = linkAlias.trimmingCharacters(in: .whitespacesAndNewlines)
            newRecord = Record(type: .link(trimmedText, alias: trimmedAlias))
        } else {
            newRecord = Record(type: .text(trimmedText))
        }
        
        // Add to the beginning of the list
        records.insert(newRecord, at: 0)

        // Keep only last 100 items to prevent unlimited growth
        if records.count > 100 {
            records = Array(records.prefix(100))
        }
        
        // Save to encrypted file
        saveRecords()
        
        // Clear the input fields and reset toggles
        newTextInput = ""
        passwordAlias = ""
        linkAlias = ""
        isPasswordToggle = false
        isLinkToggle = false
    }
    
    private func addImageFromClipboard() {
        let trimmedAlias = imageAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check that alias is provided
        guard !trimmedAlias.isEmpty else { return }
        
        // Try to get image from clipboard
        let pasteboard = NSPasteboard.general
        guard let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage else {
            // Could add an alert here to inform user no image was found
            return
        }
        
        // Create new image record
        guard let imageData = image.tiffRepresentation else {
            // Show alert to inform user image conversion failed
            showImageConversionAlert = true
            return
        }
        let newRecord = Record(type: .image(imageData, alias: trimmedAlias))
        
        // Add to the beginning of the list
        records.insert(newRecord, at: 0)
        
        // Keep only last 10 items to prevent unlimited growth
        if records.count > 10 {
            records = Array(records.prefix(10))
        }
        
        // Save to encrypted file
        saveRecords()
        
        // Clear the input fields and reset toggle
        imageAlias = ""
        isImageToggle = false
    }
    
    private func deleteRecord(_ record: Record) {
        records.removeAll { $0.id == record.id }
        // Save to encrypted file after deletion
        saveRecords()
    }
    
    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    @ViewBuilder
    private func recordView(_ record: Record) -> some View {
        Button(action: {
            copyToClipboard(record)
        }) {
            ZStack {
                // Background highlight on hover
                if hoveredRecord == record {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.2))
                }
                HStack {
                    switch record.type {
                    case .text(let str):
                        Text(str)
                            .foregroundColor(.primary)
                    case .password(let str, let alias):
                        Text("Password: \(alias)") // Show "Password: <Alias>"
                            .foregroundColor(.secondary)
                    case .image(let img, let alias):
                        HStack {
                            if let nsImage = NSImage(data: img) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 40)
                            }
                            VStack(alignment: .leading) {
                                Text("Image: \(alias)")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                    case .link(let url, let alias):
                        HStack {
                            Image(systemName: "link")
                                .foregroundColor(.blue)
                                .frame(width: 16, height: 16)
                            VStack(alignment: .leading) {
                                Text("Link: \(alias)")
                                    .foregroundColor(.blue)
                                Text(url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                        }
                    }
                    
                    Spacer()
                    
                    // Action buttons (only show on hover and not while scrolling)
                    if hoveredRecord == record && !isScrolling {
                        HStack(spacing: 4) {
                            // Open in browser button (only for links)
                            if case .link(let url, _) = record.type {
                                Button(action: {
                                    openLinkInBrowser(url)
                                }) {
                                    Image(systemName: "arrow.up.right")
                                        .foregroundColor(.blue)
                                        .frame(width: 16, height: 16)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Open link in browser")
                            }
                            
                            // Delete button
                            Button(action: {
                                deleteRecord(record)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Delete this item")
                        }
                    }
                }
                .padding(8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            // Only update hover state if not currently scrolling
            if !isScrolling {
                hoveredRecord = hovering ? record : nil
            }
        }
    }
    
    private func handleScrollStart() {
        isScrolling = true
        hoveredRecord = nil // Clear any current hover state
        
        // Cancel any existing timer
        scrollTimer?.invalidate()
    }
    
    private func handleScrollEnd() {
        // Start a timer to delay the end of scrolling state
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            isScrolling = false
        }
    }
    
    // MARK: - Encryption and File Management
    
    private static func getOrCreateEncryptionKey() -> SymmetricKey {
        let keychain = Keychain()
        let keyIdentifier = "clipboard-manager-encryption-key"
        
        if let existingKeyData = keychain.getData(keyIdentifier) {
            return SymmetricKey(data: existingKeyData)
        } else {
            let newKey = SymmetricKey(size: .bits256)
            let keyData = newKey.withUnsafeBytes { Data($0) }
            keychain.set(keyData, forKey: keyIdentifier)
            return newKey
        }
    }
    
    private func loadRecords() {
        // Create app support directory if it doesn't exist
        try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        
        guard fileManager.fileExists(atPath: dataFileURL.path) else {
            // File doesn't exist, start with empty records
            records = []
            return
        }
        
        do {
            let encryptedData = try Data(contentsOf: dataFileURL)
            let decryptedData = try ChaChaPoly.open(try ChaChaPoly.SealedBox(combined: encryptedData), using: encryptionKey)
            let loadedRecords = try JSONDecoder().decode([Record].self, from: decryptedData)
            records = loadedRecords
        } catch {
            print("Failed to load records: \(error)")
            // On error, start with empty records
            records = []
        }
    }
    
    private func saveRecords() {
        // Create app support directory if it doesn't exist
        try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        
        do {
            let jsonData = try JSONEncoder().encode(records)
            let sealedBox = try ChaChaPoly.seal(jsonData, using: encryptionKey)
            try sealedBox.combined.write(to: dataFileURL)
        } catch {
            print("Failed to save records: \(error)")
        }
    }
}

// MARK: - Simple Keychain Helper
private class Keychain {
    func set(_ data: Data, forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }
    
    func getData(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        return nil
    }
}

