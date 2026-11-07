# Writes the corpus for the ICU pattern oracle: python3 -I corpus.py corpus.json
# Then: swiftc -O oracle.swift -o oracle && ./oracle corpus.json icu-oracle.json
# icu-oracle.json (committed) holds what NSRegularExpression answered for each case; icu-patterns_test.go checks the
# Go patterns against it. Regenerate it only when a pattern in ActivityFold.swift or SessionTitles.swift changes.
import json, itertools
W = ["\t","\n","\x0b","\x0c","\r","\x1c","\x1d","\x1e","\x1f"," ","\x85","\xa0","\u1680","\u180e","\u2000","\u2001","\u2005","\u200a","\u200b","\u2028","\u2029","\u202f","\u205f","\u3000","\ufeff","\u2060"]
T = ["\n","\x0b","\x0c","\r","\x85","\u2028","\u2029","\r\n","\n\n","\r\r\n"]
cases=[]
def add(re_, s): cases.append({"re":re_,"input":s})
# explore
for w in W:
    add("explore","git"+w+"status"); add("explore","gh"+w+"pr"+w+"view"); add("explore","gh pr"+w+"list"); add("explore","test"+w+"-f x"); add("explore","gh"+w+"x"+w+"list")
for s in ["cat x","ls","lsof","catalog","grep -r x"," ls","\nls","[ -f x ]","[","test","test -f","git","git status","git  log","git\tdiff","git push","gh pr view","gh pr create","gh  pr  list","gh pr","gh a view","echo hi","file x","stat","diff a b","find .","sed -i x","head","tail -f","wc -l","pwd","which node","du -sh","rg x","git ls-files","git check-ignore x","git rev-parse HEAD","git branch","git show","git grep","git gre","filex","statx","\u0441at x","cat\u00e9","ls\u0301","\ufeffls","ls\n"]:
    add("explore",s)
# errorLine
words=["error","failed","fail","exception","cannot","could not","couldn't","not found","denied","panic","fatal","unexpected","undefined is","is not a function","\u2717","\u00d7","ERROR","Error","FAILED","FaIl","EXCEPTION","Cannot","COULDN'T","UNDEFINED IS","Is Not A Function"]
for w in words:
    add("errorLine",w); add("errorLine","x "+w); add("errorLine",w+" x"); add("errorLine","x"+w+"x")
for s in ["errors","myerror","error:","error_","error1","1error","_error","errorx","failure","failing","failed.","(failed)","e\u0301rror","error\u0301","\u00e9error","error\u00e9","error\u0301x","\u0301error","x\u0301error","error\u200b","error\u200d","\u200derror","error\u200c","error\u0660","\u0660error","error\u2160","\u2160error","error\u00aa","\u00aaerror","error\u02b0","error\u1d2c","error\u3007","error\u2e2f","error\u203f","\u203ferror","error-","error\u00a0","error\u2028","\u2028error","error\ufeff","\ufefferror","error\u00ad","\u00aderror","error\u0600","\u0600error","error\U0001d7ce","error\U0001f600","\U0001f600error","fail\u0301","fai\u017f","denied","DENIE\u1e9e","\u017fndefined is","undefined \u017f","undefined \u0131s","UNDEFINED \u0130S","\u212aerror","not found","NOT FOUND","not\u00a0found","not  found","stra\u00dfe fatal","FATAL","fa\u0131al","ſ","ß","SS","ǅ","ﬃ","ffi error","\u0130","i\u0307","\u03c3","\u03c2","\u03a3","K","\u212a","Å","\u00c5","ǆ"]:
    add("errorLine",s)
for s in ["canno\u212a","coul\u0131d not","could not"+"\u0131","could n\u00f4t","\u1e9ee","ﬀail","ﬁ","fail\u0345","faIl","Faıl","FAİL","fai\u0307l","paniC","PANİC","panı̇c","\ufb01le error","ﬆ","unexpec\ufb05ed","unexpec\u017fed","unexpected","unexpecteD"]:
    add("errorLine",s)
# zeroCount
for s in ["0 failed","0 error","0 errors","0 ERRORS","0 Failed","10 failed","a0 failed","_0 failed","\u06600 failed","0 failed.","0 failedx","0 failed_","0 errorss","0  failed","0\tfailed","0\u00a0failed","x 0 errors y","0 errorS","0 error\u0301","0 failed\u0301","\u0301""0 failed","x\u0301""0 failed","0 failed\u200b","\u200d""0 failed","\u0e010 failed","\u00e90 failed","-0 failed","(0 failed)","0 error","0 failed\u0660","0 failed\U0001f600","\U0001d7ce0 failed","\u2160""0 failed","0 Fai\u017fled"]:
    add("zeroCount",s)
