##   Class for storing keys and corresponding vector of objects from
##     all configurations

import 
  serializetools/serializebin, serializetools/crc32,
  ffdb_header, system,
  strutils


const
  FILEDB_DEFAULT_PAGESIZE = 8192
  FILEDB_DEFAULT_NUM_BUCKETS = 32

# Deal with C-based arrays
#type
#  cArray{.unchecked.}[T] = array[0,T]
#
#template `[]`(x: cArray): untyped = addr x[0]
#template `&`(x: ptr cArray): untyped = addr x[0]

template asarray*[T](p:pointer):auto =
  ## Convert pointers to C-style arrays of types.
  type A{.unchecked.} = array[0..0,T]
  cast[ptr A](p)


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

proc setMaxUserInfoLen*(filedb: var ConfDataStoreDB; len: cuint) =
  ## Set and get maximum user information length
  filedb.options.userinfolen = len + 1
  ##  account for possible null terminator on string
  
proc getMaxUserInfoLen*(filedb: ConfDataStoreDB): cuint {.noSideEffect.} =
  if filedb.dbh == nil: return filedb.options.userinfolen
  return filedb_max_user_info_len(filedb.dbh)

proc setMaxNumberConfigs*(filedb: var ConfDataStoreDB; num: cuint) =
  ## Set and get maximum number of configurations
  filedb.options.numconfigs = num

proc getMaxNumberConfigs*(filedb: ConfDataStoreDB): cuint {.noSideEffect.} =
  if filedb.dbh == nil: return filedb.options.numconfigs
  return filedb_num_configs(filedb.dbh)

proc open*(filedb: var ConfDataStoreDB; file: string; open_flags: cint; mode: cint): cint =
  ## Open
  ## @param ``file`` filename holding all data and keys
  ## @param ``open_flags``: can be regular UNIX file open flags such as: O_RDONLY, O_RDWR, O_TRUNC
  ## @param mode regular unix file mode
  ##
  ## @return 0 on success, -1 on failure with proper errno set
  var foo: cstring = file
  echo "open: here are options:\n", filedb.options
#  filedb.dbh = filedb_dbopen(addr(foo), open_flags, mode, addr(filedb.options))
  filedb.dbh = filedb_dbopen(foo, open_flags, mode, addr(filedb.options))
  if filedb.dbh == nil: return -1
  return 0

#[
proc close*(filedb: var ConfDataStoreDB): cint =
  var ret: cint = 0
  if filedb.dbh != nil:
    ret = filedb.dbh.close(filedb.dbh)
    filedb.dbh = nil
  return ret
]#
  
proc insert*[K,D](filedb: var ConfDataStoreDB; key: K; data: D): cint =
  ## Insert a pair of data and key into the database
  ## data is not ensemble, but a vector of complex.
  ## @param key a key
  ## @param data a user provided data
  ##
  ## @return 0 on successful write, -1 on failure with proper errno set
  let keyObj: cstring = serializeBinary(key);

  # create key
  let dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: keyObj.size())
          
  # Convert data into binary form
  let dataObj = serializeBinary(data)

  # create DBt object
  let dbdata = FILEDB_DBT(data: addr(dataObj), size: dataObj.size)

  # now it is time to insert
  let ret: cint = filedb.dbh.put(filedb.dbh, addr(dbkey), addr(dbdata), 0)
  return ret


proc get*[K,D](filedb: var ConfDataStoreDB; key: K; data: var D): cint =
  ## Get data for a given key
  ## @param key user supplied key
  ## @param data after the call data will be populated
  ## @return 0 on success, otherwise the key not found
  let keyObj: cstring = serializeBinary(key);

  # create key
  let dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: keyObj.size())
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT
  dbdata.data = 0
  dbdata.size = 0

  # now retrieve data from database
  let ret: cint = filedb.dbh.get(filedb.dbh, addr(dbkey), addr(dbdata), 0)
  if ret == 0:
    try:
      # convert object into a string
      # Convert data into binary form 
      let dataObj = string(dbdata.data)
      data = deserializeBinary[D](dataObj)
      # I have to use free since I use malloc in c code
      #####      free(dbdata.data)
      echo "FIX ME"
    except:
      quit("failed to deserialize")

  return ret

proc exist*[K](filedb: var ConfDataStoreDB; key: K): bool =
  ## Does this key exist in the store
  ## @param key a key object
  ## @return true if the answer is yes
  let keyObj: cstring = serializeBinary(key)

  # create key
  let dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: keyObj.size())
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT
  dbdata.data = 0
  dbdata.size = 0

  # now retrieve data from database
  let ret: cint = filedb.dbh.get(filedb.dbh, addr(dbkey), addr(dbdata), 0)
  if ret == 0:
    #####      free(dbdata.data)
    result = true
  else:
    result = false


