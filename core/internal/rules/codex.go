package rules

import (
	"encoding/json"
	"math"
	"slices"
	"strconv"

	"spacevibe.dev/core/internal/fsx"
	"spacevibe.dev/core/internal/roots"
	"spacevibe.dev/core/internal/textjs"
	"spacevibe.dev/core/internal/toml"
)

// How Codex's permissions are configured, read-only (RulesCodexPermissions.swift). Only the keys named here are read;
// nothing under [mcp_servers.*], [shell_environment_policy] or any env table is looked at, and no auth file is opened.

// PermissionModel says which of Codex's two permission models config.toml uses. They must not be mixed: the legacy
// sandbox_mode plus [sandbox_workspace_write], or default_permissions with [permissions.<name>] profiles.
type PermissionModel string

// The permission models.
const (
	ModelLegacy   PermissionModel = "legacy"
	ModelProfiles PermissionModel = "profiles"
	ModelBoth     PermissionModel = "both"
)

// Flag is one scalar key: a boolean, a string or a number (json.Number).
type Flag struct {
	Key   string `json:"key"`
	Value any    `json:"value"`
}

// ApprovalPolicy is either a mode ("on-request", "never", ...) or the granular switches of
// [approval_policy.granular], of which only booleans are kept.
type ApprovalPolicy struct {
	Mode       string
	Granular   []Flag
	IsGranular bool
}

// MarshalJSON writes {"mode": ...} or {"granular": [...]}.
func (p ApprovalPolicy) MarshalJSON() ([]byte, error) {
	if p.IsGranular {
		granular := p.Granular
		if granular == nil {
			granular = []Flag{}
		}
		return json.Marshal(struct {
			Granular []Flag `json:"granular"`
		}{granular})
	}
	return json.Marshal(struct {
		Mode string `json:"mode"`
	}{p.Mode})
}

// WorkspaceWrite is [sandbox_workspace_write].
type WorkspaceWrite struct {
	NetworkAccess *bool    `json:"networkAccess"`
	WritableRoots []string `json:"writableRoots"`
}

// Profile is a [permissions.<name>] profile, counts only: no path, no glob and no value is returned.
type Profile struct {
	Name              string `json:"name"`
	FilesystemEntries int    `json:"filesystemEntries"`
	NetworkEntries    int    `json:"networkEntries"`
	// NetworkFlags are the scalar keys of [permissions.<name>.network], such as enabled = true, in file order.
	NetworkFlags []Flag `json:"networkFlags"`
}

// CodexProject is a project with a trust level.
type CodexProject struct {
	Path       string  `json:"path"`
	TrustLevel *string `json:"trustLevel"`
}

// RulesSummary counts prefix_rule(...) per decision across ~/.codex/rules/*.rules. The patterns themselves are never
// returned.
type RulesSummary struct {
	Files     int `json:"files"`
	Allow     int `json:"allow"`
	Prompt    int `json:"prompt"`
	Forbidden int `json:"forbidden"`
	Other     int `json:"other"`
	// Unreadable counts .rules files that exist but could not be read, so their rules are not in the counts (G-fix.18).
	Unreadable int `json:"unreadable"`
	// FolderNotReadable is true when the rules folder could not be listed (G-fix.18).
	FolderNotReadable bool `json:"folderNotReadable"`
}

// CodexPermissions are the permission keys of Codex config.toml.
type CodexPermissions struct {
	// Present is false when there is no config.toml.
	Present      bool            `json:"present"`
	Model        PermissionModel `json:"model"`
	Unrestricted bool            `json:"unrestricted"`
	Warnings     []string        `json:"warnings"`
	// ApprovalPolicy is null when none is set.
	ApprovalPolicy        *ApprovalPolicy `json:"approvalPolicy"`
	SandboxMode           *string         `json:"sandboxMode"`
	SandboxWorkspaceWrite *WorkspaceWrite `json:"sandboxWorkspaceWrite"`
	DefaultPermissions    *string         `json:"defaultPermissions"`
	ApprovalsReviewer     *string         `json:"approvalsReviewer"`
	Profiles              []Profile       `json:"profiles"`
	Projects              []CodexProject  `json:"projects"`
	Rules                 RulesSummary    `json:"rules"`

	// NotReadable is true when config.toml may exist but cannot be read, so every setting above is unknown, not the
	// defaults (G-fix.18). Outside the golden projection.
	NotReadable bool `json:"notReadable"`
	// SkippedLines counts config.toml lines the reader could not make sense of (G-fix.18). Outside the golden projection.
	SkippedLines int `json:"skippedLines"`
}

