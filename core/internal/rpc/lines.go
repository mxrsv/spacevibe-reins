package rpc

import (
	"bufio"
	"bytes"
	"io"
)

// lineReader reads newline-terminated lines of bounded length. A line over the cap is discarded
// through its newline, so the stream stays usable (docs/internals/core-protocol.md, "Size overflow").
type lineReader struct {
	r   *bufio.Reader
	buf []byte
}

func newLineReader(r io.Reader) *lineReader {
	return &lineReader{r: bufio.NewReaderSize(r, 64<<10)}
}

// next returns the next line without its "\n" or "\r\n". tooLong is true when the content passed
// max bytes; line is nil then. The returned slice is valid until the next call. At the end of input
// it returns io.EOF; a last line with no newline is returned first.
func (l *lineReader) next(max int) (line []byte, tooLong bool, err error) {
	l.buf = l.buf[:0]
	over := false
	for {
		chunk, rerr := l.r.ReadSlice('\n')
		if !over {
			if len(l.buf)+len(chunk) > max+2 { // room for the "\r\n"
				over = true
				l.buf = l.buf[:0]
			} else {
				l.buf = append(l.buf, chunk...)
			}
		}
		if rerr == bufio.ErrBufferFull {
			continue
		}
		if rerr != nil && rerr != io.EOF {
			return nil, false, rerr
		}
		if rerr == io.EOF && !over && len(l.buf) == 0 {
			return nil, false, io.EOF
		}
		if over {
			return nil, true, nil
		}
		line = bytes.TrimSuffix(l.buf, []byte("\n"))
		line = bytes.TrimSuffix(line, []byte("\r"))
		if len(line) > max {
			return nil, true, nil
		}
		return line, false, nil
	}
}
