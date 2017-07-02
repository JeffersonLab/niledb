# Niledb

[![Build Status](https://travis-ci.org/JeffersonLab/niledb.svg?branch=master)](https://travis-ci.org/JeffersonLab/niledb)

A fast file-hash DB. Interface is Key/Value pair semantics. Storage
of these pairs is into strings, and uses an underlying Berkeley Sleep Cat
file-hash database. A single integer index is provided to allow the 
grouping of the values from many DB's but with a single key. 

The `serializetools` module provides tools for serialization and 
deserialization of keys and values to/from strings.

## Example

```nimrod
# example.nim
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

# open and existing db
var ret = db.open("some_file", O_RDONLY, 0o400)

# grab all the keys and deserialize them
let des_keys: seq[MyKey_t] = allKeys[MyKey_t](db)

# Get a specific key/val
var val: MyVal_t
ret = db.get(allKeys[0], val)

```
