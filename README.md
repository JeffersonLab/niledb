# Niledb [![Build Status](https://travis-ci.org/JeffersonLab/niledb.svg?branch=master)](https://travis-ci.org/JeffersonLab/niledb)

A fast file-hash DB. The interface is Key/Value pair
semantics. Storage of these pairs is into strings, and uses an
underlying `filehash` package implemented over a Berkeley Sleepy Cat
file-hash database. A single integer index is provided to allow the
grouping of the values from many DB's but with a single key.

The `filehash` DB provides page-level checksums and supports caching
of pages for fast retrievals and storage. Multi-threading reading is
supported. The DB scales well, an in production, has been used to hold
up to 80GB single files with O(100K) keys.

The [serializetools](https://github.com/JeffersonLab/serializetools) module provides 
tools for serialization and deserialization of keys and values to/from strings.

## Example

```nimrod
import niledb, serializetools/serializebin
import posix  ## used for file-modes

MyObj_t = object
  more: int                                    ## Example of nesting

MyKey_t = object
  fred:     int                                ## Simple types
  george:   tuple[here: string, there: char]   ## More complicated types
  stuff:    seq[MyObj_t]                       ## Supports nested objects

MyVal_t = object
  vals:  array[0..3, MyObj_t]                  ## Nested types are also allowed

# The DB
var db: ConfDataStoreDB = newConfDataStoreDB()

# Open an existing DB using posix file modes
var ret = db.open("some_file", O_RDONLY, 0o400)

# Grab all the keys and deserialize them
let des_keys: seq[MyKey_t] = allKeys[MyKey_t](db)

# Get a specific key/val
var val: MyVal_t
ret = db.get(allKeys[0], val)   # return error code if key does not exist

# which is equivalent to 
let val_str: string = db[allKeys[0]]
val = deserializeBinary[MyVal_t](val_str)

```
