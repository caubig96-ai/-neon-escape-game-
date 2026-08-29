import SwiftUI
import Foundation
import Darwin

struct ContentView: View {
    @AppStorage("pcIP") private var pcIP = "192.168.2.139"
    @AppStorage("broadcastIP") private var broadcastIP = "192.168.2.255"
    @AppStorage("pin") private var pin = ""
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form {
                        Section("Mạng PC") {
                            TextField("IP PC", text: $pcIP)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                            TextField("Broadcast IP", text: $broadcastIP)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                            LabeledContent("MAC", value: mac)
                            LabeledContent("Port điều khiển", value: "8765")
                            SecureField("PIN đã đặt trên PC", text: $pin)
                                .keyboardType(.numberPad)
                        }
                        Section {
                            Text("Bật máy dùng Wake-on-LAN. Các lệnh Tắt/Restart/Ngủ/Khóa cần CAU-BIG Companion chạy trên Windows.")
                        }
                    }
                    .navigationTitle("Cài đặt")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { showSettings = false } } }
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
        let ok = sendMagicPacket(mac: mac, broadcast: broadcastIP, port: 9)
        message = ok ? "Đã gửi lệnh bật máy. Chờ khoảng 5–20 giây." : "Không gửi được Wake-on-LAN. Kiểm tra Wi-Fi và Broadcast IP."
        if ok {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { checkStatus() }
        }
    }

    private func sendAction(_ action: String) {
        guard let url = URL(string: "http://\(pcIP):8765/action") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard !pin.isEmpty else {
            message = "Hãy mở Cài đặt và nhập PIN đã đặt khi cài Companion trên PC."
            return
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["action": action, "pin": pin])
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    message = "Không kết nối được PC: \(error.localizedDescription)"
                    online = false
                } else if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    message = "Đã gửi lệnh \(label(action))."
                    if action == "shutdown" || action == "restart" || action == "sleep" { online = false }
                } else {
                    message = "PC không nhận lệnh. Kiểm tra Companion."
                }
            }
        }.resume()
    }

    private func checkStatus() {
        guard let url = URL(string: "http://\(pcIP):8765/status") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        URLSession.shared.dataTask(with: req) { _, response, error in
            DispatchQueue.main.async {
                online = (error == nil && (response as? HTTPURLResponse)?.statusCode == 200)
                message = online ? "PC đang trực tuyến." : "PC đang tắt hoặc Companion chưa chạy."
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

private func sendMagicPacket(mac: String, broadcast: String, port: UInt16) -> Bool {
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
    var yes: Int32 = 1
    if setsockopt(sock, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size)) != 0 { return false }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    let converted = broadcast.withCString { inet_pton(AF_INET, $0, &addr.sin_addr) }
    guard converted == 1 else { return false }

    let sent = packet.withUnsafeBytes { buf -> Int in
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
    return sent == packet.count
}
