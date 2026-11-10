package redact

import "testing"

func TestCommandMasksEveryShape(t *testing.T) {
	cases := []struct{ name, in, want string }{
		{"authorization header", `curl -H "Authorization: Bearer abc123" https://x.dev`, `curl -H "Authorization: Bearer ` + Mark + `" https://x.dev`},
		{"authorization basic, lower case", `curl -H 'authorization: basic dXNlcjpwYXNz'`, `curl -H 'authorization: basic ` + Mark + `'`},
		{"authorization without a scheme", `curl -H "Authorization: abc123"`, `curl -H "Authorization: ` + Mark + `"`},
		{"authorization in json", `{"Authorization":"Bearer abc123"}`, `{"Authorization":"Bearer ` + Mark + `"}`},
		{"bare bearer", `echo Bearer abc123xyz`, `echo Bearer ` + Mark},
		{"--token space", `tool --token abc123 run`, `tool --token ` + Mark + ` run`},
		{"--token equals", `tool --token=abc123`, `tool --token=` + Mark},
		{"--password quoted", `tool --password "pa ss" go`, `tool --password ` + Mark + ` go`},
		{"--passwd", `tool --passwd=p`, `tool --passwd=` + Mark},
		{"--secret", `tool --secret s3cr3t`, `tool --secret ` + Mark},
		{"--api-key", `tool --api-key=k1`, `tool --api-key=` + Mark},
		{"--apikey", `tool --apikey k1`, `tool --apikey ` + Mark},
		{"--access-token", `tool --access-token=t1`, `tool --access-token=` + Mark},
		{"--auth", `tool --auth t1`, `tool --auth ` + Mark},
		{"curl -u", `curl -u alice:hunter2 https://x.dev`, `curl -u alice:` + Mark + ` https://x.dev`},
		{"curl --user quoted", `curl --user "alice:hunter2" https://x.dev`, `curl --user "alice:` + Mark + `" https://x.dev`},
		{"curl --user equals", `curl --user=alice:hunter2 -s`, `curl --user=alice:` + Mark + ` -s`},
		{"NAME with TOKEN", `GITHUB_TOKEN=abc123 npm publish`, `GITHUB_TOKEN=` + Mark + ` npm publish`},
		{"NAME with KEY after export", `export API_KEY="abc 123"; run`, `export API_KEY=` + Mark + `; run`},
		{"NAME with SECRET", `AWS_SECRET_ACCESS_KEY=abc run`, `AWS_SECRET_ACCESS_KEY=` + Mark + ` run`},
		{"NAME with PASSWORD", `DB_PASSWORD=pw run`, `DB_PASSWORD=` + Mark + ` run`},
		{"NAME with PASSWD", `DB_PASSWD=pw run`, `DB_PASSWD=` + Mark + ` run`},
		{"NAME with CREDENTIAL", `GOOGLE_CREDENTIALS=x run`, `GOOGLE_CREDENTIALS=` + Mark + ` run`},
		{"NAME with AUTH", `BASIC_AUTH=x run`, `BASIC_AUTH=` + Mark + ` run`},
		{"two names in a row", `A_KEY=1 B_KEY=2 run`, `A_KEY=` + Mark + ` B_KEY=` + Mark + ` run`},
		{"url userinfo", `git clone https://bob:hunter2@github.com/o/r.git`, `git clone https://bob:` + Mark + `@github.com/o/r.git`},
		{"url userinfo with an @ in the password", `git clone https://bob:p@ss@github.com/o/r`, `git clone https://bob:` + Mark + `@github.com/o/r`},
		{"sk- key", `run sk-abcdefghij0123456789`, `run ` + Mark},
		{"sk-ant key", `run sk-ant-api03-abcdefghij0123456789`, `run ` + Mark},
		{"ghp_ token", `run ghp_abcdefghij0123456789ab`, `run ` + Mark},
		{"gho_ token", `run gho_abcdefghij0123456789ab`, `run ` + Mark},
		{"ghs_ token", `run ghs_abcdefghij0123456789ab`, `run ` + Mark},
		{"github_pat_ token", `run github_pat_11ABCDEFG0abcdefghij_klmnop`, `run ` + Mark},
		{"slack token", `run xoxb-1234567890-abcdef`, `run ` + Mark},
		{"slack token p", `run xoxp-1234567890-abcdef`, `run ` + Mark},
		{"aws key id", `run AKIAIOSFODNN7EXAMPLE now`, `run ` + Mark + ` now`},
		{"jwt", `run eyJhbGciOi.eyJzdWIiOjE.SflKxwRJSMeKKF2QT4`, `run ` + Mark},
	}
	for _, c := range cases {
		if got := Command(c.in); got != c.want {
			t.Errorf("%s:\n got  %q\n want %q", c.name, got, c.want)
		}
	}
}

func TestCommandKeepsHarmlessLookAlikes(t *testing.T) {
	for _, in := range []string{
		"npm test",
		`git commit -m "fix auth flow"`,
		"ls -la /tmp",
		"PATH=/usr/bin:$PATH run",
		"author=bob run",
		"monkey=banana",
		"tool --token-file ./t.txt",
		"tool --token $GITHUB_TOKEN",
		"tool --password=$PW",
		"tool --auth --verbose",
		"GITHUB_TOKEN=$TOKEN run",
		"curl -H 'Authorization: Bearer $TOKEN' x",
		"docker run -u 1000:1000 img",
		"curl -s https://x.dev/a?b=c",
		"git clone ssh://git@github.com:22/o/r.git",
		"git clone git@github.com:o/r.git",
		"curl http://localhost:3000/x@y",
		"pip install scikit-learn",
		"echo sk-short ghp_short AKIA123 eyJ.a.b",
		"the bearer of news",
		"cd /work/app-a && npm test",
	} {
		if got := Command(in); got != in {
			t.Errorf("harmless text changed:\n got  %q\n want %q", got, in)
		}
	}
}

func TestCommandIsIdempotentAndHandlesEmpty(t *testing.T) {
	in := `curl -u a:b -H "Authorization: Bearer abc123" --token x A_KEY=1 https://u:p@h ghp_abcdefghij0123456789ab`
	once := Command(in)
	if twice := Command(once); twice != once {
		t.Errorf("not idempotent:\n once  %q\n twice %q", once, twice)
	}
	if Command("") != "" {
		t.Error("empty text changed")
	}
}

func TestUserinfoMasksOnlyThePassword(t *testing.T) {
	for in, want := range map[string]string{
		"http://u:pw@proxy.corp:8080": "http://u:" + Mark + "@proxy.corp:8080",
		"TOKEN=abc":                   "TOKEN=abc",
		"ghp_abcdefghij0123456789ab":  "ghp_abcdefghij0123456789ab",
		"true":                        "true",
	} {
		if got := Userinfo(in); got != want {
			t.Errorf("Userinfo(%q) = %q, want %q", in, got, want)
		}
	}
}
