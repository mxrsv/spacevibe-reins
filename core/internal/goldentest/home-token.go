package goldentest

import (
	"encoding/json"
	"reflect"
	"strings"
)

// Token is the placeholder the frozen goldens and the committed home tree use for the fixture root.
const Token = "$HOME"

// HomeToken is the home-token projection: it returns a copy of the JSON tree v with every occurrence of root
// replaced by Token, in object keys and in string values. v is not changed. Slices and string-keyed maps of
// other element types come back as []any and map[string]any; a value that is not a container or a string
// (a json.Number, a bool, a number, nil) is returned as it is, so a number never turns into a string. If two keys become equal after the replacement, one of them is dropped, so a caller
// that can produce such keys must avoid them.
func HomeToken(v any, root string) any {
	switch x := v.(type) {
	case string:
		return HomeTokenString(x, root)
	case json.Number:
		return x // its kind is string, but it is a number leaf: keep the type
	case []any:
		out := make([]any, len(x))
		for i, item := range x {
			out[i] = HomeToken(item, root)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(x))
		for k, item := range x {
			out[HomeTokenString(k, root)] = HomeToken(item, root)
		}
		return out
	}
	rv := reflect.ValueOf(v)
	switch rv.Kind() {
	case reflect.Slice, reflect.Array:
		out := make([]any, rv.Len())
		for i := range out {
			out[i] = HomeToken(rv.Index(i).Interface(), root)
		}
		return out
	case reflect.Map:
		if rv.Type().Key().Kind() == reflect.String {
			out := make(map[string]any, rv.Len())
			for it := rv.MapRange(); it.Next(); {
				out[HomeTokenString(it.Key().String(), root)] = HomeToken(it.Value().Interface(), root)
			}
			return out
		}
	case reflect.String:
		return HomeTokenString(rv.String(), root)
	}
	return v
}

// HomeTokenString replaces root with Token in s. An empty root changes nothing.
func HomeTokenString(s, root string) string {
	if root == "" {
		return s
	}
	return strings.ReplaceAll(s, root, Token)
}
