package logs

import "bytes"

// lineSplitter splits a byte stream into lines across chunk boundaries (Swift LineSplitter). It works on bytes, so a
// multi-byte character cut by a chunk is safe, and it has no line limit of its own: bufio.Scanner would stop at
// 64 KB, but the usage scanner allows lines of 32 MiB.
type lineSplitter struct {
	maxLineBytes int // <= 0 means no limit
	oversized    int
	partial      []byte
	skipping     bool
}

func (s *lineSplitter) tooLong(n int) bool { return s.maxLineBytes > 0 && n > s.maxLineBytes }

// feed passes every complete line in chunk to body (without its `\n`; a trailing `\r` is kept). The slice is valid
// only during the call.
func (s *lineSplitter) feed(chunk []byte, body func([]byte) error) error {
	start := 0
	for {
		i := bytes.IndexByte(chunk[start:], '\n')
		if i < 0 {
			break
		}
		newline := start + i
		switch {
		case s.skipping:
			s.skipping = false
			s.partial = s.partial[:0]
		case len(s.partial) == 0:
			if err := s.emit(chunk[start:newline], body); err != nil {
				return err
			}
		default:
			s.partial = append(s.partial, chunk[start:newline]...)
			line := s.partial
			s.partial = s.partial[:0]
			if err := s.emit(line, body); err != nil {
				return err
			}
		}
		start = newline + 1
	}
	if start >= len(chunk) || s.skipping {
		return nil
	}
	s.partial = append(s.partial, chunk[start:]...)
	if s.tooLong(len(s.partial)) {
		s.partial = s.partial[:0]
		s.skipping = true
		s.oversized++
	}
	return nil
}

// finish passes a last line that has no newline.
func (s *lineSplitter) finish(body func([]byte) error) error {
	var err error
	if !s.skipping && len(s.partial) > 0 {
		err = s.emit(s.partial, body)
	}
	s.partial = s.partial[:0]
	s.skipping = false
	return err
}

func (s *lineSplitter) emit(line []byte, body func([]byte) error) error {
	if s.tooLong(len(line)) {
		s.oversized++
		return nil
	}
	return body(line)
}
