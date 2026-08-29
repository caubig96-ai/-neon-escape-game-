import SwiftUI
import Foundation
import Darwin

struct ContentView: View {
    @AppStorage("pcIP") private var pcIP = "192.168.2.139"
    @AppStorage("broadcastIP") private var broadcastIP = "192.168.2.255"
    @AppStorage("internetMode") private var internetMode = false
    @AppStorage("remoteWakeHost") private var remoteWakeHost = ""
    @AppStorage("remoteWakePort") private var remoteWakePort = "40009"
    @AppStorage("remoteControlURL") private var remoteControlURL = ""
    @AppStorage("controlToken") private var controlToken = "CBR-2026-7f2d9c4a-9e31-4b6d"

    @State private var online = false
    @State private var message = "Sẵn sàng"
    @State private var showSettings = false

    private let mac = "34:5A:60:2F:6F:2B"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 52, weight: .semibold))
                        Text("PC CAU-BIG")
                            .font(.title2.bold())
                        HStack(spacing: 8) {
                            Circle().fill(online ? Color.green : Color.gray).frame(width: 10, height: 10)
                            Text(online ? "ĐANG BẬT" : "CHƯA KẾT NỐI")
                                .font(.subheadline.bold())
                        }
                    }
                    .padding(.top, 20)

                    Button {
                        wakePC()
                    } label: {
                        Label("BẬT MÁY", systemImage: "power")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    actionButton("TẮT MÁY", icon: "power.circle", action: "shutdown", role: .destructive)
                    actionButton("KHỞI ĐỘNG LẠI", icon: "arrow.clockwise", action: "restart")
                    actionButton("NGỦ", icon: "moon.zzz", action: "sleep")
                    actionButton("KHÓA MÁY", icon: "lock", action: "lock")

                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    Button("Kiểm tra trạng thái") { checkStatus() }
                        .buttonStyle(.borderless)
                }
                .padding(22)
            }
            .navigationTitle("CAU-BIG Remote")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form {
                        Section("Mạng trong nhà") {
                            TextField("IP PC", text: $pcIP)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                            TextField("Broadcast IP", text: $broadcastIP)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                            LabeledContent("MAC", value: mac)
                            LabeledContent("Port Companion", value: "8765")
                        }

                        Section("Điều khiển từ Internet") {
                            Toggle("Bật chế độ 3G/4G/5G", isOn: $internetMode)
                            TextField("IP công khai hoặc DDNS router", text: $remoteWakeHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            TextField("Port Wake ngoài nhà", text: $remoteWakePort)
                                .keyboardType(.numberPad)
                            TextField("URL điều khiển Tailscale", text: $remoteControlURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            SecureField("Mã bảo mật Companion", text: $controlToken)
                                .textInputAutocapitalization(.never)
                        }

                        Section("Cách hoạt động") {
                            Text("Ở nhà: app gửi Wake-on-LAN trực tiếp. Ở ngoài: app gửi Magic Packet tới router qua IP công khai/DDNS. Router phải chuyển tiếp UDP tới mạng LAN. Các lệnh Tắt/Restart/Ngủ/Khóa nên đi qua Tailscale, không mở cổng 8765 trực tiếp ra Internet.")
                                .font(.footnote)
                        }
                    }
                    .navigationTitle("Cài đặt")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Xong") { showSettings = false }
                        }
                    }
                }
            }
            .task { checkStatus() }
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, icon: String, action: String, role: ButtonRole? = nil) -> some View {
        Button(role: role) {
            sendAction(action)
        } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private func wakePC() {
        let localOK = sendMagicPacket(mac: mac, host: broadcastIP, port: 9, allowBroadcast: true)
        var remoteOK = false

        if internetMode {
            let host = remoteWakeHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if !host.isEmpty {
                let port = UInt16(remoteWakePort) ?? 40009
                remoteOK = sendMagicPacket(mac: mac, host: host, port: port, allowBroadcast: false)
            }
        }

        if localOK && remoteOK {
            message = "Đã gửi lệnh bật máy qua Wi-Fi nhà và Internet."
        } else if remoteOK {
            message = "Đã gửi lệnh bật máy qua Internet. Chờ khoảng 5–20 giây."
        } else if localOK {
            message = internetMode ? "Đã gửi Wake-on-LAN trong nhà. Chưa gửi được qua Internet; kiểm tra DDNS/IP và port router." : "Đã gửi lệnh bật máy. Chờ khoảng 5–20 giây."
        } else {
            message = "Không gửi được lệnh bật máy. Kiểm tra cấu hình mạng."
        }

        if localOK || remoteOK {
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { checkStatus() }
        }
    }

    private func candidateBaseURLs() -> [(URL, String)] {
        var result: [(URL, String)] = []
        if let local = URL(string: "http://\(pcIP):8765") {
            result.append((local, "mạng nhà"))
        }

        if internetMode {
            var remote = remoteControlURL.trimmingCharacters(in: .whitespacesAndNewlines)
            while remote.hasSuffix("/") { remote.removeLast() }
            if !remote.isEmpty, let url = URL(string: remote) {
                result.append((url, "Internet/Tailscale"))
            }
        }
        return result
    }

    private func sendAction(_ action: String) {
        let bases = candidateBaseURLs()
        guard !bases.isEmpty else {
            message = "Chưa có địa chỉ điều khiển PC."
            return
        }
        tryAction(action, bases: bases, index: 0)
    }

    private func tryAction(_ action: String, bases: [(URL, String)], index: Int) {
        guard index < bases.count else {
            DispatchQueue.main.async {
                message = "Không kết nối được PC. Kiểm tra Companion/Tailscale."
                online = false
            }
            return
        }

        let (base, source) = bases[index]
        let url = base.appendingPathComponent("action")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "token": controlToken])

        URLSession.shared.dataTask(with: req) { _, response, error in
            if error == nil, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                DispatchQueue.main.async {
                    message = "Đã gửi lệnh \(label(action)) qua \(source)."
                    if action == "shutdown" || action == "restart" || action == "sleep" { online = false }
                }
            } else {
                tryAction(action, bases: bases, index: index + 1)
            }
        }.resume()
    }

    private func checkStatus() {
        let bases = candidateBaseURLs()
        guard !bases.isEmpty else {
            online = false
            message = "Chưa có địa chỉ điều khiển PC."
            return
        }
        tryStatus(bases: bases, index: 0)
    }

    private func tryStatus(bases: [(URL, String)], index: Int) {
        guard index < bases.count else {
            DispatchQueue.main.async {
                online = false
                message = "PC đang tắt hoặc chưa kết nối được Companion."
            }
            return
        }

        let (base, source) = bases[index]
        let url = base.appendingPathComponent("status")
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5

        URLSession.shared.dataTask(with: req) { _, response, error in
            if error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async {
                    online = true
                    message = "PC đang trực tuyến qua \(source)."
                }
            } else {
                tryStatus(bases: bases, index: index + 1)
            }
        }.resume()
    }

    private func label(_ action: String) -> String {
        switch action {
        case "shutdown": return "tắt máy"
        case "restart": return "khởi động lại"
        case "sleep": return "ngủ"
        case "lock": return "khóa máy"
        default: return action
        }
    }
}

