# Package
version       = "1.0.0"
author        = "Robert Edwards"
description   = "Key/Value storage into a fast file-hash"
license       = "MIT"
srcDir        = "src"
skipDirs      = @["tmp"]

# Dependencies
requires "nim >= 0.17.0"

# Builds
task test, "Run the test suite":
  exec "nim c -r tests/test_niledb"

task docgen, "Regenerate the documentation":
  exec "nim doc2 --out:docs/niledb.html src/niledb.nim"