# exitLine / exitCode
digits=["0","1","42","007","\u0660","\u0661\u0662","1\u0662","9"*25,"9"*19,"9223372036854775807","9223372036854775808","\uff11","\u0e51","\u09e7","\U0001d7d9","\u00b2","\u2460","\u00bd"]
for d in digits:
    for suf in ["","\n","\r\n","\r","\x85","\u2028","\u2029","\x0b","\x0c","\n\n","\r\n\r\n"," ","x","\r\r\n","\n\r","\u0301"]:
        add("exitLine","Exit code "+d+suf); add("exitCode","Exit code "+d+suf)
for s in ["Exit code","Exit code ","Exit code  1","exit code 1","Exit Code 1","\nExit code 1"," Exit code 1","Exit code 1\nrest","Exit code 2\nError: x","\ufeffExit code 1","Exit\u00a0code 1","Exit code\t1","xExit code 1"]:
    add("exitLine",s); add("exitCode",s)
# stripCd
for w in W:
    add("stripCd","cd"+w+"/x && npm test"); add("stripCd","cd /x"+w+"&& npm test"); add("stripCd","cd /x &&"+w+"npm test"); add("stripCd","cd /x ;"+w+"npm"); add("stripCd","cd"+w+"/x"+w+";"+w+"rest")
for s in ["cd /x && npm test","cd /x;npm","cd /x ; npm","cd /x&&npm","cd  /x  &&  npm test","cd x","cd /x","cd","cd ","cd && x","cd ; x","cd /a/b/c && cd /d && x","cd /x &&","cd /x && ","cd /x;","cd /x ;;x","cd /x & x","cd \"a b\" && x","cd 'a b' && x","cdx && y","CD /x && y"," cd /x && y","cd /x\n&& y","cd /x &&\ny","cd /x;y;z","cd ~;ls","cd /x&&&y","cd /x&&&&y","cd -- /x && y","cd /x || y","cd /x|y","cd /\u00e9 && y","cd /x \u00a0&& y","cd\u00a0/x && y","cd /x&&y&&z","cd a;b&&c","cd a&&b;c"]:
    add("stripCd",s)
# patchFile
for s in ["*** Update File: src/old.ts\n@@","*** Add File: /abs/new.ts\n*** End Patch","*** Delete File: a b.ts","*** Update File: a\\b","*** Update File: a\"b","*** Update File: a\r\nb","*** Update File: \n","*** Update File: ","*** Update File: x","***  Update File: x","*** Move File: x","*** update File: x","*** Update File: a\u2028b","*** Update File: a\x85b","*** Update File: \u00e9\U0001f600","*** Begin Patch\n*** Update File: a\n*** Add File: b\n*** Delete File: c\n*** End Patch","x*** Update File: a***Update File: b","*** Update File: a *** Add File: b","*** Update File:  lead","*** Update File: trail  \n","*** Update File: a\tb\n"]:
    add("patchFile",s)
# worktrees
paths=["/p/.claude/worktrees/fox","/p/.claude/worktrees/fox/src","/p/.claude/worktrees/fox/","/p/.claude/worktrees/","/p/.claude/worktrees","/.claude/worktrees/x","/a/b/.claude/worktrees/x/y/z","C:\\p\\.claude\\worktrees\\fox\\src","C:/p\\.claude/worktrees\\fox","/p/.claude/worktrees/fox\n","/p/.claude/worktrees/fox\r\n","/p/.claude/worktrees/fox\n\n","/p/.claude/worktrees/fox/a\n","/p/.claude/worktrees/fox\x85","/p/.claude/worktrees/fox\u2028","/p/.claude/worktrees/fox\r","/p/.claude/worktrees/fox\x0b","/p/.claude/worktrees/fox\x0c","/a\nb/.claude/worktrees/fox","/a\rb/.claude/worktrees/fox","/a\x85b/.claude/worktrees/fox","/a\u2028b/.claude/worktrees/fox","/a\x0bb/.claude/worktrees/fox","/a\x0cb/.claude/worktrees/fox","/a\u2029b/.claude/worktrees/fox","x\n/p/.claude/worktrees/fox","/p/.claude/worktrees/fox/a\nb","/p/.claude/worktrees/fox/a\x85b","/p/.claude/worktrees/fox/a\r\nb","/p/.claude/worktrees/f\no/x","/p/.claude/worktrees/\n","/p/.claude/worktrees/\n/x","/p/.claude/worktrees/fox\n\r","/p/.claude/worktrees/fox\r\r","/p/.claude/worktrees/fox\u0301","/p/.claude/Worktrees/fox","/p/.claude/worktrees/fox/.claude/worktrees/bar","/p/.claude/worktrees/a/.claude/worktrees/b/c","//.claude/worktrees/x","/p//.claude/worktrees/x","/p/.claudeX/worktrees/x","/p/x.claude/worktrees/x",
 "/h/.codex/worktrees/a1b2/my-repo","/h/.codex/worktrees/a1b2/my-repo/src","/h/.codex/worktrees/a1b2/","/h/.codex/worktrees/a1b2","/h/.codex/worktrees//x","/h/.codex/worktrees/a/b/c","/h/.codex/worktrees/a/b\n","/h/.codex/worktrees/a/b\r\n","/h/.codex/worktrees/a/b\x85","/h/.codex/worktrees/a/b/c\nd","/h/.codex/worktrees/a/b/c\x85d","/h/.codex/worktrees/a/b\n\n","/h/.codex/worktrees/a/b\nc","/h/.codex/worktrees/a/\nb","x\n/h/.codex/worktrees/a/b","C:\\h\\.codex\\worktrees\\a\\b\\c","/h/.codex/worktrees/a/b/c/.codex/worktrees/d/e","/.codex/worktrees/a/b","/h/.codex/worktrees/a/b\u2028","/h/.codex/worktrees/a/b\x0b","/h/.codex/worktrees/a/b\x0c",
 "/m/.git/worktrees/wt1","/m/.git/worktrees/wt1\n","/m/.git/worktrees/wt1\r\n","/m/.git/worktrees/wt1\x85","/m/.git/worktrees/wt1\u2028","/m/.git/worktrees/wt1/","/m/.git/worktrees/wt1/x","/m/.git/worktrees/","/.git/worktrees/x","C:\\m\\.git\\worktrees\\wt1","/a\nb/.git/worktrees/wt1","/a\x85b/.git/worktrees/wt1","/m/.git/worktrees/w\nt","x\n/m/.git/worktrees/wt1","/m/.git/worktrees/wt1\n\n","/m/.git/worktrees/wt1\r","/m/.git/worktrees/wt1\x0b","/m/.git/worktrees/wt1\x0c","/m/.git/worktrees/wt1\r\r\n","/m/.git/worktrees/wt1\u2029"]
