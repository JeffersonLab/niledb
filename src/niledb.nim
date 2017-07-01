##   Class for storing keys and corresponding vector of objects from
##     all configurations

import 
  serializetools/serializebin, serializetools/crc32,
  ffdb_header, system, tables, serializetools/serialstring,
  strutils


const
  FILEDB_DEFAULT_PAGESIZE = 8192
  FILEDB_DEFAULT_NUM_BUCKETS = 32

# Need C-based printf
proc cprintf(formatstr: cstring) {.importc: "printf", varargs, header: "<stdio.h>".}

# Need C-based free
proc cfree(p: pointer): void {.importc: "free", header: "<stdlib.h>".}

template asarray*[T](p:pointer):auto =
  ## Convert pointers to C-style arrays of types.
  type A{.unchecked.} = array[0..0,T]
  cast[ptr A](p)


# String conversion
proc `$`*(a: FILEDB_DBT): string =
  ## Convert a stupid C-based string `a` of length `size` into a proper string
  result = newString(a.size)
  let sz = int(a.size)
  copyMem(addr(result[0]), a.data, sz)


proc printBin(x:string): string =
  ## Print a binary string
  result = "0x"
  for e in items(x):
    result.add(toHex(e))


## Main type
type
  ConfDataStoreDB* = object
    filename:  string           ## database name
    options:   FILEDB_OPENINFO  ## all open options
    dbh:       ptr FILEDB_DB    ## opened database handle


proc newConfDataStoreDB*(): ConfDataStoreDB =
  ## Empty constructor for a data store for one configuration
  zeroMem(addr(result.options), sizeof((FILEDB_OPENINFO)))
  result.options.bsize = FILEDB_DEFAULT_PAGESIZE
  result.options.nbuckets = FILEDB_DEFAULT_NUM_BUCKETS
  #  the other elements will be arranged by file hash package
  
proc setCacheSize*(filedb: var ConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in bytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  filedb.options.cachesize = size

proc setCacheSizeMB*(filedb: var ConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in megabytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  if sizeof(culong) == sizeof((cuint)):
    quit("Cannot handle a 32-bit machine")
#[
    ##  this is a 32 bit machine, we need to make sure
    ##  we do not overflow the 32 bit integer here
    var i: cint = 1
    var tsize: cuint = size
    while i <= 20:
      tsize = (tsize shl 1)
      if i < 20 and tsize >= cast[cuint](0x80000000):
        ## 	    std::cerr << "Database cache size exceeds maximum unsigned int" << std::endl;
        tsize = 0xFFFFFFFF
        break
      inc(i)
    filedb.options.cachesize = tsize
]#
  else:
    filedb.options.cachesize = (cast[culong](size)) shl 20
  
proc setPageSize*(filedb: var ConfDataStoreDB; size: cuint) =
  ## Page size used when a new data based is created
  ## This only effects a new database
  ##
  ## @param pagesize the pagesize used in hash database. This value
  ## should be power of 2. The minimum value is 512 and maximum value
  ## is 262144
  filedb.options.bsize = size

proc setNumberBuckets*(filedb: var ConfDataStoreDB; num: cuint) =
  ## Set initial number of buckets
  ##
  ## This should be called before the open is called
  ##
  ## @param num the number of buckets should be used
  filedb.options.nbuckets = num

proc enablePageMove*(filedb: var ConfDataStoreDB) =
  ## Set whether to move pages when close to save disk space
  ##
  ## This only effective on writable database
  filedb.options.rearrangepages = 1

proc disablePageMove*(filedb: var ConfDataStoreDB) =
  filedb.options.rearrangepages = 0

proc setMaxUserInfoLen*(filedb: var ConfDataStoreDB; len: int) =
  ## Set and get maximum user information length
  filedb.options.userinfolen = cuint(len) + 1
  ##  account for possible null terminator on string
  
proc getMaxUserInfoLen*(filedb: ConfDataStoreDB): int {.noSideEffect.} =
  if filedb.dbh == nil: return int(filedb.options.userinfolen)
  return int(filedb_max_user_info_len(filedb.dbh))

proc setMaxNumberConfigs*(filedb: var ConfDataStoreDB; num: cuint) =
  ## Set and get maximum number of configurations
  filedb.options.numconfigs = num

proc getMaxNumberConfigs*(filedb: ConfDataStoreDB): cuint {.noSideEffect.} =
  if filedb.dbh == nil: return filedb.options.numconfigs
  return filedb_num_configs(filedb.dbh)

proc open*(filedb: var ConfDataStoreDB; file: string; open_flags: cint; mode: cint): int =
  ## Open
  ## @param ``file`` filename holding all data and keys
  ## @param ``open_flags``: can be regular UNIX file open flags such as: O_RDONLY, O_RDWR, O_TRUNC
  ## @param mode regular unix file mode
  ##
  ## @return 0 on success, -1 on failure with proper errno set
  var foo: cstring = file
  echo "open: here are options:\n", filedb.options
  filedb.filename = file
  filedb.dbh = filedb_dbopen(foo, open_flags, mode, addr(filedb.options))
  if filedb.dbh == nil: return -1
  return 0


proc close*(filedb: var ConfDataStoreDB): cint =
  ## Close a database<
  return filedb_close(filedb.dbh)
  

proc insert*[K,D](filedb: var ConfDataStoreDB; key: K; data: D): int =
  ## Insert a pair of data and key into the database
  ## data is not ensemble, but a vector of complex.
  ## @param key a key
  ## @param data a user provided data
  ##
  ## @return 0 on successful write, -1 on failure with proper errno set
  var keyObj = serializeBinary(key)

  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # Convert data into binary form
  var dataObj = serializeBinary(data)

  # create DBt object
  var dbdata = FILEDB_DBT(data: addr(dataObj[0]), size: cuint(dataObj.len))

  # now it is time to insert
  let ret = int(filedb_insert_data(filedb.dbh, addr(dbkey), addr(dbdata)))
  return ret


proc get*[K,D](filedb: var ConfDataStoreDB; key: K; data: var D): int =
  ## Get data for a given key
  ## @param key user supplied key
  ## @param data after the call data will be populated
  ## @return 0 on success, otherwise the key not found
  let keyObj: cstring = serializeBinary(key);

  # create key
  let dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: keyObj.len())
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT
  dbdata.data = 0
  dbdata.size = 0

  # now retrieve data from database
  let ret = filedb_get_data(filedb.dbh, addr(dbkey), addr(dbdata), 0)
  if ret == 0:
    try:
      # convert object into a string
      # Convert data into binary form 
      let dataObj = string(dbdata.data)
      data = deserializeBinary[D](dataObj)
      # I have to use free since I use malloc in c code
      cfree(dbdata.data)
    except:
      quit("failed to deserialize")

  return int(ret)


