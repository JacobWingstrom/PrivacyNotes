package main

import (
	"bufio"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// System stats for the Hush "Server" widget. Read from /proc and /sys, so on Linux (and in Docker)
// they describe the host: CPU, memory, load and uptime are host-wide. Disks are the data folder plus
// any mount points listed in HUSH_DISKS (for example "/host" when the host root is mounted read-only).

type cpuTimes struct{ idle, total uint64 }

type diskInfo struct {
	Mount string `json:"mount"`
	Total uint64 `json:"total"`
	Used  uint64 `json:"used"`
}

type tempInfo struct {
	Name    string  `json:"name"`
	Celsius float64 `json:"celsius"`
}

type systemInfo struct {
	Hostname   string     `json:"hostname"`
	OS         string     `json:"os"`
	Kernel     string     `json:"kernel"`
	Arch       string     `json:"arch"`
	Uptime     float64    `json:"uptime"`
	Load       []float64  `json:"load"`
	CPUPercent float64    `json:"cpuPercent"`
	PerCore    []float64  `json:"perCore"`
	Cores      int        `json:"cores"`
	MemTotal   uint64     `json:"memTotal"`
	MemUsed    uint64     `json:"memUsed"`
	SwapTotal  uint64     `json:"swapTotal"`
	SwapUsed   uint64     `json:"swapUsed"`
	Disks      []diskInfo `json:"disks"`
	Temps      []tempInfo `json:"temps"`
	NetRx      uint64     `json:"netRx"`
	NetTx      uint64     `json:"netTx"`
	Time       int64      `json:"time"`
}

func (s *server) system(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, 200, collectSystem(s.dataDir, os.Getenv("HUSH_DISKS"), "/proc", "/sys"))
}

func collectSystem(dataDir, extraDisks, proc, sys string) systemInfo {
	info := systemInfo{Arch: runtime.GOARCH, Time: time.Now().Unix(), Load: []float64{0, 0, 0}}
	info.Hostname, _ = os.Hostname()
	if b, err := os.ReadFile("/host/etc/hostname"); err == nil && len(strings.TrimSpace(string(b))) > 0 {
		info.Hostname = strings.TrimSpace(string(b))
	}
	info.OS = osName()
	if b, err := os.ReadFile(filepath.Join(proc, "sys/kernel/osrelease")); err == nil {
		info.Kernel = strings.TrimSpace(string(b))
	}
	if b, err := os.ReadFile(filepath.Join(proc, "uptime")); err == nil {
		if f := strings.Fields(string(b)); len(f) > 0 {
			info.Uptime, _ = strconv.ParseFloat(f[0], 64)
		}
	}
	if b, err := os.ReadFile(filepath.Join(proc, "loadavg")); err == nil {
		f := strings.Fields(string(b))
		for i := 0; i < 3 && i < len(f); i++ {
			info.Load[i], _ = strconv.ParseFloat(f[i], 64)
		}
	}

	// CPU: two samples a quarter second apart.
	a := readCPU(proc)
	time.Sleep(250 * time.Millisecond)
	b := readCPU(proc)
	if len(a) > 0 && len(a) == len(b) {
		info.CPUPercent = busy(a[0], b[0])
		for i := 1; i < len(a); i++ {
			info.PerCore = append(info.PerCore, busy(a[i], b[i]))
		}
		info.Cores = len(a) - 1
	}
	if info.Cores == 0 {
		info.Cores = runtime.NumCPU()
	}

	mem := readMeminfo(proc)
	info.MemTotal = mem["MemTotal"]
	if avail, ok := mem["MemAvailable"]; ok && info.MemTotal >= avail {
		info.MemUsed = info.MemTotal - avail
	}
	info.SwapTotal = mem["SwapTotal"]
	if info.SwapTotal >= mem["SwapFree"] {
		info.SwapUsed = info.SwapTotal - mem["SwapFree"]
	}

	mounts := []string{dataDir}
	for _, m := range strings.Split(extraDisks, ",") {
		if m = strings.TrimSpace(m); m != "" {
			mounts = append(mounts, m)
		}
	}
	seen := map[string]bool{}
	for _, m := range mounts {
		var st syscall.Statfs_t
		if err := syscall.Statfs(m, &st); err != nil {
			continue
		}
		total := st.Blocks * uint64(st.Bsize)
		free := st.Bavail * uint64(st.Bsize)
		key := strconv.FormatUint(total, 10) + "/" + strconv.FormatUint(st.Bfree, 10)
		if total == 0 || seen[key] {
			continue
		}
		seen[key] = true
		info.Disks = append(info.Disks, diskInfo{Mount: m, Total: total, Used: total - free})
	}

	info.Temps = readTemps(sys)
	info.NetRx, info.NetTx = readNet(proc)
	return info
}