for p in paths:
    for n in ["wtClaude","wtCodex","gitdirWt"]: add(n,p)
# gitdirLine
gl=["gitdir: /m/.git/worktrees/wt1\n","gitdir: /x","gitdir:/x","gitdir:   /x   ","gitdir:\n/x","gitdir:\n","gitdir: \n","gitdir:  \n","gitdir:\n\n/x","gitdir:","gitdir: ","gitdir:\r\n/x","gitdir:\r/x","gitdir:\x85/x","gitdir:\u2028/x","gitdir:\x0b/x","gitdir:\x0c/x","gitdir:\u00a0/x","gitdir:\u3000/x","gitdir:\ufeff/x","\ngitdir: /x","a\ngitdir: /x\nb","a\rgitdir: /x","a\r\ngitdir: /x\r\n","a\x85gitdir: /x","a\u2028gitdir: /x","a\u2029gitdir: /x","a\x0bgitdir: /x","a\x0cgitdir: /x","x gitdir: /x","Gitdir: /x"," gitdir: /x","gitdir: /x\ngitdir: /y","gitdir: a\rb","gitdir: a\x85b","gitdir: a\u2028b","gitdir: a\x0bb","gitdir: a\x0cb","gitdir: a\u2029b","gitdir: a\r\nb","gitdir: a\tb","gitdir: \u00e9\U0001f600","gitdir:\t/x","gitdir:\x1c/x","gitdir:\u180e/x","gitdir:\u200b/x","\r\ngitdir: /x","\n\rgitdir: /x","\rgitdir: /x","x\r\n\ngitdir:  \n  \n/y","gitdir:  \r\n","gitdir:  \r","gitdir: \r\n/x","gitdir:\r\n","gitdir:\n   \n","gitdir:a","gitdir:\n x","gitdir:   \n   y \n"]
for s in gl: add("gitdirLine",s)
# split
for s in ["a\nb","a\r\nb","a\r\n\r\nb","a\n\nb","a\r\r\nb","a\n\rb","a\rb","\n","\r\n","","a\r\n","\r\nA","a\u0301\nb","a\n\u0301b","a\r\n\u0301b","a\nb\r\nc\nd"]:
    add("split",s)

# Full case folding: U+FB01 reads as "fi" inside "undefined is"; other expansions (ss, ff, fl, st) occur in no pattern.
for s in ["unde\ufb01ned is","UNDE\ufb01NED IS","undefined \ufb01s","not \ufb01ound","not fo\u00dfnd","fa\ufb01led","unexpected \ufb02","exception\ufb03","unde\ufb01ned\u00a0is","nOt FoUnD","COULDN\u2019T","couldn\u2019t","couldn't","COULDN'T","could\u00a0not","uNdEfInEd Is","\u212a\u212a","fatal\u0301","FATA\u2113","denied\u200b","\ufb06","pani\u0063\u0301","ERROR\u200d","fail\u200c"]:
    add("errorLine",s)
for s in ["0 \ufb01ailed","0 failed","0 ERROR\u017f","0 error\u017f","0 error\u017f","0 ERRORS\u0301","0 errors\u200d","0 e\u0301rrors"]:
    add("zeroCount",s)

import sys
json.dump(cases,open(sys.argv[1],"w"),ensure_ascii=True)
print(len(cases), "cases")