proc exist*[K](filedb: var ConfDataStoreDB; key: K): bool =
  ## Does this key exist in the store
  ## @param key a key object
  ## @return true if the answer is yes
  let keyObj = serializeBinary(key)

  # create key
  let dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: keyObj.size())
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT
  dbdata.data = 0
  dbdata.size = 0

  # now retrieve data from database
  let ret: cint = filedb.dbh.get(filedb.dbh, addr(dbkey), addr(dbdata), 0)
  if ret == 0:
    cfree(dbdata.data)
    result = true
  else:
    result = false


proc allBinaryKeys*(filedb: ConfDataStoreDB): seq[string] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.

  var 
    #foobar: array[0..ArrayDummySize, cstring]
    #dbkeys: ptr FILEDB_DBT
    dbkeys: pointer
    num0:   cuint
    

  # Grab all keys in string form
  echo "call filedb_get_all"
  filedb_get_all_keys(filedb.dbh, addr(dbkeys), addr(num0))
  let num = int(num0)
  echo "keys: num keys= ", num

  # Hold the result
  newSeq[string](result, num)

  # Loop over all the keys and deserialize them
  for i in 0..num-1:
    ## convert into key object
    var sz:int = int(asarray[FILEDB_DBT](dbkeys)[i].size)
    #var keyObj = newString(sz)
    #copyMem(addr(keyObj[0]), asarray[FILEDB_DBT](dbkeys)[i].data, sz)

    # put this new key into the vector
    result[i] = $asarray[FILEDB_DBT](dbkeys)[i]
    #result[i] = keyObj
    if (i == 0) or (i < 120):
      echo "binaryKeys: i= ", i, "  sz= ", sz,  "  result.len= ", result[i].len, " res= ", printBin(result[i])
    
    # free memory
    #echo "i= ", i, "  sz= ", sz
    cfree(asarray[FILEDB_DBT](dbkeys)[i].data)

  # Cleanup
  echo "free"
  cfree(dbkeys)



proc allBinaryPairs*(filedb: ConfDataStoreDB): seq[tuple[key:string,val:string]] =
  ## Return all available key/value pairs to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.

  var 
    dbkeys: pointer
    dbvals: pointer
    num0:   cuint
    sz:     int

  # Grab all keys & data in string form
  echo "call filedb_get_pairs"
  filedb_get_all_pairs(filedb.dbh, addr(dbkeys), addr(dbvals), addr(num0))
  let num = int(num0)
  echo "keys: num keys= ", num

  echo "try asarray"
  #  let foo = dbkeys[]
  let foo = asarray[FILEDB_DBT](dbkeys)[0]
  echo "foo.sz= ", $foo.size
  
  # Hold the result
  newSeq[tuple[key:string,val:string]](result, num)

  # Loop over all the keys and deserialize them
  for i in 0..num-1:
    # convert into key object
    #sz = int(asarray[FILEDB_DBT](dbkeys)[i].size)
    #var keyObj = newString(sz)
    #copyMem(addr(keyObj[0]), asarray[FILEDB_DBT](dbkeys)[i].data, sz)

    # convert into data object
    #sz = int(asarray[FILEDB_DBT](dbvals)[i].size)
    #var dataObj = newString(sz)
    #copyMem(addr(dataObj[0]), asarray[FILEDB_DBT](dbvals)[i].data, sz)

    # put this new key into the table
    result[i] = ($asarray[FILEDB_DBT](dbkeys)[i], $asarray[FILEDB_DBT](dbvals)[i])
    #result[i] = (keyObj, dataObj)
    
    echo "res[",i,"]= ", printBin(result[i].key)

    # free memory
    cfree(asarray[FILEDB_DBT](dbkeys)[i].data)
    cfree(asarray[FILEDB_DBT](dbvals)[i].data)

  # Cleanup
  echo "free"
  cfree(dbkeys)
  cfree(dbvals)



