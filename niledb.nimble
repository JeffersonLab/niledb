# Package
version       = "1.0.0"
author        = "Robert Edwards"
description   = "Key/Value storage into a fast file-hash"
license       = "MIT"
skipDirs      = @["tests","tmp"]

# Dependencies
requires "nim >= 0.17.0", "serializetools >= 1.5.1"

# Tasks
task test, "Run the test suite":
  exec "cd tests; nim c -r test_niledb"

task docgen, "Regenerate the documentation":
  exec "nim doc2 --out:docs/niledb.html --path:./niledb/private niledb.nim"

# Build the filehash C-lib
before install:
  echo "Building filehash"
  exec "cd filehash; make"