proc keysBinary*(filedb: ConfDataStoreDB): seq[string] =
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

  # Keys
  # let keys = cast[array[0,FILEDB_DBT]](dbkeys)

  echo "try asarray"
  #  let foo = dbkeys[]
  let foo = asarray[FILEDB_DBT](dbkeys)[0]
  echo "foo.sz= ", $foo.size

  
  # Loop over all the keys and deserialize them
  for i in 0..num-1:
    # convert into key object
    var sz:int = int(asarray[FILEDB_DBT](dbkeys)[i].size)
    var keyObj = newString(sz)
    copyMem(addr(keyObj[0]), asarray[FILEDB_DBT](dbkeys)[i].data, sz)

    # put this new key into the vector
    result[i] = $asarray[FILEDB_DBT](dbkeys)[i]
    if i == 0:
      echo "keysBinary: i= ", i, "  sz= ", sz,  "  result.len= ", result[i].len, " res= ", printBin(result[i])
    
    # free memory
    #echo "i= ", i, "  sz= ", sz
    #dealloc(asarray[FILEDB_DBT](dbkeys)[i].data)

  # Cleanup
  echo "free"
  dealloc(dbkeys)



proc keys*[K](filedb: ConfDataStoreDB): seq[K] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.
  newSeq[K](result)

  var 
    dbkeys: ptr FILEDB_DBT
    num:    cuint
    
  # Grab all keys in string form
  filedb_get_all_keys(filedb.dbh, dbkeys, addr(num))
  echo "keys: num keys= ", num

  # Loop over all the keys and deserialize them
  for i in 1..num:
    # convert into key object
    var keyObj = newString(dbkeys[i].size)
    copyMem(addr(keyObj[0]), dbkeys[i].data, dbkeys[i].size)

    # put this new key into the vector
    result.push_back(deserializeBinary[K](keyObj))

    # free memory
    dealloc(dbkeys[i].data)

  # Cleanup
  dealloc(dbkeys)



proc keysAndData*[K,D](filedb: ConfDataStoreDB): seq[tuple[key:K,val:D]] =
  ## keys: var >vector[K]; values: var vector[D]) =
  ## Return all pairs of keys and data
  ## @param keys user supplied empty vector to hold all keys
  ## @param data user supplied empty vector to hold data
  ## @return keys and data in the vectors having the same size

  newSeq[tuple[key:K,val:D]](result)
  var 
    dbkeys: ptr FILEDB_DBT
    dbvals: ptr FILEDB_DBT
    num:    cuint
    
  # Grab all keys in string form
  filedb_get_all_pairs(filedb.dbh, dbkeys, dbvals, addr(num))
  echo "keys: num key/vals= ", num

  # Loop over all the keys and deserialize them
  for i in 1..num:
    # convert into key object
    var keyObj  = newString(dbkeys[i].size)
    copyMem(addr(keyObj[0]), dbkeys[i].data, dbkeys[i].size)
    let k = deserializeBinary[K](keyObj)

    var valObj = newString(dbvals[i].size)
    copyMem(addr(valObj[0]), dbvals[i].data, dbvals[i].size)
    let v = deserializeBinary[D](valObj)

    # put this new key into the vector
    result.push_back(k, v)

    # free memory
    dealloc(dbkeys[i].data)

  # Cleanup
  dealloc(dbkeys)
  dealloc(dbvals)


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


proc insertUserdata*(filedb: var ConfDataStoreDB; user_data: string): cint =
  ## Insert user data into the  metadata database
  ##
  ## @param user_data user supplied data
  ## @return returns 0 if success, else failure
  #  var foo = cstring(user_data)
  #  return filedb_set_user_info(filedb.dbh, addr(foo), foo.len)
  return filedb_set_user_info(filedb.dbh, cast[ptr cuchar](user_data[0]),
                            cuint(user_data.len))


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
  import strutils, posix, os   # get the posix file modes

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
  let ret = db.open(file, O_RDONLY, 0o400)
  echo "return type= ", ret
  if ret != 0:
    quit("strerror= " & $strerror(errno))

  # Try metadata
  echo "Get metadata"
  let meta = db.getUserdata()
  #  echo "metadata = ", meta
  echo "it did not blowup..."
  
  # Read all the keys
  echo "try getting all the binary keys"
  let all_keys = db.keysBinary()
  echo "found num keys= ", all_keys.len
  echo "here is the first key: len= ", all_keys[0].len, "  val= ", printBin(all_keys[0])

  # Get braver, attempt to deserialize
  type
    KeyPropElementalOperator_t = object
      t_slice:    cint     ## Propagator time slice
      t_source:   cint     ## Source time slice
      spin_l:     cint     ## Sink spin index
      spin_r:     cint     ## spin index
      mass_label: cstring  ## A mass label

  # Deserialize the first key
  echo "Deserialize..."
  let foo = deserializeBinary[KeyPropElementalOperator_t](all_keys[0])
  echo "here it is:\n", foo