#proc allKeys*[K](filedb: ConfDataStoreDB, result: var seq[K]) =
proc allKeys*[K](filedb: ConfDataStoreDB): seq[K] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.
  # Grab all the binary keys
  echo "allKeys: call allBinaryKeys"
  let all_keys = allBinaryKeys(filedb)

  # Hold the result
  echo "allKeys: len= ", all_keys.len, "  newSeq"
  newSeq[K](result, all_keys.len)

  # Loop over all the keys and deserialize them
  echo "allKeys: loop"
  for i in 0..all_keys.len-1:
    # convert into key object
    if (i == 0) or (i < 120):
      echo "i= ", i, "  key= ", printBin(all_keys[i])
    result[i] = deserializeBinary[K](all_keys[i])
    if (i == 0) or (i < 120):
      echo "res[",i,"]= ", result[i]

  echo "allKeys: last check: here is the 0th key: ", result[0]
  echo "another last check: result[0]: ", printBin($result[0].mass_label)
  echo "allKeys: done"
  #quit("bye")



proc allPairs*[K,D](filedb: ConfDataStoreDB): Table[K,D] =
  ## keys: var >vector[K]; values: var vector[D]) =
  ## Return all pairs of keys and data
  ## @param keys user supplied empty vector to hold all keys
  ## @param data user supplied empty vector to hold data
  ## @return keys and data in the vectors having the same size
  let all_pairs = allBinaryPairs(filedb)
    
  result = initTable[K,D](rightSize(all_pairs.len))

  # Loop over all the keys and deserialize them
  for i in 0..all_pairs.len-1:
    result.add(deserializeBinary[K](all_pairs[i].key), deserializeBinary[D](all_pairs[i].val))


#[
proc flush*(filedb: var ConfDataStoreDB) =
  ## Flush database in memory to disk
  discard filedb.dbh.sync(filedb.dbh, 0)
]#


proc storageName*(filedb: ConfDataStoreDB): string {.noSideEffect.} =
  ## Name of database associated with this Data store
  ##
  ## @return database name
  return filedb.filename


proc insertUserdata*(filedb: var ConfDataStoreDB; user_data: string): int =
  ## Insert user data into the  metadata database
  ##
  ## @param user_data user supplied data
  ## @return returns 0 if success, else failure
  var dd: cstring
  shallowCopy(dd, user_data)
  return filedb_set_user_info(filedb.dbh, cast[ptr cuchar](addr(dd[0])), cuint(user_data.len))


proc getUserdata*(filedb: ConfDataStoreDB): string =
  ## Get user user data from the metadata database
  ##
  ## @param user_data user supplied buffer to store user data
  ## @return returns user supplied buffer if success. Otherwise failure. 
  var len: cuint = filedb_max_user_info_len(filedb.dbh)
  echo "getUserdata: len= ", len
  result = newString(len+1)
  var ret = filedb_get_user_info(filedb.dbh, addr(result[0]), addr(len))
  echo "ret= ", ret
  if ret != 0:
    quit("Error returning user meta-data from db")
  return result


#-----------------------------------------------------------------------
when isMainModule:
  import strutils, posix, os, hashes

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

  # Hold onto this
  var meta:string

  #
  # Test reading an existing DB
  #
  if true:
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
    #  echo "metadata = ", meta
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
      #var des_keys: seq[KeyPropElementalOperator_t]
      #allKeys[KeyPropElementalOperator_t](db, des_keys)
      echo "found num all keys= ", des_keys.len
      echo "here is the first all key: len= ", des_keys.len, "  val= ", des_keys[0]
      #echo "here are all the keys: len= ", des_keys.len, "  vals:\n", des_keys
      #for i in 0..des_keys.len-1:
      for i in 0..100:
        echo "k[",i,"]= ", des_keys[i]

    # Close
    if (db.close() != 0):
      quit("Some strange error closing db")

  #
  # Test writing a DB
  #
  if true:
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

    # Finish up
    if (db.close() != 0):
      quit("Some strange error closing db")

    
  #
  # Test reading from a previously written DB
  #
  if true:
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
      #let des_pairs = db.allBinaryPairs()
      echo "found num keys= ", des_pairs.len
      echo "here are all the keys: len= ", des_pairs.len, "  keys:\n"
      for k,v in des_pairs:
        echo "k= ", $k, "  v= ", $v

    # Close
    if (db.close() != 0):
      quit("Some strange error closing db")

