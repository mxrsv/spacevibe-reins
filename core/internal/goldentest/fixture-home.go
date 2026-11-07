package goldentest

import (
	"bytes"
	"encoding/json"
	"errors"
	"io/fs"
	"math"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// CanonicalRoot is the path the frozen goldens ran on. Ids in them (hook ids, project ids) are hashes of
// absolute paths under it (B6), so the shared tree must live exactly here. It is a macOS path; the fixture
// tests skip elsewhere.
const CanonicalRoot = "/private/tmp/reins-fixture-home"

const (
	stampName        = ".fixture-stamp"
	dataFolder       = ".reins"
	mtimeToleranceMS = 1.0
)

var materializeLock sync.Mutex

// Manifest is fixtures/manifest.json: the fixed clock of the fixture, the placeholder, the content digest that
// serves as the tree's stamp, and every file's modification time in ms since 1970 (git keeps no mtimes).
type Manifest struct {
	Now    float64            `json:"now"`
	Token  string             `json:"token"`
	Digest string             `json:"digest"`
	Mtimes map[string]float64 `json:"mtimes"`
}

// LoadManifest reads manifest.json from the fixtures folder.
func LoadManifest() (Manifest, error) {
	dir, err := FixturesDir()
	if err != nil {
		return Manifest{}, err
	}
	return loadManifest(dir)
}

func loadManifest(fixtures string) (Manifest, error) {
	data, err := os.ReadFile(filepath.Join(fixtures, "manifest.json"))
	if err != nil {
		return Manifest{}, errors.New("goldentest: cannot read manifest.json")
	}
	var m Manifest
	if err := json.Unmarshal(data, &m); err != nil {
		return Manifest{}, errors.New("goldentest: manifest.json is not a valid manifest")
	}
	if m.Token == "" || m.Digest == "" {
		return Manifest{}, errors.New("goldentest: manifest.json has no token or digest")
	}
	for rel := range m.Mtimes {
		if !filepath.IsLocal(rel) {
			return Manifest{}, errors.New("goldentest: manifest.json lists a path outside the tree")
		}
	}
	return m, nil
}

// Now is the fixed "now" of the fixture; pass it wherever the Node run used it.
func Now() (time.Time, error) {
	m, err := LoadManifest()
	if err != nil {
		return time.Time{}, err
	}
	return time.UnixMilli(int64(m.Now)), nil
}

// Env is the environment that points every root at the tree at root, with the real-home guard on.
func Env(root string) map[string]string {
	return map[string]string{
		"HOME": root, "CLAUDE_CONFIG_DIR": root + "/.claude", "CODEX_HOME": root + "/.codex",
		"SPACEVIBE_HOME": root + "/" + dataFolder, "SPACEVIBE_TEST": "1",
	}
}

// Materialize returns the shared read-only tree at CanonicalRoot, building it only when it is not already
// right. It follows FixtureHome.materialize in Swift, so a Go and a Swift test run can share the tree: the
// tree is reused while its stamp equals the manifest digest; otherwise it is built in a sibling staging
// folder, the old tree is moved aside and the staging folder is renamed into place. If another process wins
// the rename, its tree is used when it is right.
//
// Stronger than Swift: a matching stamp is not trusted alone. The tree must also hold exactly the files the
// manifest lists with the committed bytes (token replaced by the root path) and mtimes, and no other file
// outside the data folder .reins, where a scan may write. A stale or corrupt tree under a matching stamp is
// rebuilt. The stamp format is unchanged (the manifest digest), so Swift reads Go's tree and the reverse.
func Materialize() (string, error) { return materializeAt(CanonicalRoot) }

// materializeAt is Materialize for any root, so tests can exercise the rebuild on a temporary folder.
func materializeAt(root string) (string, error) {
	materializeLock.Lock()
	defer materializeLock.Unlock()
	fixtures, err := FixturesDir()
	if err != nil {
		return "", err
	}
	manifest, err := loadManifest(fixtures)
	if err != nil {
		return "", err
	}
	files, err := expectedFiles(fixtures, manifest, root)
	if err != nil {
		return "", err
	}
	if treeIsRight(root, manifest, files) {
		return root, nil
	}

	parent := filepath.Dir(root)
	staging, err := os.MkdirTemp(parent, filepath.Base(root)+"-")
	if err != nil {
		return "", errors.New("goldentest: cannot create the staging folder")
	}
	if err := os.Chmod(staging, 0o755); err != nil {
		_ = os.RemoveAll(staging)
		return "", errors.New("goldentest: cannot set the staging folder mode")
	}
	if err := build(staging, manifest, files); err != nil {
		_ = os.RemoveAll(staging)
		return "", err
	}
	aside := ""
	if info, err := os.Lstat(root); err == nil {
		// Only ever moves the canonical fixture folder, and never through a symlink.
		if !info.IsDir() {
			_ = os.RemoveAll(staging)
			return "", errors.New("goldentest: the canonical fixture path is not a folder")
		}
		aside = staging + "-old"
		if err := os.Rename(root, aside); err != nil {
			aside = ""
		}
	}
	if err := os.Rename(staging, root); err != nil {
		_ = os.RemoveAll(staging)
		if !treeIsRight(root, manifest, files) { // another process may have won the race
			return "", errors.New("goldentest: cannot move the fixture tree into place")
		}
	}
	if aside != "" {
		_ = os.RemoveAll(aside)
	}
	return root, nil
}

// MaterializeInto builds a private copy at dest, which must not exist, with the token replaced by dest itself.
// Path-hashed ids in it differ from the goldens, which is fine for tests that write.
func MaterializeInto(dest string) error {
	fixtures, err := FixturesDir()
	if err != nil {
		return err
	}
	manifest, err := loadManifest(fixtures)
	if err != nil {
		return err
	}
	files, err := expectedFiles(fixtures, manifest, dest)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(dest), 0o755); err != nil {
		return errors.New("goldentest: cannot create the parent of the copy")
	}
	if err := os.Mkdir(dest, 0o755); err != nil {
		return errors.New("goldentest: the copy folder exists or cannot be created")
	}
	return build(dest, manifest, files)
}

