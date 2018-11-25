# Package
version       = "1.2.0"
author        = "Jie Chen and Robert Edwards"
description   = "Key/Value storage into a fast file-hash"
license       = "MIT"
#skipDirs     = @["tests","tmp"]
installDirs   = @["filehash"]

# Dependencies
requires "nim >= 0.19.0", "serializetools >= 1.12.0"

# Tasks
task test, "Run the test suite":
  exec "cd tests; nim c -r test_niledb"

task docgen, "Regenerate the documentation":
  exec "nim doc2 --out:docs/niledb.html niledb.nim"

# Build the filehash C-lib
before install:
  echo "Building filehash"
  exec "cd filehash; make"
