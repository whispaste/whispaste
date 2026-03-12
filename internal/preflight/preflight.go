package preflight

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"

	"golang.org/x/sys/cpu"
	"golang.org/x/sys/windows"
)

type Purpose string

const (
	PurposeUse        Purpose = "use"
	PurposeDownload   Purpose = "download"
	PurposeOnboarding Purpose = "onboarding"
	PurposeInspect    Purpose = "inspect"
)

const (
	StatusPass = "pass"
	StatusWarn = "warn"
	StatusFail = "fail"
	StatusSkip = "skip"
	checkOS    = "os-windows"
	checkArch  = "arch-amd64"
	checkAVX   = "cpu-avx"
	checkAVX2  = "cpu-avx2"
	checkCores = "cpu-cores"
	checkRAM   = "memory"
	checkDisk  = "disk-space"
	checkProbe = "server-runtime"
)

const (
	minRuntimeRAMBytes     = 4 << 30
	recommendedRAMBytes    = 8 << 30
	minRecommendedCores    = 4
	runtimeProbeTimeout    = 5 * time.Second
	defaultServerBudget    = 220 << 20
	defaultDiskSafetyBytes = 256 << 20
	cacheTTL               = 15 * time.Second
)

type Options struct {
	Purpose         Purpose
	ModelID         string
	ModelSizeBytes  int64
	NeedServer      bool
	ServerPath      string
	ProbeServer     bool
	StoragePath     string
	ServerBudget    uint64
	DiskSafetyBytes uint64
	Now             time.Time
}

type Result struct {
	Status        string
	Blocking      bool
	ReasonCode    string
	CheckedAt     time.Time
	Facts         Facts
	Checks        []Check
	ServerRuntime Probe
}

type Facts struct {
	OS            string
	Arch          string
	LogicalCores  int
	CPUFeatures   []string
	MemoryBytes   uint64
	FreeDiskBytes uint64
	RequiredBytes uint64
	ServerPath    string
}

type Probe struct {
	Status   string
	ExitCode int
	Output   string
}

type Check struct {
	Code     string
	Status   string
	Blocking bool
	Value    string
	Detail   string
}

type scanner struct {
	mu    sync.Mutex
	cache map[string]cacheEntry
}

type cacheEntry struct {
	at     time.Time
	result Result
}

var defaultScanner = &scanner{cache: map[string]cacheEntry{}}

var procGlobalMemoryStatusEx = windows.NewLazySystemDLL("kernel32.dll").NewProc("GlobalMemoryStatusEx")

type memoryStatusEx struct {
	Length               uint32
	MemoryLoad           uint32
	TotalPhys            uint64
	AvailPhys            uint64
	TotalPageFile        uint64
	AvailPageFile        uint64
	TotalVirtual         uint64
	AvailVirtual         uint64
	AvailExtendedVirtual uint64
}

func Scan(opts Options) Result {
	return defaultScanner.Scan(opts)
}

func Invalidate() {
	defaultScanner.Invalidate()
}

func (s *scanner) Scan(opts Options) Result {
	key := cacheKey(opts)
	now := opts.Now
	if now.IsZero() {
		now = time.Now()
	}

	s.mu.Lock()
	if entry, ok := s.cache[key]; ok && now.Sub(entry.at) < cacheTTL {
		s.mu.Unlock()
		return cloneResult(entry.result)
	}
	s.mu.Unlock()

	result := runScan(opts, now)

	s.mu.Lock()
	s.cache[key] = cacheEntry{at: now, result: cloneResult(result)}
	s.mu.Unlock()

	return result
}

func (s *scanner) Invalidate() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cache = map[string]cacheEntry{}
}

func runScan(opts Options, now time.Time) Result {
	result := Result{
		Status:    StatusPass,
		CheckedAt: now,
		Facts: Facts{
			OS:           runtime.GOOS,
			Arch:         runtime.GOARCH,
			LogicalCores: runtime.NumCPU(),
			ServerPath:   opts.ServerPath,
		},
	}
	firstWarnCode := ""

	appendCheck := func(check Check) {
		result.Checks = append(result.Checks, check)
		switch check.Status {
		case StatusFail:
			if check.Blocking {
				result.Blocking = true
				result.Status = StatusFail
				if result.ReasonCode == "" {
					result.ReasonCode = check.Code
				}
			} else if result.Status == StatusPass {
				result.Status = StatusWarn
			}
		case StatusWarn:
			if firstWarnCode == "" {
				firstWarnCode = check.Code
			}
			if result.Status == StatusPass {
				result.Status = StatusWarn
			}
		}
	}

	appendCheck(checkOSWindows(runtime.GOOS))
	appendCheck(checkAMD64(runtime.GOARCH))
	appendCheck(checkCPUFeatures(&result.Facts))
	appendCheck(checkLogicalCores(result.Facts.LogicalCores))
	appendCheck(checkMemory(&result.Facts))
	appendCheck(checkDiskSpace(opts, &result.Facts))

	if opts.ProbeServer {
		probeCheck, probe := checkServerRuntime(opts.ServerPath)
		result.ServerRuntime = probe
		appendCheck(probeCheck)
	}

	result.ReasonCode = resolveReasonCode(result.Status, result.ReasonCode, firstWarnCode)

	return result
}