// expectedFiles reads every file the manifest lists from fixtures/home with the token replaced by root.
func expectedFiles(fixtures string, m Manifest, root string) (map[string][]byte, error) {
	files := make(map[string][]byte, len(m.Mtimes))
	for rel := range m.Mtimes {
		data, err := os.ReadFile(filepath.Join(fixtures, "home", rel))
		if err != nil {
			return nil, errors.New("goldentest: a file listed in the manifest is missing from the committed tree")
		}
		files[rel] = bytes.ReplaceAll(data, []byte(m.Token), []byte(root))
	}
	return files, nil
}

func mtimeOf(ms float64) time.Time { return time.Unix(0, int64(math.Round(ms*1e6))) }

func build(dest string, m Manifest, files map[string][]byte) error {
	rels := make([]string, 0, len(files))
	for rel := range files {
		rels = append(rels, rel)
	}
	sort.Strings(rels)
	for _, rel := range rels {
		target := filepath.Join(dest, rel)
		if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return errors.New("goldentest: cannot create a folder in the fixture tree")
		}
		if err := os.WriteFile(target, files[rel], 0o644); err != nil {
			return errors.New("goldentest: cannot write a file in the fixture tree")
		}
		t := mtimeOf(m.Mtimes[rel])
		if err := os.Chtimes(target, t, t); err != nil {
			return errors.New("goldentest: cannot set a modification time in the fixture tree")
		}
	}
	if err := os.MkdirAll(filepath.Join(dest, dataFolder), 0o755); err != nil {
		return errors.New("goldentest: cannot create the data folder")
	}
	if err := os.WriteFile(filepath.Join(dest, stampName), []byte(m.Digest), 0o644); err != nil {
		return errors.New("goldentest: cannot write the stamp")
	}
	return nil
}

// treeIsRight reports whether root holds exactly the tree Materialize builds, apart from files under the data folder.
func treeIsRight(root string, m Manifest, files map[string][]byte) bool {
	return len(checkTree(root, m, files)) == 0
}

// checkTree lists how the tree at root differs from the one the manifest describes (empty when it is right).
// files maps each manifest path to its expected bytes. Each problem is a fixed sentence plus a relative path
// inside the tree, never file content.
func checkTree(root string, m Manifest, files map[string][]byte) []string {
	var problems []string
	stamp, err := os.ReadFile(filepath.Join(root, stampName))
	if err != nil || string(stamp) != m.Digest {
		return []string{"stamp missing or different from the manifest digest"}
	}
	seen := make(map[string]bool, len(files))
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			problems = append(problems, "cannot read a folder in the tree")
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		if d.IsDir() {
			return nil
		}
		want, listed := files[rel]
		switch {
		case rel == stampName:
		case !listed && (rel == dataFolder || strings.HasPrefix(rel, dataFolder+string(filepath.Separator))):
		case !listed:
			problems = append(problems, "unexpected file: "+rel)
		case !d.Type().IsRegular():
			problems = append(problems, "not a regular file: "+rel)
		default:
			seen[rel] = true
			if got, err := os.ReadFile(path); err != nil || !bytes.Equal(got, want) {
				problems = append(problems, "content differs: "+rel)
			}
			if info, err := d.Info(); err != nil || math.Abs(float64(info.ModTime().UnixNano())/1e6-m.Mtimes[rel]) > mtimeToleranceMS {
				problems = append(problems, "mtime differs: "+rel)
			}
		}
		return nil
	})
	if err != nil {
		problems = append(problems, "cannot walk the tree")
	}
	for rel := range files {
		if !seen[rel] {
			problems = append(problems, "missing file: "+rel)
		}
	}
	if info, err := os.Stat(filepath.Join(root, dataFolder)); err != nil || !info.IsDir() {
		problems = append(problems, "missing data folder: "+dataFolder)
	}
	sort.Strings(problems)
	return problems
}
