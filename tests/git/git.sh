#!/bin/sh
# git.sh - Phase 10 gate, run in the guest by test-git.sh: git built by the
# ports (ports/git.sh) on local repositories and over https.
#   local    init, add, commit, branch, merge (with a conflict), rebase,
#            stash, tag, diff, grep, local clone, repack/gc, fsck, archive
#   network  (unless NONET=1) DHCP on em0, curl https with certificate
#            checks (good and expired), git ls-remote / shallow clone / full
#            clone / fetch over https, tag hash against the value
#            the host saw (/mnt/expect-tag)
# Prints GIT-OK.
unset LD_LIBRARY_PATH
PATH=/usr/pkg/bin:$PATH; export PATH
export HOME=/usr/tmp/githome PAGER=cat GIT_PAGER=cat
W=/usr/tmp/gitwork
REMOTE=${REMOTE:-https://github.com/madler/zlib.git}
TAG=${TAG:-v1.3.1}
rm -rf $HOME $W; mkdir -p $HOME $W
fails=0
ok() { echo "GIT: ok   $1"; }
bad() { echo "GIT: FAIL $1"; fails=$((fails+1)); }
t() {	# t <name> <command...>: passes when the command succeeds
	n=$1; shift
	if "$@" > /tmp/git-t.out 2>&1; then ok "$n"
	else bad "$n"; sed 's/^/    /' /tmp/git-t.out | tail -15; fi
}
is() { if [ "$2" = "$3" ]; then ok "$1: $2"; else bad "$1: got '$2', want '$3'"; fi; }

git --version || { echo "GIT: git does not run"; exit 1; }
git config --global user.name "MINIX Tester"
git config --global user.email tester@minix.invalid
git config --global init.defaultBranch main
git config --global advice.detachedHead false

echo "== local"
cd $W; t "init" git init a; cd a
i=0; while [ $i -lt 200 ]; do echo "line $i of the file"; i=$((i+1)); done > big.txt
mkdir -p src/deep; echo 'int main(void) { return 0; }' > src/main.c
echo hello > README; echo x > src/deep/x.txt
t "add" git add .
t "commit" git commit -m "first commit"
is "status clean" "$(git status --porcelain | wc -l | tr -d ' ')" 0
is "ls-files" "$(git ls-files | wc -l | tr -d ' ')" 4
echo world >> README; t "commit -a" git commit -am "second"
is "log count" "$(git rev-list --count HEAD)" 2
is "diff stat" "$(git diff --shortstat HEAD~1 HEAD | tr -s ' ')" " 1 file changed, 1 insertion(+)"
t "branch" git checkout -b topic
echo topic > topic.txt; sed -i.bak 's/line 5 of/line five of/' big.txt; rm big.txt.bak
git add .; t "commit on topic" git commit -m "topic work"
t "checkout main" git checkout main
sed -i.bak 's/line 150 of/line 1-5-0 of/' big.txt; rm big.txt.bak
t "commit on main" git commit -am "main work"
t "merge (3-way, clean)" git merge --no-edit topic
is "merge result" "$(grep -c -e 'line five' -e 'line 1-5-0' big.txt)" 2
is "merge parents" "$(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" 3
# conflict
git checkout -q -b c1; echo one > c.txt; git add c.txt; git commit -q -m c1
git checkout -q main; echo two > c.txt; git add c.txt; git commit -q -m c2
if git merge c1 > /tmp/git-t.out 2>&1; then bad "conflict detected"; else ok "conflict detected"; fi
is "conflict markers" "$(grep -cE '^(<<<<<<<|>>>>>>>)' c.txt)" 2
t "merge --abort" git merge --abort
# rebase
git checkout -q -b r1 HEAD~1; echo r > r.txt; git add r.txt; git commit -q -m r1
t "rebase" git rebase main
is "rebase linear" "$(git rev-list --count main..r1)" 1
git checkout -q main
# stash, tag, grep, show
echo dirty >> README; t "stash" git stash
is "stash cleaned" "$(git status --porcelain | wc -l | tr -d ' ')" 0
t "stash pop" git stash pop; git checkout -q README
t "tag -a" git tag -a v1 -m "version 1"
is "describe" "$(git describe)" v1
is "grep" "$(git grep -c 'line five' -- big.txt)" "big.txt:1"
t "show" git show --stat HEAD
t "blame" git blame -L 1,3 big.txt
t "archive" sh -c 'git archive --format=tar HEAD | tar tf - | grep -q src/main.c'
# clone, push to a bare repository, fetch
cd $W; t "clone --bare" git clone --bare a b.git
t "clone (local)" git clone b.git c
cd c; echo pushed > p.txt; git add p.txt; git commit -q -m pushed
t "push" git push origin main
is "push arrived" "$(git -C ../b.git rev-parse main)" "$(git rev-parse HEAD)"
cd ../a; t "fetch" git fetch ../b.git main
t "merge --ff-only" git merge --ff-only FETCH_HEAD
t "repack" git repack -a -d
t "gc" git gc --quiet
is "no loose objects" "$(git count-objects | awk '{print $1}')" 0
t "fsck" git fsck --full --strict
is "count" "$(git rev-list --all --count)" 9

if [ "${NONET:-0}" != 1 ]; then
echo "== network"
dhcpcd -qM -4 -w em0 || bad "dhcp"
t "curl https" curl -sSf -o /tmp/index.html https://example.com/
if curl -sS -o /dev/null https://expired.badssl.com/ 2> /tmp/git-t.out; then
	bad "expired certificate refused"
elif grep -q 'certificate has expired' /tmp/git-t.out; then
	ok "expired certificate refused"
else	bad "expired certificate refused for another reason"; cat /tmp/git-t.out
fi
cd $W
want=$(cat /mnt/expect-tag 2>/dev/null)
got=$(git ls-remote $REMOTE "refs/tags/$TAG^{}" | awk '{print $1}')
is "ls-remote $TAG" "$got" "$want"
t "clone --depth 1" git clone --depth 1 --branch $TAG $REMOTE shallow
is "shallow depth" "$(git -C shallow rev-list --count HEAD)" 1
is "shallow HEAD" "$(git -C shallow rev-parse HEAD)" "$want"
s=$(date +%s)
t "clone (full)" git clone --quiet $REMOTE full
echo "GIT: full clone took $(($(date +%s) - s)) s," \
    "$(git -C full rev-list --all --count) commits," \
    "$(du -sk full/.git | awk '{print $1}') KB"
is "tag in the full clone" "$(git -C full rev-parse "$TAG^{commit}")" "$want"
t "fsck (full clone)" git -C full fsck --full
t "checkout tag" git -C full checkout -q $TAG
is "same tree as the shallow clone" "$(git -C full rev-parse 'HEAD^{tree}')" \
    "$(git -C shallow rev-parse 'HEAD^{tree}')"
t "log" sh -c "git -C full log --oneline -5 | grep -q ."
t "fetch --unshallow" git -C shallow fetch --quiet --unshallow
is "unshallowed" "$(git -C shallow rev-list --count HEAD)" \
    "$(git -C full rev-list --count HEAD)"
fi

df -k /usr | tail -1
echo "GIT: fails=$fails"
[ $fails = 0 ] && echo GIT-OK
