package main

import (
	"sync"
)

var (
	selectedProjectMu sync.RWMutex
	selectedProjectID string
)

func getSelectedProjectID() string {
	selectedProjectMu.RLock()
	defer selectedProjectMu.RUnlock()
	return selectedProjectID
}

func setSelectedProjectID(id string) {
	selectedProjectMu.Lock()
	defer selectedProjectMu.Unlock()
	selectedProjectID = id
}