private func sendMagicPacket(mac: String, host: String, port: UInt16, allowBroadcast: Bool) -> Bool {
    let clean = mac.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
    guard clean.count == 12 else { return false }

    var macBytes = [UInt8]()
    for i in stride(from: 0, to: 12, by: 2) {
        let start = clean.index(clean.startIndex, offsetBy: i)
        let end = clean.index(start, offsetBy: 2)
        guard let b = UInt8(clean[start..<end], radix: 16) else { return false }
        macBytes.append(b)
    }

    var packet = [UInt8](repeating: 0xFF, count: 6)
    for _ in 0..<16 { packet.append(contentsOf: macBytes) }

    let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard sock >= 0 else { return false }
    defer { close(sock) }

    if allowBroadcast {
        var yes: Int32 = 1
        if setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) != 0 { return false }
    }

    guard let ip = resolveIPv4(host) else { return false }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = ip

    let sent = packet.withUnsafeBytes { buf -> Int in
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    return sent == packet.count
}

private func resolveIPv4(_ rawHost: String) -> in_addr? {
    var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    if host.hasPrefix("udp://") { host.removeFirst(6) }
    if host.hasSuffix("/") { host.removeLast() }
    guard !host.isEmpty else { return nil }

    var address = in_addr()
    let numeric = host.withCString { inet_pton(AF_INET, $0, &address) }
    if numeric == 1 { return address }

    guard let entry = host.withCString({ gethostbyname($0) }) else { return nil }
    guard entry.pointee.h_addrtype == AF_INET,
          entry.pointee.h_length == Int32(MemoryLayout<in_addr>.size),
          let list = entry.pointee.h_addr_list,
          let first = list[0] else { return nil }

    memcpy(&address, first, MemoryLayout<in_addr>.size)
    return address
}
