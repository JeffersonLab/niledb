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


proc openTheSDB(out_file: string): ConfDataStoreDB =
  ## Convenience function to open a SDB
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


proc openTheEDB(out_file: string): AllConfDataStoreDB =
  ## Convenience function to open an EDB
  echo "Declare conf db"
  result = newAllConfDataStoreDB()

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
# Useful vars
#
## Hold onto this
let
  meta:string = """<?xml version="1.0"?>

<DBMetaData>
  <id>propElemOp</id>
  <lattSize>4 4 4 16</lattSize>
  <decay_dir>3</decay_dir>
</DBMetaData>
"""

  # File name for tests
  single_file = "foo.sdb"  
  multi_file  = "boo.edb"  



#-----------------------------------------------------------
#
# Unittests of the SDB functions
#
suite "Tests of single configuration (S)DB functions":
  # Save a key for later testing
  var save_a_key: KeyPropElementalOperator_t


  #--------------------------------
  test "Test writing a single config DB":
    # Need to declare something
    echo "Declare conf db"
    var db = newConfDataStoreDB()

    # Let us write a file
    echo "Is file= ", single_file, "  present?"
    if fileExists(single_file):
      echo "It exists, so remove it"
      removeFile(single_file)
    else:
      echo "Does not exist"

    # Meta-data
    echo "Here is the metadata to insert:\n", meta
    db.setMaxUserInfoLen(meta.len)

    echo "open the db = ", single_file
    var ret = db.open(single_file, O_RDWR or O_TRUNC or O_CREAT, 0o664)
    echo "open = ", single_file, "  return type= ", ret
    if ret != 0:
      quit("strerror= " & $strerror(errno))

    # Insert new DB-meta
    ret = db.insertUserdata(meta)
    if ret != 0:
      quit("strerror= " & $strerror(errno))
 
    # labels
    let labels = @["fred", "george"]

    # Build up some keys and associated values in a table
    var kv = initTable[KeyPropElementalOperator_t,float]()

    var first = true

    for ll in items(labels):
      for t_slice in 9..10:
        for sl in 0..3:
          for sr in 0..3:
            #echo "t_slice= ", t_slice, " sl= ", sl, " sr= ", sr
            let key = KeyPropElementalOperator_t(t_slice: cint(t_slice), t_source: 5, 
                                                 spin_l: cint(sl), spin_r: cint(sr), 
                                                 mass_label: SerialString(ll))
            let val = random(3.0)  # some arbitrary number
            kv.add(key,val)
            if first:   # save some random key for later testing
              save_a_key = key
              first = false

    # insert the entire table
    ret = db.insert(kv)
    if ret != 0:
      echo "Ooops, ret= ", ret
      quit("Error in insertion")

    # Close
    require(db.close() == 0)

    
  #--------------------------------
  test "Test reading an existing SDB":
    # Open the DB
    var db = openTheSDB(single_file)

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
  test "Poke around some in a previously written SDB":
    # Open the DB
    var db = openTheSDB(single_file)

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
  test "Test reading all the binary keys out of an existing SDB":
    # Open the DB
    var db = openTheSDB(single_file)

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
  test "Test reading deserialized keys out of an existing SDB":
    # Open the DB
    var db = openTheSDB(single_file)

    # Read all the keys
    echo "try getting all the deserialized keys"
    let des_keys = allKeys[KeyPropElementalOperator_t](db)
    echo "found num all keys= ", des_keys.len
    echo "here is the first all key: len= ", des_keys.len, "  val= ", des_keys[0]
    echo "here are 10 of the keys"
    #for i in 0..des_keys.len-1:
    for i in 0..10:
      echo "k[",i,"]= ", des_keys[i]

    # Close
    require(db.close() == 0)


  #--------------------------------
  test "Test reading all the pairs out of a SDB":
    # Open the DB
    var db = openTheSDB(single_file)

    # Read all the keys & data
    echo "try getting all the deserialized pairs"
    let des_pairs = allPairs[KeyPropElementalOperator_t,float](db)
    echo "found num keys= ", des_pairs.len
    echo "here are all the keys: len= ", des_pairs.len, "  keys:\n"
    echo "here are 10 of the keys"
    for k,v in des_pairs:
      echo "k= ", $k, "  v= ", $v

    # Close
    require(db.close() == 0)


