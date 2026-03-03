package main

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// LogLevel controls the verbosity of log output.
type LogLevel int

const (
	LogDebug LogLevel = iota
	LogInfo
	LogWarn
	LogError
)

const (
	maxLogSize = 5 * 1024 * 1024 // 5 MB
	logFile    = "whispaste.log"
)

var (
	logger     *appLogger
	loggerOnce sync.Once
)

type appLogger struct {
	mu    sync.Mutex
	file  *os.File
	level LogLevel
}

// InitLogger sets up file-based logging in the config directory.
// Falls back to stderr if the log file cannot be opened.
func InitLogger(level LogLevel) {
	loggerOnce.Do(func() {
		logger = &appLogger{level: level}

		dir, err := configDir()
		if err != nil {
			log.SetOutput(os.Stderr)
			return
		}
		path := filepath.Join(dir, logFile)

		// Rotate if file exceeds size limit
		if info, err := os.Stat(path); err == nil && info.Size() > maxLogSize {
			os.Remove(path + ".old")
			os.Rename(path, path+".old")
		}

		f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0600)
		if err != nil {
			log.SetOutput(os.Stderr)
			return
		}
		logger.file = f

		// Redirect the standard logger through our mutex to avoid races
		log.SetOutput(logger)
		log.SetFlags(0) // we format our own prefix
	})
}

// CloseLogger flushes and closes the log file.
func CloseLogger() {
	if logger != nil && logger.file != nil {
		logger.file.Close()
	}
}

// Write implements io.Writer so the standard log package shares our mutex.
func (l *appLogger) Write(p []byte) (n int, err error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file != nil {
		return l.file.Write(p)
	}
	return os.Stderr.Write(p)
}

func (l *appLogger) log(level LogLevel, tag string, format string, args ...interface{}) {
	if level < l.level {
		return
	}
	msg := fmt.Sprintf(format, args...)
	ts := time.Now().Format("2006-01-02 15:04:05.000")
	line := fmt.Sprintf("%s [%s] %s\n", ts, tag, msg)

	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file != nil {
		l.file.WriteString(line)
	} else {
		fmt.Fprint(os.Stderr, line)
	}
}

// logDebug logs a debug-level message (verbose, development only).
func logDebug(format string, args ...interface{}) {
	if logger != nil {
		logger.log(LogDebug, "DBG", format, args...)
	}
}

// logInfo logs an informational message.
func logInfo(format string, args ...interface{}) {
	if logger != nil {
		logger.log(LogInfo, "INF", format, args...)
	}
}

// logWarn logs a warning message.
func logWarn(format string, args ...interface{}) {
	if logger != nil {
		logger.log(LogWarn, "WRN", format, args...)
	}
}

// logError logs an error message.
func logError(format string, args ...interface{}) {
	if logger != nil {
		logger.log(LogError, "ERR", format, args...)
	}
}