// ReadCodexPermissions reads the Codex permission keys. Same fields as readCodexPermissions in Node rules
// (git b58269d), minus the file path.
func ReadCodexPermissions(r roots.Roots) CodexPermissions {
	out := CodexPermissions{Warnings: []string{}, Profiles: []Profile{}, Projects: []CodexProject{}}
	out.Rules = summarizeRules(join(r.Codex.Root, "rules"))
	config := join(r.Codex.Root, "config.toml")
	switch fsx.PathPresence(config) {
	case fsx.Present:
		out.Present = true
		data, err := readCapped(config, maxJSONBytes)
		if err != nil {
			out.NotReadable = true
			break
		}
		doc := toml.Read(textjs.Repair(string(data)))
		out.SkippedLines = doc.SkippedLines
		out.fill(doc)
	case fsx.Unknown:
		out.NotReadable = true
	}
	hasProfiles := out.DefaultPermissions != nil
	hasLegacy := out.SandboxMode != nil
	switch {
	case hasProfiles && hasLegacy:
		out.Model = ModelBoth
	case hasProfiles:
		out.Model = ModelProfiles
	default:
		out.Model = ModelLegacy
	}
	if out.Model == ModelBoth {
		out.Warnings = append(out.Warnings, "Both default_permissions and sandbox_mode are set. Codex expects only one of them.")
	}
	out.Unrestricted = out.SandboxMode != nil && *out.SandboxMode == "danger-full-access"
	out.Warnings = append(out.Warnings, out.unknownWarnings()...)
	return out
}