#-----------------------------------------------------------
#
# Unittests of the SDB functions
#
suite "Tests of multi-configuration (Ensemble)DB functions":
  # Save a key for later testing
  var save_a_key: KeyPropElementalOperator_t
  
  # Number of configurations for the tests
  let nbins = 10


  #--------------------------------
  test "Test writing a multiple config DB (an EDB)":
    # Need to declare something
    echo "Declare allconf db"
    var db = newAllConfDataStoreDB()

    # Let us write a file
    echo "Is multi-file= ", multi_file, "  present?"
    if fileExists(multi_file):
      echo "It exists, so remove it"
      removeFile(multi_file)
    else:
      echo "Does not exist"

    # Meta-data
    echo "Here is the metadata to insert:\n", meta
    db.setMaxUserInfoLen(meta.len)

    # Number of configs
    echo "Set max configs= ", nbins
    db.setMaxNumberConfigs(nbins)

    echo "open the db = ", multi_file
    var ret = db.open(multi_file, O_RDWR or O_TRUNC or O_CREAT, 0o664)
    echo "open = ", multi_file, "  return type= ", ret
    if ret != 0:
      quit("strerror= " & $strerror(errno))

    # Insert new DB-meta
    ret = db.insertUserdata(meta)
    if ret != 0:
      quit("strerror= " & $strerror(errno))
 
    # labels
    let labels = @["fred", "george"]

    # Build up some keys and associated values in a table
    var keys: seq[KeyPropElementalOperator_t]
    keys = @[]

    for ll in items(labels):
      for t_slice in 9..10:
        for sl in 0..1:
          for sr in 2..3:
            #echo "t_slice= ", t_slice, " sl= ", sl, " sr= ", sr
            keys.add(KeyPropElementalOperator_t(t_slice: cint(t_slice), t_source: 5, 
                                                spin_l: cint(sl), spin_r: cint(sr), 
                                                mass_label: SerialString(ll)))

    # Save an arbitrary key
    save_a_key = keys[0]

    # For each key, built up some values and insert them
    for key in items(keys):
      var val = newSeq[float](nbins)

      for n in 0..nbins-1:
        val[n] = random(3.0)  # some arbitrary number

      # Insert
      ret = db.insert(key,val)
      if ret != 0:
        echo "Ooops, ret= ", ret
        quit("Error in insertion")

    # Close
    require(db.close() == 0)
    

  #--------------------------------
  test "Test reading an existing EDB":
    # Open the DB
    var db = openTheEDB(multi_file)

    # Try metadata
    echo "Get metadata"
    var mmeta = db.getUserdata()
    echo "it did not blowup..."

    echo " meta= ", printBin(meta)
    echo "mmeta= ", printBin(mmeta)
    require(meta == mmeta)

    echo "Get number of configs"
    let ncfgs = db.getMaxNumberConfigs()
    echo "Number of configs= ", ncfgs
    require(ncfgs == nbins)

    # Close
    require(db.close() == 0)

  
  #--------------------------------
  test "Poke around some in a previously written EDB":
    # Open the DB
    var db = openTheEDB(multi_file)

    # Simple tests
    let here = db.exist(save_a_key)
    require(here)

    # Get it
    var val: seq[float]
    var ret = db.get(save_a_key, val)
    require(ret == 0)

    # Get it again
    echo "Pull out a string"
    let boo = db[save_a_key]
    echo "If we get this far it has not blown up: the retrieved string= ", printBin(boo)
    require(boo.len > 0)
    require(db.close() == 0)


  #--------------------------------
  test "Test reading all the binary keys out of an existing EDB":
    # Open the DB
    var db = openTheEDB(multi_file)

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
  test "Test reading deserialized keys out of an existing EDB":
    # Open the DB
    var db = openTheEDB(multi_file)

    # Read all the keys
    echo "try getting all the deserialized keys"
    let des_keys = allKeys[KeyPropElementalOperator_t](db)
    echo "found num all keys= ", des_keys.len
    echo "here is the first all key: len= ", des_keys.len, "  val= ", des_keys[0]
    echo "here are 10 of the keys"
    #for i in 0..des_keys.len-1:
    for i in 0..10:
      echo "k[",i,"]= ", des_keys[i]

    # Close
    require(db.close() == 0)


  #--------------------------------
  test "Test reading all the pairs out of a EDB":
    # Open the DB
    var db = openTheEDB(multi_file)

    # Read all the keys & data
    echo "try getting all the deserialized pairs"
    let des_pairs = allPairs[KeyPropElementalOperator_t,float](db)
    echo "found num keys= ", des_pairs.len
    echo "here are all the keys: len= ", des_pairs.len, "  keys:\n"
    for k,v in des_pairs:
      echo "k= ", $k, "  v= ", $v

    # Close
    require(db.close() == 0)
