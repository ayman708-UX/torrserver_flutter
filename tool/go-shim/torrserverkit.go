package torrserverkit

/*
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"server"
	"server/log"
	"server/settings"
)

var (
	runningMu sync.Mutex
	running   int32
)

//export StartServer
func StartServer(port C.int, dataDir *C.char) *C.char {
	runningMu.Lock()
	defer runningMu.Unlock()

	if atomic.LoadInt32(&running) == 1 {
		return C.CString("server is already running")
	}

	portInt := int(port)
	if portInt <= 0 {
		portInt = 8090
	}
	portStr := strconv.Itoa(portInt)

	var dir string
	if dataDir != nil {
		dir = C.GoString(dataDir)
	}
	if dir == "" {
		dir, _ = os.Getwd()
	}

	if err := os.MkdirAll(dir, 0755); err != nil {
		return C.CString(fmt.Sprintf("failed to create data directory: %v", err))
	}

	// Pre-check port availability before passing to TorrServer to avoid os.Exit(1)
	ln, err := net.Listen("tcp", "127.0.0.1:"+portStr)
	if err != nil {
		return C.CString(fmt.Sprintf("port %s is already in use: %v", portStr, err))
	}
	_ = ln.Close()

	settings.Path = dir
	log.Init(filepath.Join(dir, "torrserver.log"), filepath.Join(dir, "web.log"))

	settings.Args = &settings.ExecArgs{
		Port:     portStr,
		Path:     dir,
		RDB:      false,
		SearchWA: true,
	}

	atomic.StoreInt32(&running, 1)

	go func() {
		server.Start()
		server.WaitServer()
		atomic.StoreInt32(&running, 0)
	}()

	return nil
}

//export StopServer
func StopServer() *C.char {
	runningMu.Lock()
	defer runningMu.Unlock()

	if atomic.LoadInt32(&running) == 0 {
		return nil
	}

	done := make(chan struct{})
	go func() {
		server.Stop()
		close(done)
	}()

	select {
	case <-done:
		atomic.StoreInt32(&running, 0)
		return nil
	case <-time.After(5 * time.Second):
		atomic.StoreInt32(&running, 0)
		return C.CString("server shutdown timed out")
	}
}

//export IsRunning
func IsRunning() C.int {
	return C.int(atomic.LoadInt32(&running))
}