// unknownWarnings say what could not be read, so the values above are not mistaken for the defaults (G-fix.18). Fixed
// sentences with counts only.
func (c CodexPermissions) unknownWarnings() []string {
	var out []string
	if c.NotReadable {
		out = append(out, "Codex config.toml could not be read, so the settings below are not known.")
	}
	if c.SkippedLines > 0 {
		out = append(out, strconv.Itoa(c.SkippedLines)+" "+plural(c.SkippedLines, "line", "lines")+" of Codex config.toml could not be understood and "+
			plural(c.SkippedLines, "was", "were")+" skipped, so some settings may be missing.")
	}
	if c.Rules.FolderNotReadable {
		out = append(out, "The Codex rules folder could not be read, so its rules are not counted.")
	}
	if n := c.Rules.Unreadable; n > 0 {
		out = append(out, strconv.Itoa(n)+" Codex .rules "+plural(n, "file", "files")+" could not be read and "+plural(n, "is", "are")+" not counted.")
	}
	return out
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

type profileData struct {
	fs, net int
	flags   []Flag
}

func (c *CodexPermissions) fill(doc toml.Document) {
	var profileOrder []string
	profiles := map[string]*profileData{}
	var projectOrder []string
	projectTrust := map[string]*string{}
	var workspaceNetwork, workspaceRoots *toml.Value
	workspaceSeen := false
	var granular []Flag
	var inline *ApprovalPolicy

	setProject := func(path string, trust *string) {
		if _, seen := projectTrust[path]; !seen {
			projectOrder = append(projectOrder, path)
		}
		projectTrust[path] = trust
	}

	// Entries under [[array]] tables are ignored, as in the Node reader.
	for _, entry := range doc.Entries {
		if entry.InArrayTable {
			continue
		}
		table := entry.Table
		key := entry.Key()
		switch {
		case len(table) == 0 && slices.Contains([]string{"approval_policy", "sandbox_mode", "default_permissions", "approvals_reviewer"}, key):
			switch key {
			case "approval_policy":
				if text, ok := stringOf(entry.Value); ok {
					inline = &ApprovalPolicy{Mode: text}
				} else if pairs, ok := tableOf(entry.Value, "granular"); ok {
					inline = &ApprovalPolicy{IsGranular: true, Granular: booleans(pairs)}
				} else {
					inline = nil
				}
			case "sandbox_mode":
				c.SandboxMode = optString(entry.Value)
			case "default_permissions":
				c.DefaultPermissions = optString(entry.Value)
			default:
				c.ApprovalsReviewer = optString(entry.Value)
			}
		case len(table) == 0 && key == "sandbox_workspace_write":
			if entry.Value != nil {
				if pairs, ok := entry.Value.AsTable(); ok {
					for _, pair := range pairs {
						workspaceSeen = true
						value := pair.Value
						if pair.Key == "network_access" {
							workspaceNetwork = &value
						}
						if pair.Key == "writable_roots" {
							workspaceRoots = &value
						}
					}
				}
			}
		case slices.Equal(table, []string{"sandbox_workspace_write"}) && (key == "network_access" || key == "writable_roots"):
			workspaceSeen = true
			if key == "network_access" {
				workspaceNetwork = entry.Value
			} else {
				workspaceRoots = entry.Value
			}
		case slices.Equal(table, []string{"approval_policy", "granular"}):
			if entry.Value != nil {
				if flag, ok := entry.Value.AsBool(); ok {
					granular = slices.DeleteFunc(granular, func(f Flag) bool { return f.Key == key })
					granular = append(granular, Flag{Key: key, Value: flag})
				}
			}
		case len(table) >= 2 && table[0] == "permissions":
			name := table[1]
			data := profiles[name]
			if data == nil {
				data = &profileData{}
				profiles[name] = data
				profileOrder = append(profileOrder, name)
			}
			if len(table) > 2 && table[2] == "filesystem" {
				data.fs++
			} else if len(table) > 2 && table[2] == "network" {
				data.net++
				if flag, ok := scalar(entry.Value); ok && isFlagKey(key) {
					data.flags = slices.DeleteFunc(data.flags, func(f Flag) bool { return f.Key == key })
					data.flags = append(data.flags, Flag{Key: key, Value: flag})
				}
			}
		case len(table) == 2 && table[0] == "projects" && key == "trust_level":
			setProject(table[1], optString(entry.Value))
		case slices.Equal(table, []string{"projects"}) && len(entry.KeyPath) == 1:
			if trust, ok := trustOf(entry.Value); ok {
				setProject(key, &trust)
			}
		}
	}

	// [approval_policy.granular] replaces an unset or inline-table policy, never a plain string such as "never".
	if len(granular) > 0 && (inline == nil || inline.IsGranular) {
		inline = &ApprovalPolicy{IsGranular: true, Granular: granular}
	}
	c.ApprovalPolicy = inline
	for _, name := range profileOrder {
		data := profiles[name]
		flags := data.flags
		if flags == nil {
			flags = []Flag{}
		}
		c.Profiles = append(c.Profiles, Profile{Name: name, FilesystemEntries: data.fs, NetworkEntries: data.net, NetworkFlags: flags})
	}
	for _, path := range projectOrder {
		c.Projects = append(c.Projects, CodexProject{Path: path, TrustLevel: projectTrust[path]})
	}
	if workspaceSeen {
		write := &WorkspaceWrite{WritableRoots: []string{}}
		if workspaceNetwork != nil {
			if b, ok := workspaceNetwork.AsBool(); ok {
				write.NetworkAccess = &b
			}
		}
		if workspaceRoots != nil {
			write.WritableRoots = workspaceRoots.Strings()
		}
		c.SandboxWorkspaceWrite = write
	}
}

func stringOf(v *toml.Value) (string, bool) {
	if v == nil {
		return "", false
	}
	return v.AsString()
}

func optString(v *toml.Value) *string {
	if s, ok := stringOf(v); ok {
		return &s
	}
	return nil
}

// tableOf is the inline table under key of an inline-table value.
func tableOf(v *toml.Value, key string) ([]toml.Pair, bool) {
	if v == nil {
		return nil, false
	}
	inner, ok := v.Get(key)
	if !ok {
		return nil, false
	}
	return inner.AsTable()
}

// trustOf is the trust_level string of an inline table.
func trustOf(v *toml.Value) (string, bool) {
	if v == nil {
		return "", false
	}
	inner, ok := v.Get("trust_level")
	if !ok {
		return "", false
	}
	return inner.AsString()
}

func booleans(pairs []toml.Pair) []Flag {
	var out []Flag
	for _, pair := range pairs {
		if b, ok := pair.Value.AsBool(); ok {
			out = append(out, Flag{Key: pair.Key, Value: b})
		}
	}
	return out
}

// isFlagKey: a non-empty key of ASCII letters, digits, "_" and "-".
func isFlagKey(key string) bool {
	if key == "" {
		return false
	}
	for _, r := range key {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_', r == '-':
		default:
			return false
		}
	}
	return true
}

// scalar is a boolean, string or number value; false for anything else.
func scalar(v *toml.Value) (any, bool) {
	if v == nil {
		return nil, false
	}
	switch v.Kind {
	case toml.KindBool:
		return v.Bool, true
	case toml.KindString, toml.KindRaw:
		return v.Str, true
	case toml.KindInteger:
		return json.Number(strconv.FormatInt(v.Int, 10)), true
	case toml.KindFloat:
		if math.IsInf(v.Float, 0) || math.IsNaN(v.Float) {
			return strconv.FormatFloat(v.Float, 'g', -1, 64), true
		}
		return json.Number(strconv.FormatFloat(v.Float, 'g', -1, 64)), true
	}
	return nil, false
}
