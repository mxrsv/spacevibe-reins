package activity

import (
	"errors"
	"io"
	"os"

	"spacevibe.dev/core/internal/clis"
	"spacevibe.dev/core/internal/textjs"
)

// Log discovery (Activity.swift listLogs and its helpers).

const (
	childHeadBytes = 64 * 1024
	indexTailBytes = 1024 * 1024
)

type logFile struct {
	path    string
	cli     clis.ID
	session string
	sub     bool
	mtimeMs float64
}

// mtimeMs is the modification time in milliseconds, computed as seconds*1000 + nanoseconds/1e6 in floating point.
func mtimeMs(path string) (float64, bool) {
	info, err := os.Stat(path)
	if err != nil {
		return 0, false
	}
	t := info.ModTime()
	return textjs.BoundedTimestamp(float64(t.Unix())*1000 + float64(t.Nanosecond())/1e6)
}

// readRegularFile reads a file that is a regular file. A FIFO would block a reader that has no writer.
func readRegularFile(path string) ([]byte, bool) {
	data, err := readRegularFileErr(path)
	return data, err == nil
}

// errNotRegular is what readRegularFileErr returns for a FIFO, a directory or a device.
var errNotRegular = errors.New("not a regular file")

// readRegularFileErr is readRegularFile with the reason: an fs error (os.IsNotExist tells a vanished file from an
// unreadable one) or errNotRegular.
func readRegularFileErr(path string) ([]byte, error) {
	info, err := os.Stat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, errNotRegular
	}
	return os.ReadFile(path)
}

// readJSONObject reads a file whose root is a JSON object.
func readJSONObject(path string) (jv, bool) {
	data, ok := readRegularFile(path)
	if !ok {
		return jv{}, false
	}
	return parseLine(data)
}

// readHead is the first n bytes of a regular file.
func readHead(path string, n int) []byte {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() {
		return nil
	}
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	buf := make([]byte, n)
	got, _ := io.ReadFull(f, buf)
	return buf[:got]
}
