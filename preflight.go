package main

import (
	"fmt"
	"strings"
	"time"

	"github.com/whispaste/whispaste/internal/models"
	preflightpkg "github.com/whispaste/whispaste/internal/preflight"
)

type localSTTPreflightView struct {
	Status    string                       `json:"status"`
	Blocking  bool                         `json:"blocking"`
	Summary   string                       `json:"summary"`
	Message   string                       `json:"message"`
	CheckedAt string                       `json:"checkedAt"`
	Checks    []localSTTPreflightCheckView `json:"checks"`
	Facts     localSTTPreflightFactsView   `json:"facts"`
}

type localSTTPreflightCheckView struct {
	Code     string `json:"code"`
	Status   string `json:"status"`
	Blocking bool   `json:"blocking"`
	Title    string `json:"title"`
	Detail   string `json:"detail"`
	Value    string `json:"value"`
}

type localSTTPreflightFactsView struct {
	OS           string `json:"os"`
	Arch         string `json:"arch"`
	LogicalCores int    `json:"logicalCores"`
	CPUFeatures  string `json:"cpuFeatures"`
	Memory       string `json:"memory"`
	FreeDisk     string `json:"freeDisk"`
	RequiredDisk string `json:"requiredDisk"`
	RuntimeProbe string `json:"runtimeProbe"`
}

var runLocalSTTPreflight = defaultLocalSTTPreflight

func defaultLocalSTTPreflight(modelID, purpose string) preflightpkg.Result {
	serverPath, _ := STTServerPath()
	storagePath, _ := STTDir()
	model := models.Find(modelID)
	modelSize := int64(0)
	if model != nil && !models.IsDownloaded(modelID) {
		modelSize = model.SizeBytes
	}
	result := preflightpkg.Scan(preflightpkg.Options{
		Purpose:        localSTTPreflightPurpose(purpose),
		ModelID:        modelID,
		ModelSizeBytes: modelSize,
		NeedServer:     !IsSTTServerInstalled(),
		ServerPath:     serverPath,
		ProbeServer:    IsSTTServerInstalled() && purpose != "download",
		StoragePath:    storagePath,
		Now:            time.Now(),
	})
	logLocalSTTPreflight(result, purpose, modelID)
	return result
}

func localSTTPreflightPurpose(purpose string) preflightpkg.Purpose {
	switch purpose {
	case string(preflightpkg.PurposeDownload):
		return preflightpkg.PurposeDownload
	case string(preflightpkg.PurposeOnboarding):
		return preflightpkg.PurposeOnboarding
	case string(preflightpkg.PurposeInspect):
		return preflightpkg.PurposeInspect
	default:
		return preflightpkg.PurposeUse
	}
}

func localSTTPreflightViewFor(modelID, purpose string) localSTTPreflightView {
	result := runLocalSTTPreflight(modelID, purpose)
	return buildLocalSTTPreflightView(result, purpose)
}

func buildLocalSTTPreflightView(result preflightpkg.Result, purpose string) localSTTPreflightView {
	checks := make([]localSTTPreflightCheckView, 0, len(result.Checks))
	for _, check := range result.Checks {
		if check.Status == preflightpkg.StatusSkip {
			continue
		}
		checks = append(checks, localSTTPreflightCheckView{
			Code:     check.Code,
			Status:   check.Status,
			Blocking: check.Blocking,
			Title:    localizeLocalSTTPreflightCheckTitle(check.Code),
			Detail:   localizeLocalSTTPreflightCheckDetail(check),
			Value:    check.Value,
		})
	}

	return localSTTPreflightView{
		Status:    result.Status,
		Blocking:  result.Blocking,
		Summary:   localizeLocalSTTPreflightSummary(result, purpose),
		Message:   localizeLocalSTTPreflightMessage(result),
		CheckedAt: result.CheckedAt.Format(time.RFC3339),
		Checks:    checks,
		Facts: localSTTPreflightFactsView{
			OS:           result.Facts.OS,
			Arch:         result.Facts.Arch,
			LogicalCores: result.Facts.LogicalCores,
			CPUFeatures:  emptyDash(strings.Join(result.Facts.CPUFeatures, ", ")),
			Memory:       emptyDash(formatBytes(result.Facts.MemoryBytes)),
			FreeDisk:     emptyDash(formatBytes(result.Facts.FreeDiskBytes)),
			RequiredDisk: emptyDash(formatBytes(result.Facts.RequiredBytes)),
			RuntimeProbe: emptyDash(result.ServerRuntime.Output),
		},
	}
}

func ensureLocalSTTAllowed(modelID, purpose string) error {
	result := runLocalSTTPreflight(modelID, purpose)
	if !result.Blocking {
		return nil
	}
	return fmt.Errorf("%s", localizeLocalSTTPreflightMessage(result))
}

func invalidateLocalSTTPreflight() {
	preflightpkg.Invalidate()
}

func localizeLocalSTTPreflightSummary(result preflightpkg.Result, purpose string) string {
	switch result.Status {
	case preflightpkg.StatusFail:
		return T("preflight.summary.fail")
	case preflightpkg.StatusWarn:
		return T("preflight.summary.warn")
	default:
		if purpose == string(preflightpkg.PurposeDownload) || purpose == string(preflightpkg.PurposeOnboarding) {
			return T("preflight.summary.pass_download")
		}
		return T("preflight.summary.pass")
	}
}

