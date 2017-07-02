##   Class for storing keys and corresponding vector of objects from
##     all configurations

import niledb/private/ffdb_header
import system, tables
import strutils
import 
  serializetools/serializebin, serializetools/crc32, serializetools/serialstring


const
  FILEDB_DEFAULT_PAGESIZE = 8192
  FILEDB_DEFAULT_NUM_BUCKETS = 32


# Need C-based free
proc cfree(p: pointer): void {.importc: "free", header: "<stdlib.h>".}

template asarray[T](p:pointer):auto =
  ## Convert pointers to C-style arrays of types.
  type A{.unchecked.} = array[0..0,T]
  cast[ptr A](p)


# String conversion
proc `$`(a: FILEDB_DBT): string =
  ## Convert a stupid C-based string `a` of length `size` into a proper string
  result = newString(a.size)
  let sz = int(a.size)
  copyMem(addr(result[0]), a.data, sz)


#proc printBin(x:string): string =
#  ## Print a binary string
#  result = "0x"
#  for e in items(x):
#    result.add(toHex(e))


## Main type
type
  ConfDataStoreDB* = object
    filename:  string           ## database name
    metadata:  string           ## metadata
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
  filedb.options.userinfolen = cuint(len)
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
  filedb.filename = file
  filedb.dbh = filedb_dbopen(foo, open_flags, mode, addr(filedb.options))
  if filedb.dbh == nil: return -1
  return 0


proc close*(filedb: var ConfDataStoreDB): cint =
  ## Close a database
  return filedb_close(filedb.dbh)
  

proc insert*[K,D](filedb: var ConfDataStoreDB; key: K; data: D): int =
  ## Insert a pair of data and key into the database
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


proc insert*[K,D](filedb: var ConfDataStoreDB; kv: Table[K,D]): int =
  ## Insert a table of key/value pairs `kv` into the database
  result = 0
  for k,v in pairs(kv):
    let ret = filedb.insert(k,v)
    if ret != 0: return ret


proc get*[K,D](filedb: ConfDataStoreDB; key: K; data: var D): int =
  ## Get data for a given key
  ## @param key user supplied key
  ## @param data after the call data will be populated
  ## @return 0 on success, otherwise the key not found
  var keyObj = serializeBinary(key)

  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT

  # now retrieve data from database
  let ret = filedb_get_data(filedb.dbh, addr(dbkey), addr(dbdata))
  if ret == 0:
    # convert object into a string
    data = deserializeBinary[D]($dbdata)
    # I have to use free since I use malloc in c code
    cfree(dbdata.data)

  return int(ret)


proc `[]`*[K](filedb: ConfDataStoreDB; key: K): string =
  ## Get data for a given key
  ## @param key user supplied key
  ## @return data on success, otherwise abort
  result = ""
  var keyObj = serializeBinary(key)

  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT

  # now retrieve data from database
  let ret = filedb_get_data(filedb.dbh, addr(dbkey), addr(dbdata))
  if ret == 0:
    # convert object into a string
    result = $dbdata
    # I have to use free since I use malloc in c code
    cfree(dbdata.data)
  else:
    quit("Error retrieving key = " & $key)


proc exist*[K](filedb: ConfDataStoreDB; key: K): bool =
  ## Does this key exist in the store
  ## @param key a key object
  ## @return true if the answer is yes
  var keyObj = serializeBinary(key)

  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create DBt object
  var dbdata: FILEDB_DBT

  # now retrieve data from database
  let ret = filedb_get_data(filedb.dbh, addr(dbkey), addr(dbdata))
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
    dbkeys: pointer
    num0:   cuint
    
  # Grab all keys in string form
  filedb_get_all_keys(filedb.dbh, addr(dbkeys), addr(num0))
  let num = int(num0)

  # Hold the result
  newSeq[string](result, num)

  # Loop over all the keys and deserialize them
  for i in 0..num-1:
    ## convert into key object
    result[i] = $asarray[FILEDB_DBT](dbkeys)[i]
    
    # free memory
    cfree(asarray[FILEDB_DBT](dbkeys)[i].data)

  # Cleanup
  cfree(dbkeys)



proc allBinaryPairs*(filedb: ConfDataStoreDB): seq[tuple[key:string,val:string]] =
  ## Return all available key/value pairs to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.

  var 
    dbkeys: pointer
    dbvals: pointer
    num0:   cuint

  # Grab all keys & data in string form
  filedb_get_all_pairs(filedb.dbh, addr(dbkeys), addr(dbvals), addr(num0))
  let num = int(num0)

  # Hold the result
  newSeq[tuple[key:string,val:string]](result, num)

  # Loop over all the keys and deserialize them
  for i in 0..num-1:
    # put this new pair into the table
    result[i] = ($asarray[FILEDB_DBT](dbkeys)[i], $asarray[FILEDB_DBT](dbvals)[i])

    # free memory
    cfree(asarray[FILEDB_DBT](dbkeys)[i].data)
    cfree(asarray[FILEDB_DBT](dbvals)[i].data)

  # Cleanup
  cfree(dbkeys)
  cfree(dbvals)



proc allKeys*[K](filedb: ConfDataStoreDB): seq[K] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.
  # Grab all the binary keys
  let all_keys = allBinaryKeys(filedb)

  # Hold the result
  newSeq[K](result, all_keys.len)

  # Loop over all the keys and deserialize them
  for i in 0..all_keys.len-1:
    # convert into key object
    result[i] = deserializeBinary[K](all_keys[i])



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
  result = newString(len)
  var ret = filedb_get_user_info(filedb.dbh, addr(result[0]), addr(len))
  if ret != 0:
    quit("Error returning user meta-data from db")
  return result

