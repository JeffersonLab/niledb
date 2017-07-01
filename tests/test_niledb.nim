##  Unittests for niledb

import niledb, tables,
       serializetools/serializebin, serializetools/serialstring
import unittest
import strutils, posix, os, hashes
  
#  serializetools/serializebin, serializetools/crc32,
#  ffdb_header, system, tables, serializetools/serialstring,
#  strutils


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



#-----------------------------------------------------------
suite "Tests of DB functions":
  # Hold onto this
  var meta:string

  test "Test reading an existing DB":
    # Need to declare something
    echo "Declare conf db"
    var db = newConfDataStoreDB()

    # Open a file
    let file = "prop.sdb"
    echo "Is file= ", file, "  present?"
    if fileExists(file):
      echo "hooray, it exists"
    else:
      quit("oops, does not exist")

    echo "open the db = ", file
    var ret = db.open(file, O_RDONLY, 0o400)
    echo "return type= ", ret
    if ret != 0:
      quit("strerror= " & $strerror(errno))

    # Try metadata
    echo "Get metadata"
    meta = db.getUserdata()
    echo "it did not blowup..."
  
    # Tests
    if false:
      # Read all the keys
      echo "try getting all the binary keys"
      let all_keys = db.allBinaryKeys()
      echo "binary: found num keys= ", all_keys.len
      echo "here is the first binary key: len= ", all_keys[0].len, "  val= ", printBin(all_keys[0])

      # Deserialize the first key
      echo "Deserialize first binary key..."
      let foo = deserializeBinary[KeyPropElementalOperator_t](all_keys[0])
      echo "here it is:\n", foo

    # Read all the keys
    if true:
      echo "try getting all the deserialized keys"
      let des_keys = allKeys[KeyPropElementalOperator_t](db)
      echo "found num all keys= ", des_keys.len
      echo "here is the first all key: len= ", des_keys.len, "  val= ", des_keys[0]
      #for i in 0..des_keys.len-1:
      for i in 0..100:
        echo "k[",i,"]= ", des_keys[i]

    # Close
    ret = db.close()
    require(ret == 0)


#--------------------------------
  test "Test writing a DB":
    # Need to declare something
    echo "Declare conf db"
    var db = newConfDataStoreDB()

    # Let us write a file
    let out_file = "foo.sdb"
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
    if true:
      let val:float = 5.7
      for t_slice in 9..10:
        for sl in 0..3:
          for sr in 0..3:
            echo "t_slice= ", t_slice, " sl= ", sl, " sr= ", sr
            let key = KeyPropElementalOperator_t(t_slice: cint(t_slice), t_source: 5, 
                                                 spin_l: cint(sl), spin_r: cint(sr), 
                                                 mass_label: SerialString("fred"))

            let ret = db.insert(key, val)
            if ret != 0:
              echo "Ooops, ret= ", ret
              quit("Error in insertion")

    # Close
    ret = db.close()
    require(ret == 0)

    
#--------------------------------
  test "Test reading from a previously written DB":
    # Need to declare something
    echo "Declare conf db"
    var db = newConfDataStoreDB()

    # Open a file
    let file = "foo.sdb"
    echo "Is file= ", file, "  present?"
    if fileExists(file):
      echo "hooray, it exists"
    else:
      quit("oops, does not exist")

    echo "open the db = ", file
    var ret = db.open(file, O_RDONLY, 0o400)
    echo "return type= ", ret
    if ret != 0:
      quit("strerror= " & $strerror(errno))
  
    # Read all the keys & data
    if true:
      echo "try getting all the deserialized pairs"
      let des_pairs = allPairs[KeyPropElementalOperator_t,float](db)
      echo "found num keys= ", des_pairs.len
      echo "here are all the keys: len= ", des_pairs.len, "  keys:\n"
      for k,v in des_pairs:
        echo "k= ", $k, "  v= ", $v

    # Close
    ret = db.close()
    require(ret == 0)