func busy(a, b cpuTimes) float64 {
	dt := float64(b.total - a.total)
	if dt <= 0 || b.total < a.total {
		return 0
	}
	return 100 * (1 - float64(b.idle-a.idle)/dt)
}

func readCPU(proc string) []cpuTimes {
	f, err := os.Open(filepath.Join(proc, "stat"))
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []cpuTimes
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 5 || !strings.HasPrefix(fields[0], "cpu") {
			continue
		}
		var t cpuTimes
		for i, v := range fields[1:] {
			n, _ := strconv.ParseUint(v, 10, 64)
			if i >= 8 { // guest time is already counted in user time
				break
			}
			t.total += n
			if i == 3 || i == 4 { // idle + iowait
				t.idle += n
			}
		}
		out = append(out, t)
	}
	return out
}

func readMeminfo(proc string) map[string]uint64 {
	out := map[string]uint64{}
	f, err := os.Open(filepath.Join(proc, "meminfo"))
	if err != nil {
		return out
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) < 2 {
			continue
		}
		n, _ := strconv.ParseUint(fields[1], 10, 64)
		out[strings.TrimSuffix(fields[0], ":")] = n * 1024
	}
	return out
}

func readNet(proc string) (rx, tx uint64) {
	f, err := os.Open(filepath.Join(proc, "net/dev"))
	if err != nil {
		return
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		colon := strings.Index(line, ":")
		if colon < 0 {
			continue
		}
		name := strings.TrimSpace(line[:colon])
		if name == "lo" || strings.HasPrefix(name, "veth") || strings.HasPrefix(name, "docker") || strings.HasPrefix(name, "br-") {
			continue
		}
		fields := strings.Fields(line[colon+1:])
		if len(fields) < 9 {
			continue
		}
		r, _ := strconv.ParseUint(fields[0], 10, 64)
		t, _ := strconv.ParseUint(fields[8], 10, 64)
		rx += r
		tx += t
	}
	return
}

func readTemps(sys string) []tempInfo {
	var out []tempInfo
	zones, _ := filepath.Glob(filepath.Join(sys, "class/thermal/thermal_zone*"))
	for _, z := range zones {
		t := readMilli(filepath.Join(z, "temp"))
		if t <= 0 {
			continue
		}
		name := readTrim(filepath.Join(z, "type"))
		if name == "" {
			name = filepath.Base(z)
		}
		out = append(out, tempInfo{Name: name, Celsius: t})
	}
	inputs, _ := filepath.Glob(filepath.Join(sys, "class/hwmon/hwmon*/temp*_input"))
	for _, in := range inputs {
		t := readMilli(in)
		if t <= 0 {
			continue
		}
		dir := filepath.Dir(in)
		label := readTrim(strings.TrimSuffix(in, "_input") + "_label")
		chip := readTrim(filepath.Join(dir, "name"))
		name := strings.TrimSpace(chip + " " + label)
		if name == "" {
			name = filepath.Base(in)
		}
		out = append(out, tempInfo{Name: name, Celsius: t})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Celsius > out[j].Celsius })
	if len(out) > 12 {
		out = out[:12]
	}
	return out
}

func readMilli(path string) float64 {
	v, err := strconv.ParseFloat(readTrim(path), 64)
	if err != nil {
		return 0
	}
	return v / 1000
}

func readTrim(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func osName() string {
	for _, p := range []string{"/host/etc/os-release", "/etc/os-release"} {
		b, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		for _, line := range strings.Split(string(b), "\n") {
			if strings.HasPrefix(line, "PRETTY_NAME=") {
				return strings.Trim(strings.TrimPrefix(line, "PRETTY_NAME="), "\"")
			}
		}
	}
	return runtime.GOOS
}