func resolveReasonCode(status string, currentReason string, firstWarnCode string) string {
	if currentReason != "" {
		return currentReason
	}
	if status == StatusWarn {
		if firstWarnCode != "" {
			return firstWarnCode
		}
		return checkAVX2
	}
	return "ready"
}

func cloneResult(in Result) Result {
	out := in
	out.Facts.CPUFeatures = append([]string(nil), in.Facts.CPUFeatures...)
	out.Checks = append([]Check(nil), in.Checks...)
	return out
}

func cacheKey(opts Options) string {
	var b strings.Builder
	b.WriteString(string(opts.Purpose))
	b.WriteString("|")
	b.WriteString(opts.ModelID)
	b.WriteString("|")
	b.WriteString(fmt.Sprintf("%d|%t|%t|%s|%s", opts.ModelSizeBytes, opts.NeedServer, opts.ProbeServer, opts.ServerPath, opts.StoragePath))
	return b.String()
}

func checkOSWindows(goos string) Check {
	if goos == "windows" {
		return Check{Code: checkOS, Status: StatusPass, Blocking: true, Value: goos}
	}
	return Check{Code: checkOS, Status: StatusFail, Blocking: true, Value: goos, Detail: "Local STT is currently supported on Windows only."}
}

func checkAMD64(arch string) Check {
	if arch == "amd64" {
		return Check{Code: checkArch, Status: StatusPass, Blocking: true, Value: arch}
	}
	return Check{Code: checkArch, Status: StatusFail, Blocking: true, Value: arch, Detail: "The packaged whisper-server build requires a 64-bit x86 CPU."}
}

func checkCPUFeatures(facts *Facts) Check {
	features := []string{}
	if cpu.X86.HasSSE41 {
		features = append(features, "SSE4.1")
	}
	if cpu.X86.HasSSE42 {
		features = append(features, "SSE4.2")
	}
	if cpu.X86.HasAVX {
		features = append(features, "AVX")
	}
	if cpu.X86.HasAVX2 {
		features = append(features, "AVX2")
	}
	if cpu.X86.HasFMA {
		features = append(features, "FMA")
	}
	facts.CPUFeatures = features

	if !cpu.X86.HasAVX {
		return Check{Code: checkAVX, Status: StatusFail, Blocking: true, Value: strings.Join(features, ", "), Detail: "The current whisper-server build requires AVX CPU instructions."}
	}
	if !cpu.X86.HasAVX2 {
		return Check{Code: checkAVX2, Status: StatusWarn, Blocking: false, Value: strings.Join(features, ", "), Detail: "AVX2 is not available. Local STT may still work, but performance headroom will be lower."}
	}
	return Check{Code: checkAVX, Status: StatusPass, Blocking: true, Value: strings.Join(features, ", ")}
}

func checkLogicalCores(cores int) Check {
	if cores >= minRecommendedCores {
		return Check{Code: checkCores, Status: StatusPass, Blocking: false, Value: fmt.Sprintf("%d", cores)}
	}
	return Check{Code: checkCores, Status: StatusWarn, Blocking: false, Value: fmt.Sprintf("%d", cores), Detail: "Fewer than 4 logical CPU cores can noticeably slow down local transcription."}
}

func checkMemory(facts *Facts) Check {
	var mem memoryStatusEx
	mem.Length = uint32(unsafe.Sizeof(mem))
	r1, _, callErr := procGlobalMemoryStatusEx.Call(uintptr(unsafe.Pointer(&mem)))
	if r1 == 0 {
		if callErr == nil || callErr == syscall.Errno(0) {
			callErr = syscall.EINVAL
		}
		return Check{Code: checkRAM, Status: StatusWarn, Blocking: false, Detail: fmt.Sprintf("Memory scan failed: %v", callErr)}
	}
	facts.MemoryBytes = mem.TotalPhys
	value := formatBytes(mem.TotalPhys)
	if mem.TotalPhys < minRuntimeRAMBytes {
		return Check{Code: checkRAM, Status: StatusFail, Blocking: true, Value: value, Detail: "At least 4 GB RAM is required for reliable local STT startup."}
	}
	if mem.TotalPhys < recommendedRAMBytes {
		return Check{Code: checkRAM, Status: StatusWarn, Blocking: false, Value: value, Detail: "8 GB RAM or more is recommended for smoother local STT usage."}
	}
	return Check{Code: checkRAM, Status: StatusPass, Blocking: false, Value: value}
}

