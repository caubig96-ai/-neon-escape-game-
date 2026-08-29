package main

import (
    "crypto/rand"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "log"
    "net"
    "net/http"
    "os"
    "os/exec"
    "path/filepath"
    "runtime"
    "strings"
    "time"
)

type actionRequest struct {
    Action string `json:"action"`
    Token  string `json:"token"`
}

func tokenFilePath() string {
    base := strings.TrimSpace(os.Getenv("ProgramData"))
    if base == "" { base = `C:\ProgramData` }
    return filepath.Join(base, "CAU-BIG-Remote", "TOKEN.txt")
}

func loadOrCreateToken() (string, error) {
    if v := strings.TrimSpace(os.Getenv("CAUBIG_REMOTE_TOKEN")); v != "" { return v, nil }
    path := tokenFilePath()
    if b, err := os.ReadFile(path); err == nil {
        if v := strings.TrimSpace(string(b)); len(v) >= 24 { return v, nil }
    }
    raw := make([]byte, 24)
    if _, err := rand.Read(raw); err != nil { return "", err }
    value := hex.EncodeToString(raw)
    if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil { return "", err }
    if err := os.WriteFile(path, []byte(value+"\r\n"), 0600); err != nil { return "", err }
    return value, nil
}

func jsonOut(w http.ResponseWriter, code int, v any) {
    w.Header().Set("Content-Type", "application/json; charset=utf-8")
    w.Header().Set("X-Content-Type-Options", "nosniff")
    w.Header().Set("Cache-Control", "no-store")
    w.WriteHeader(code)
    _ = json.NewEncoder(w).Encode(v)
}

func trustedRemote(remoteAddr string) bool {
    host, _, err := net.SplitHostPort(remoteAddr)
    if err != nil { host = remoteAddr }
    ip := net.ParseIP(strings.Trim(host, "[]"))
    if ip == nil { return false }
    if ip.IsLoopback() || ip.IsPrivate() { return true }
    _, tsNet, _ := net.ParseCIDR("100.64.0.0/10")
    return tsNet != nil && tsNet.Contains(ip)
}

func trustedOnly(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if !trustedRemote(r.RemoteAddr) {
            log.Printf("blocked request from %s", r.RemoteAddr)
            jsonOut(w, http.StatusForbidden, map[string]any{"ok": false, "error": "public Internet access is blocked; use LAN or Tailscale"})
            return
        }
        next(w, r)
    }
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodGet {
        jsonOut(w, http.StatusMethodNotAllowed, map[string]any{"ok": false, "error": "GET required"})
        return
    }
    jsonOut(w, 200, map[string]any{"ok": true, "name": "CAU-BIG", "os": runtime.GOOS, "time": time.Now().Format(time.RFC3339), "remote": r.RemoteAddr})
}

func runAction(action string) error {
    switch strings.ToLower(strings.TrimSpace(action)) {
    case "shutdown": return exec.Command("shutdown.exe", "/s", "/t", "0").Start()
    case "restart": return exec.Command("shutdown.exe", "/r", "/t", "0").Start()
    case "lock": return exec.Command("rundll32.exe", "user32.dll,LockWorkStation").Start()
    case "sleep":
        ps := `Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState('Suspend',$false,$false)`
        return exec.Command("powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps).Start()
    default: return fmt.Errorf("unknown action")
    }
}

func actionHandler(authToken string) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        if r.Method != http.MethodPost {
            jsonOut(w, http.StatusMethodNotAllowed, map[string]any{"ok": false, "error": "POST required"})
            return
        }
        r.Body = http.MaxBytesReader(w, r.Body, 4096)
        var req actionRequest
        if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
            jsonOut(w, http.StatusBadRequest, map[string]any{"ok": false, "error": "invalid request"})
            return
        }
        if req.Token != authToken {
            time.Sleep(250 * time.Millisecond)
            jsonOut(w, http.StatusUnauthorized, map[string]any{"ok": false, "error": "unauthorized"})
            return
        }
        if err := runAction(req.Action); err != nil {
            jsonOut(w, http.StatusBadRequest, map[string]any{"ok": false, "error": err.Error()})
            return
        }
        jsonOut(w, 200, map[string]any{"ok": true, "action": req.Action})
    }
}

func main() {
    authToken, err := loadOrCreateToken()
    if err != nil { log.Fatalf("cannot initialize security token: %v", err) }
    mux := http.NewServeMux()
    mux.HandleFunc("/status", trustedOnly(statusHandler))
    mux.HandleFunc("/action", trustedOnly(actionHandler(authToken)))
    srv := &http.Server{Addr: ":8765", Handler: mux, ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second}
    log.Printf("CAU-BIG Companion listening on port 8765 (LAN/Tailscale only)")
    log.Printf("Security token file: %s", tokenFilePath())
    log.Fatal(srv.ListenAndServe())
}
