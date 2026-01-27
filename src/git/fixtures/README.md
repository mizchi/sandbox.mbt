# Fixtures

## hello.pack

Generated via:

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
printf "hello\n" > hello.txt
git add hello.txt
git commit -m "init" -q
OBJ_LIST=$(git rev-list --objects --all)
printf "%s\n" "$OBJ_LIST" | git pack-objects --stdout > /path/to/src/git/fixtures/hello.pack
# Verify
cd /path/to/repo
git index-pack src/git/fixtures/hello.pack
```

## oracle.pack

Non-delta packfile with compression level 0 (stored blocks).

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.name "Test"
git config user.email "test@example.com"
printf "hello\n" > hello.txt
printf "world\n" > world.txt
git add hello.txt world.txt
GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git commit -q -m "initial"
git rev-list --objects --all | cut -d' ' -f1 | \
  git -c core.compression=0 pack-objects --stdout --window=0 --depth=0 --no-reuse-delta --no-reuse-object \
  > /path/to/src/git/fixtures/oracle.pack
# Verify
cd /path/to/repo
git index-pack src/git/fixtures/oracle.pack
```

## oracle_deflate.pack

Non-delta packfile with deflate compression.

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.name "Test"
git config user.email "test@example.com"
printf "hello\n" > hello.txt
printf "world\n" > world.txt
git add hello.txt world.txt
GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git commit -q -m "initial"
git rev-list --objects --all | cut -d' ' -f1 | \
  git -c core.compression=1 pack-objects --stdout --window=0 --depth=0 --no-reuse-delta --no-reuse-object \
  > /path/to/src/git/fixtures/oracle_deflate.pack
# Verify
cd /path/to/repo
git index-pack src/git/fixtures/oracle_deflate.pack
git verify-pack -v src/git/fixtures/oracle_deflate.pack
```

## oracle_delta.pack

Delta packfile with deflate compression.

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.name "Test"
git config user.email "test@example.com"
head -c 2048 /dev/zero | tr '\0' 'a' > big.txt
printf '\n' >> big.txt
head -c 1024 /dev/zero | tr '\0' 'a' > big2.txt
printf 'b' >> big2.txt
head -c 1023 /dev/zero | tr '\0' 'a' >> big2.txt
printf '\n' >> big2.txt
git add big.txt big2.txt
GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git commit -q -m "initial"
git rev-list --objects --all | cut -d' ' -f1 | \
  git -c core.compression=1 pack-objects --stdout --window=10 --depth=10 --no-reuse-object \
  > /path/to/src/git/fixtures/oracle_delta.pack
# Verify
cd /path/to/repo
git index-pack src/git/fixtures/oracle_delta.pack
git verify-pack -v src/git/fixtures/oracle_delta.pack
```

## oracle_thin.pack

Thin packfile (missing base objects). This will not index without the base objects
present in the repository.

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.name "Test"
git config user.email "test@example.com"
head -c 2048 /dev/zero | tr '\0' 'a' > big.txt
printf '\n' >> big.txt
git add big.txt
GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git commit -q -m "c1"
commit1=$(git rev-parse HEAD)
head -c 1024 /dev/zero | tr '\0' 'a' > big.txt
printf 'b' >> big.txt
head -c 1023 /dev/zero | tr '\0' 'a' >> big.txt
printf '\n' >> big.txt
git add big.txt
GIT_AUTHOR_DATE="1700000001 +0000" GIT_COMMITTER_DATE="1700000001 +0000" git commit -q -m "c2"
commit2=$(git rev-parse HEAD)
printf "%s\n^%s\n" "$commit2" "$commit1" | \
  git -c core.compression=1 pack-objects --thin --stdout --window=10 --depth=10 --no-reuse-object --revs \
  > /path/to/src/git/fixtures/oracle_thin.pack

# Verify in a repo that has commit1
git index-pack src/git/fixtures/oracle_thin.pack # expected: unresolved delta
cat src/git/fixtures/oracle_thin.pack | git index-pack --fix-thin --stdin
```

## oracle_thin_base.pack

Base pack for resolving `oracle_thin.pack` (commit c1 only, no deltas).

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.name "Test"
git config user.email "test@example.com"
head -c 2048 /dev/zero | tr '\0' 'a' > big.txt
printf '\n' >> big.txt
git add big.txt
GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git commit -q -m "c1"
git rev-list --objects --all | cut -d' ' -f1 | \
  git -c core.compression=1 pack-objects --stdout --window=0 --depth=0 --no-reuse-delta --no-reuse-object --no-delta-base-offset \
  > /path/to/src/git/fixtures/oracle_thin_base.pack
```

## oracle_after_delta.pack

Ref-delta pack with base object placed after the delta (reordered).

```sh
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"
git init -q
git config user.name "Test"
git config user.email "test@example.com"
head -c 2048 /dev/zero | tr '\0' 'a' > big.txt
printf '\n' >> big.txt
git add big.txt
GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git commit -q -m "c1"
head -c 1024 /dev/zero | tr '\0' 'a' > big.txt
printf 'b' >> big.txt
head -c 1023 /dev/zero | tr '\0' 'a' >> big.txt
printf '\n' >> big.txt
git add big.txt
GIT_AUTHOR_DATE="1700000001 +0000" GIT_COMMITTER_DATE="1700000001 +0000" git commit -q -m "c2"
printf "%s\n" "$(git rev-parse HEAD)" | \
  git -c core.compression=1 pack-objects --stdout --window=10 --depth=10 --no-reuse-object --no-delta-base-offset --revs \
  > /tmp/tmp_refdelta.pack

# Reorder to put delta before base (REF_DELTA is safe to reorder)
cd /path/to/repo
git index-pack /tmp/tmp_refdelta.pack
node -e 'const fs=require("fs"); const crypto=require("crypto"); const {execSync}=require("child_process"); const packPath="/tmp/tmp_refdelta.pack"; const buf=fs.readFileSync(packPath); const trailerOffset=buf.length-20; const out=execSync("git verify-pack -v "+packPath,{encoding:"utf8"}); const lines=out.trim().split("\\n").filter(l=>/^[0-9a-f]{40} /.test(l)); const entries=lines.map(l=>{const parts=l.trim().split(/\\s+/); return {offset: parseInt(parts[4],10), isDelta: parts.length>=7};}).sort((a,b)=>a.offset-b.offset); const offsets=entries.map(e=>e.offset).concat([trailerOffset]); const slices=entries.map((e,i)=>({isDelta:e.isDelta, buf: buf.slice(e.offset, offsets[i+1])})); const reordered=slices.filter(s=>s.isDelta).concat(slices.filter(s=>!s.isDelta)); const header=buf.slice(0,12); const body=Buffer.concat(reordered.map(s=>s.buf)); const content=Buffer.concat([header, body]); const trailer=crypto.createHash("sha1").update(content).digest(); fs.writeFileSync("/path/to/src/git/fixtures/oracle_after_delta.pack", Buffer.concat([content,trailer]));'
```