func checkDiskSpace(opts Options, facts *Facts) Check {
	if opts.StoragePath == "" {
		return Check{Code: checkDisk, Status: StatusWarn, Blocking: false, Detail: "Storage path unavailable; free disk space could not be verified."}
	}

	path, err := windows.UTF16PtrFromString(opts.StoragePath)
	if err != nil {
		return Check{Code: checkDisk, Status: StatusWarn, Blocking: false, Detail: fmt.Sprintf("Disk scan failed: %v", err)}
	}

	var freeBytes uint64
	var totalBytes uint64
	var totalFreeBytes uint64
	if err := windows.GetDiskFreeSpaceEx(path, &freeBytes, &totalBytes, &totalFreeBytes); err != nil {
		return Check{Code: checkDisk, Status: StatusWarn, Blocking: false, Detail: fmt.Sprintf("Disk scan failed: %v", err)}
	}

	required := requiredDiskBytes(opts)
	facts.FreeDiskBytes = freeBytes
	facts.RequiredBytes = required

	if required == 0 {
		if freeBytes >= defaultDiskSafetyBytes {
			return Check{Code: checkDisk, Status: StatusPass, Blocking: false, Value: formatBytes(freeBytes)}
		}
		return Check{Code: checkDisk, Status: StatusWarn, Blocking: false, Value: formatBytes(freeBytes), Detail: "Free disk space is getting low for local model downloads and updates."}
	}

	detail := fmt.Sprintf("%s free, %s required", formatBytes(freeBytes), formatBytes(required))
	if freeBytes < required {
		return Check{Code: checkDisk, Status: StatusFail, Blocking: true, Value: detail, Detail: "There is not enough free disk space for the selected local STT setup."}
	}
	return Check{Code: checkDisk, Status: StatusPass, Blocking: false, Value: detail}
}

func requiredDiskBytes(opts Options) uint64 {
	safety := opts.DiskSafetyBytes
	if safety == 0 {
		safety = defaultDiskSafetyBytes
	}
	required := safety
	if opts.Purpose == PurposeDownload || opts.Purpose == PurposeOnboarding {
		required += uint64(max64(opts.ModelSizeBytes, 0))
		if opts.NeedServer {
			serverBudget := opts.ServerBudget
			if serverBudget == 0 {
				serverBudget = defaultServerBudget
			}
			required += serverBudget
		}
	}
	return required
}

func checkServerRuntime(serverPath string) (Check, Probe) {
	if serverPath == "" {
		return Check{Code: checkProbe, Status: StatusSkip, Blocking: false, Detail: "No whisper-server path provided."}, Probe{Status: StatusSkip}
	}
	if _, err := os.Stat(serverPath); err != nil {
		return Check{Code: checkProbe, Status: StatusSkip, Blocking: false, Detail: "whisper-server is not installed yet."}, Probe{Status: StatusSkip}
	}

	ctx, cancel := context.WithTimeout(context.Background(), runtimeProbeTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, serverPath, "--help")
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	var output bytes.Buffer
	cmd.Stdout = &output
	cmd.Stderr = &output
	err := cmd.Run()
	summary := summarizeOutput(output.String())
	probe := Probe{Output: summary}

	if ctx.Err() == context.DeadlineExceeded {
		probe.Status = StatusFail
		return Check{
			Code:     checkProbe,
			Status:   StatusFail,
			Blocking: true,
			Detail:   "whisper-server did not respond to a lightweight runtime probe.",
			Value:    summary,
		}, probe
	}

	lower := strings.ToLower(summary)
	if err == nil || strings.Contains(lower, "usage:") || strings.Contains(lower, "--model") {
		probe.Status = StatusPass
		return Check{Code: checkProbe, Status: StatusPass, Blocking: true, Value: summary}, probe
	}

	probe.Status = StatusFail
	if exitErr, ok := err.(*exec.ExitError); ok {
		probe.ExitCode = exitErr.ExitCode()
	}
	return Check{
		Code:     checkProbe,
		Status:   StatusFail,
		Blocking: true,
		Detail:   "whisper-server could not start in a lightweight runtime probe.",
		Value:    summary,
	}, probe
}

func summarizeOutput(text string) string {
	text = strings.Join(strings.Fields(strings.TrimSpace(text)), " ")
	if len(text) > 220 {
		return text[:220] + "..."
	}
	return text
}

func formatBytes(v uint64) string {
	const unit = 1024
	if v < unit {
		return fmt.Sprintf("%d B", v)
	}
	div, exp := uint64(unit), 0
	for n := v / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", float64(v)/float64(div), "KMGTPE"[exp])
}

func max64(v int64, fallback int64) int64 {
	if v > 0 {
		return v
	}
	return fallback
}