func localizeLocalSTTPreflightMessage(result preflightpkg.Result) string {
	switch result.ReasonCode {
	case "ready":
		return T("preflight.summary.pass")
	case "os-windows":
		return T("preflight.reason.os")
	case "arch-amd64":
		return T("preflight.reason.arch")
	case "cpu-avx":
		return T("preflight.reason.avx")
	case "cpu-avx2":
		return T("preflight.reason.avx2")
	case "cpu-cores":
		return T("preflight.reason.cores")
	case "memory":
		return T("preflight.reason.memory")
	case "disk-space":
		return T("preflight.reason.disk")
	case "server-runtime":
		return T("preflight.reason.runtime")
	default:
		return T("preflight.reason.unknown")
	}
}

func localizeLocalSTTPreflightCheckTitle(code string) string {
	switch code {
	case "os-windows":
		return T("preflight.check.os")
	case "arch-amd64":
		return T("preflight.check.arch")
	case "cpu-avx":
		return T("preflight.check.avx")
	case "cpu-avx2":
		return T("preflight.check.avx2")
	case "cpu-cores":
		return T("preflight.check.cores")
	case "memory":
		return T("preflight.check.memory")
	case "disk-space":
		return T("preflight.check.disk")
	case "server-runtime":
		return T("preflight.check.runtime")
	default:
		return code
	}
}

func localizeLocalSTTPreflightCheckDetail(check preflightpkg.Check) string {
	switch check.Code {
	case "os-windows":
		if check.Status == preflightpkg.StatusFail {
			return T("preflight.detail.os.fail")
		}
	case "arch-amd64":
		if check.Status == preflightpkg.StatusFail {
			return T("preflight.detail.arch.fail")
		}
	case "cpu-avx":
		if check.Status == preflightpkg.StatusFail {
			return T("preflight.detail.avx.fail")
		}
	case "cpu-avx2":
		if check.Status == preflightpkg.StatusWarn {
			return T("preflight.detail.avx2.warn")
		}
	case "cpu-cores":
		if check.Status == preflightpkg.StatusWarn {
			return T("preflight.detail.cores.warn")
		}
	case "memory":
		if check.Status == preflightpkg.StatusFail {
			return T("preflight.detail.memory.fail")
		}
		if check.Status == preflightpkg.StatusWarn {
			return T("preflight.detail.memory.warn")
		}
	case "disk-space":
		if check.Status == preflightpkg.StatusFail {
			return fmt.Sprintf(T("preflight.detail.disk.fail"), check.Value)
		}
		if check.Status == preflightpkg.StatusWarn {
			if check.Detail != "" {
				return check.Detail
			}
			return T("preflight.detail.disk.warn")
		}
	case "server-runtime":
		if check.Status == preflightpkg.StatusFail {
			if check.Value != "" {
				return fmt.Sprintf(T("preflight.detail.runtime.fail"), check.Value)
			}
			return T("preflight.detail.runtime.fail_no_output")
		}
	}

	if check.Detail != "" {
		return check.Detail
	}
	return ""
}

func logLocalSTTPreflight(result preflightpkg.Result, purpose, modelID string) {
	logInfo("Local STT preflight: purpose=%s model=%s status=%s blocking=%v", purpose, modelID, result.Status, result.Blocking)
	for _, check := range result.Checks {
		switch check.Status {
		case preflightpkg.StatusFail:
			if check.Blocking {
				logInfo("Local STT preflight blocking failure: code=%s value=%s detail=%s", check.Code, check.Value, check.Detail)
			} else {
				logInfo("Local STT preflight warning-as-failure: code=%s value=%s detail=%s", check.Code, check.Value, check.Detail)
			}
		case preflightpkg.StatusWarn:
			logInfo("Local STT preflight warning: code=%s value=%s detail=%s", check.Code, check.Value, check.Detail)
		case preflightpkg.StatusPass:
			logDebug("Local STT preflight pass: code=%s value=%s", check.Code, check.Value)
		}
	}
	if result.ServerRuntime.Output != "" {
		logDebug("Local STT preflight runtime probe: status=%s exit=%d output=%s", result.ServerRuntime.Status, result.ServerRuntime.ExitCode, result.ServerRuntime.Output)
	}
}

func formatBytes(v uint64) string {
	if v == 0 {
		return ""
	}
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

func emptyDash(v string) string {
	if strings.TrimSpace(v) == "" {
		return "—"
	}
	return v
}

// getSystemRAM returns total physical memory in bytes (cached from preflight).
func getSystemRAM() uint64 {
	result := runLocalSTTPreflight("", "inspect")
	return result.Facts.MemoryBytes
}

func startupMemoryGateMessage() string {
	result := runLocalSTTPreflight("", "inspect")
	for _, check := range result.Checks {
		if check.Code == "memory" && check.Status == preflightpkg.StatusFail {
			return localizeLocalSTTPreflightCheckDetail(check)
		}
	}
	return ""
}
