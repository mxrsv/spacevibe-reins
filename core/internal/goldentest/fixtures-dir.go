package goldentest

import (
	"errors"
	"os"
	"path/filepath"
)

// FixturesDir is core/testdata/fixtures, found by walking up from the working directory to the folder with
// go.mod, so a test in any package gets the same answer.
func FixturesDir() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", errors.New("goldentest: cannot read the working directory")
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			fixtures := filepath.Join(dir, "testdata", "fixtures")
			if _, err := os.Stat(filepath.Join(fixtures, "manifest.json")); err != nil {
				return "", errors.New("goldentest: testdata/fixtures/manifest.json is missing next to go.mod")
			}
			return fixtures, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("goldentest: no go.mod above the working directory")
		}
		dir = parent
	}
}

// LoadGolden reads golden/<name>.json from the fixtures as a generic JSON tree. Numbers stay json.Number, so
// their text survives until Canonical prints them. The golden still holds $HOME, not the fixture root.
func LoadGolden(name string) (any, error) {
	dir, err := FixturesDir()
	if err != nil {
		return nil, err
	}
	data, err := os.ReadFile(filepath.Join(dir, "golden", name+".json"))
	if err != nil {
		return nil, errors.New("goldentest: cannot read the golden file")
	}
	return decodeJSON(data)
}
