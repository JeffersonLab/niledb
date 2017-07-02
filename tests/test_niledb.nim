##  Unittests for niledb

import niledb, tables,
       serializetools/serializebin, serializetools/serialstring
import unittest
import strutils, posix, os, hashes
import random
  
# Useful for debugging
proc printBin(x:string): string =
  ## Print a binary string
  result = "0x"
  for e in items(x):
    result.add(toHex(e))


# Key type used for tests
type
  KeyPropElementalOperator_t = object
    t_slice:    cint           ## Propagator time slice
    t_source:   cint           ## Source time slice
    spin_l:     cint           ## Sink spin index
    spin_r:     cint           ## spin index
    mass_label: SerialString   ## A mass label

proc hash(x: KeyPropElementalOperator_t): Hash =
  ## Computes a Hash from `x`.
  var h: Hash = 0
  # Iterate over parts of `x`.
  for xAtom in x.fields:
    # Mix the atom with the partial hash.
    h = h !& hash(xAtom)
    # Finish the hash.
    result = !$h


proc openTheDB(out_file: string): ConfDataStoreDB =
  ## Convenience function to open a DB
  echo "Declare conf db"
  result = newConfDataStoreDB()

  # Open a file
  echo "Is file= ", out_file, "  present?"
  if fileExists(out_file):
    echo "hooray, it exists"
  else:
    quit("oops, does not exist")

  echo "open the db = ", out_file
  let ret = result.open(out_file, O_RDONLY, 0o400)
  echo "return type= ", ret
  if ret != 0:
    quit("strerror= " & $strerror(errno))



#-----------------------------------------------------------
#
# Unittests of the DB functions
#
suite "Tests of DB functions":
  # Hold onto this
  var meta:string = """<?xml version="1.0"?>

<DBMetaData>
  <id>propElemOp</id>
  <lattSize>4 4 4 16</lattSize>
  <decay_dir>3</decay_dir>
</DBMetaData>
"""

  # File name for tests
  let out_file = "foo.sdb"  

  # Save a key for later testing
  var save_a_key: KeyPropElementalOperator_t
  

  #--------------------------------
  test "Test writing a DB":
    # Need to declare something
    echo "Declare conf db"
    var db = newConfDataStoreDB()

    # Let us write a file
    echo "Is file= ", out_file, "  present?"
    if fileExists(out_file):
      echo "It exists, so remove it"
      removeFile(out_file)
    else:
      echo "Does not exist"

    # Meta-data
    echo "Here is the metadata to insert:\n", meta
    db.setMaxUserInfoLen(meta.len)

    echo "open the db = ", out_file
    var ret = db.open(out_file, O_RDWR or O_TRUNC or O_CREAT, 0o664)
    echo "open = ", out_file, "  return type= ", ret
    if ret != 0:
      quit("strerror= " & $strerror(errno))

    # Insert new DB-meta
    ret = db.insertUserdata(meta)
    if ret != 0:
      quit("strerror= " & $strerror(errno))
 
    # Write stuff
    var kv = initTable[KeyPropElementalOperator_t,float]()

    # labels
    let labels = @["fred", "george"]

    # Build up some keys
    var first = true

    for ll in items(labels):
      for t_slice in 9..10:
        for sl in 0..3:
          for sr in 0..3:
            echo "t_slice= ", t_slice, " sl= ", sl, " sr= ", sr
            let key = KeyPropElementalOperator_t(t_slice: cint(t_slice), t_source: 5, 
                                                 spin_l: cint(sl), spin_r: cint(sr), 
                                                 mass_label: SerialString(ll))
            let val = random(3.0)  # 
            add(kv,key,val)
            if first: 
              save_a_key = key

    # insert the entire table
    ret = db.insert(kv)
    if ret != 0:
      echo "Ooops, ret= ", ret
      quit("Error in insertion")

    # Close
    require(db.close() == 0)

    
  #--------------------------------
  test "Test reading an existing DB":
    # Open the DB
    var db = openTheDB(out_file)

    # Try metadata
    echo "Get metadata"
    var mmeta = db.getUserdata()
    echo "it did not blowup..."

    echo " meta= ", printBin(meta)
    echo "mmeta= ", printBin(mmeta)
    require(meta == mmeta)

    # Close
    require(db.close() == 0)

  
  #--------------------------------
  test "Poke around some in a previously written DB":
    # Open the DB
    var db = openTheDB(out_file)

    # Simple tests
    let here = db.exist(save_a_key)
    require(here)

    # Get it
    var val: float
    var ret = db.get(save_a_key, val)
    require(ret == 0)

    # Get it again
    echo "Pull out a string"
    let boo = db[save_a_key]
    echo "If we get this far it has not blown up"
    require(boo.len > 0)
    require(db.close() == 0)


  #--------------------------------
  test "Test reading all the binary keys out of an existing DB":
    # Open the DB
    var db = openTheDB(out_file)

    # Tests
    # Read all the keys
    echo "try getting all the binary keys"
    let all_keys = db.allBinaryKeys()
    echo "binary: found num keys= ", all_keys.len
    echo "here is the first binary key: len= ", all_keys[0].len, "  val= ", printBin(all_keys[0])

    # Deserialize the first key
    echo "Deserialize first binary key..."
    let foo = deserializeBinary[KeyPropElementalOperator_t](all_keys[0])
    echo "here it is:\n", foo

    # Close
    require(db.close() == 0)


  #--------------------------------
  test "Test reading deserialized keys out of an existing DB":
    # Open the DB
    var db = openTheDB(out_file)

    # Read all the keys
    echo "try getting all the deserialized keys"
    let des_keys = allKeys[KeyPropElementalOperator_t](db)
    echo "found num all keys= ", des_keys.len
    echo "here is the first all key: len= ", des_keys.len, "  val= ", des_keys[0]
    #for i in 0..des_keys.len-1:
    for i in 0..10:
      echo "k[",i,"]= ", des_keys[i]

    # Close
    require(db.close() == 0)


  #--------------------------------
  test "Test reading all the pairs out of a DB":
    # Open the DB
    var db = openTheDB(out_file)

    # Read all the keys & data
    echo "try getting all the deserialized pairs"
    let des_pairs = allPairs[KeyPropElementalOperator_t,float](db)
    echo "found num keys= ", des_pairs.len
    echo "here are all the keys: len= ", des_pairs.len, "  keys:\n"
    for k,v in des_pairs:
      echo "k= ", $k, "  v= ", $v

    # Close
    require(db.close() == 0)




