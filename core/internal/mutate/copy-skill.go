package mutate

import (
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"

	"spacevibe.dev/core/internal/coreerr"
	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
)

// Copying a skill folder (MutateItems.copyFolder). A link inside it is copied as a link (never followed) and .git is
// left out. The whole tree is listed and checked before the first byte is written (G-fix.5), so a refusal changes
// nothing:
//
//   - a link that points outside the skill folder is refused, because the copy would hand the other CLI a path to
//     any file the user can read;
//   - anything that is not a file, a folder or a link (a FIFO, a socket, a device) is refused;
//   - a file over maxSkillFileBytes, or a folder over maxSkillTotalBytes in all, is refused (413).
//
// New files get 0600 plus the owner's execute bit of the source (a copied script still runs), never group or other
// bits; new folders get 0700. A new file has a new modification time, so the copy reads as "not counted yet".
const (
	maxSkillFileBytes  = 16 << 20
	maxSkillTotalBytes = 64 << 20
	skipFolder         = ".git"
)

type skillKind int

const (
	skillFolder skillKind = iota
	skillFile
	skillLink
)

type skillNode struct {
	rel    string // path below the skill folder, "" for the top
	kind   skillKind
	mode   fs.FileMode
	target string // link text
}

// skillTree is a vetted listing: folders come before what they hold.
type skillTree struct {
	source string
	nodes  []skillNode
}

func notCopied(why string) error {
	return fail("This skill "+why+", so nothing was copied.", coreerr.StatusConflict)
}

// listSkillFolder walks source (a real path) and refuses what must not be copied.
func listSkillFolder(source string) (skillTree, error) {
	info, err := os.Lstat(source)
	if err != nil {
		return skillTree{}, fail("Could not read "+source+". Nothing was changed.", coreerr.StatusConflict)
	}
	tree := skillTree{source: source}
	var total int64
	var walk func(abs, rel string, info fs.FileInfo) error
	walk = func(abs, rel string, info fs.FileInfo) error {
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			target, err := os.Readlink(abs)
			if err != nil {
				return fail("Could not read "+abs+". Nothing was changed.", coreerr.StatusConflict)
			}
			if !linkStaysInside(source, abs, target) {
				return notCopied("has a link that points outside its folder")
			}
			tree.nodes = append(tree.nodes, skillNode{rel: rel, kind: skillLink, target: target})
		case info.IsDir():
			tree.nodes = append(tree.nodes, skillNode{rel: rel, kind: skillFolder, mode: info.Mode().Perm()})
			entries, err := os.ReadDir(abs)
			if err != nil {
				return fail("Could not read "+abs+". Nothing was changed.", coreerr.StatusConflict)
			}
			names := make([]string, 0, len(entries))
			for _, e := range entries {
				if e.Name() != skipFolder {
					names = append(names, e.Name())
				}
			}
			slices.Sort(names)
			for _, name := range names {
				child := filepath.Join(abs, name)
				childInfo, err := os.Lstat(child)
				if err != nil {
					return fail("Could not read "+child+". Nothing was changed.", coreerr.StatusConflict)
				}
				if err := walk(child, joinRel(rel, name), childInfo); err != nil {
					return err
				}
			}
		case info.Mode().IsRegular():
			if info.Size() > maxSkillFileBytes {
				return fail("This skill has a file over 16 MiB, so nothing was copied.", coreerr.StatusTooLarge)
			}
			total += info.Size()
			if total > maxSkillTotalBytes {
				return fail("This skill is over 64 MiB in all, so nothing was copied.", coreerr.StatusTooLarge)
			}
			tree.nodes = append(tree.nodes, skillNode{rel: rel, kind: skillFile, mode: info.Mode().Perm()})
		default:
			return notCopied("holds something that is not a file, a folder or a link")
		}
		return nil
	}
	if err := walk(source, "", info); err != nil {
		return skillTree{}, err
	}
	return tree, nil
}

func joinRel(rel, name string) string {
	if rel == "" {
		return name
	}
	return rel + "/" + name
}

// linkStaysInside is true when the link at abs, read as a path, ends inside source (or at it). A relative link is
// read from its own folder. The link is not followed past that: its target may not exist yet in the copy.
func linkStaysInside(source, abs, target string) bool {
	if !filepath.IsAbs(target) {
		target = filepath.Join(filepath.Dir(abs), target)
	}
	resolved := roots.ResolvedPath(filepath.Clean(target))
	rel, err := filepath.Rel(source, resolved)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// copyTo writes the tree to destination, which must not exist. created is true once destination itself was made
// by this call. A failed copy leaves what it made for the caller's rollback to send to the trash.
func (t skillTree) copyTo(destination string) (created bool, err error) {
	if err := fsx.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return false, err
	}
	for _, n := range t.nodes {
		path := destination
		if n.rel != "" {
			path = filepath.Join(destination, filepath.FromSlash(n.rel))
		}
		var werr error
		switch n.kind {
		case skillFolder:
			werr = fsx.MkdirExclusive(path, 0o700)
		case skillLink:
			werr = fsx.Symlink(n.target, path)
		case skillFile:
			werr = copyOne(filepath.Join(t.source, filepath.FromSlash(n.rel)), path, n.mode)
		}
		if n.rel == "" && werr == nil {
			created = true
		}
		if werr != nil {
			return created, werr
		}
	}
	return created, nil
}

// copyOne copies one regular file to a path that must not exist. The source is opened without blocking and checked
// on the open descriptor, so a file swapped for a FIFO since the listing cannot hang the copy; its size is checked
// again against the cap while reading.
func copyOne(source, destination string, mode fs.FileMode) error {
	data, err := readRegular(source, maxSkillFileBytes)
	if err != nil {
		if err == errTooLarge {
			return fail("This skill has a file over 16 MiB, so the copy was stopped.", coreerr.StatusTooLarge)
		}
		return fail("Could not read "+source+".", coreerr.StatusConflict)
	}
	return fsx.CreateFileExclusive(destination, data, fsx.NewFileMode|mode&0o100)
}
