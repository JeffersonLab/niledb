##  Class for storing keys and corresponding vector of objects from all configurations

import niledb/private/ffdb_header
import tables
import 
  serializetools/serializebin, serializetools/serialstring

from strutils import toHex  # used for printBin

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


proc printBin(x:string): string =
  ## Print a binary string
  result = "0x"
  for e in items(x):
    result.add(toHex(e))


proc newDataStoreDB(): FILEDB_OPENINFO =
  zeroMem(addr(result), sizeof((FILEDB_OPENINFO)))
  result.bsize = FILEDB_DEFAULT_PAGESIZE
  result.nbuckets = FILEDB_DEFAULT_NUM_BUCKETS
  #  the other elements will be arranged by file hash package


proc setCacheSize(options: var FILEDB_OPENINFO; size: cuint) =
  ## How much data and keys should be kept in memory in bytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  options.cachesize = size

proc setCacheSizeMB(options: var FILEDB_OPENINFO; size: cuint) =
  ## How much data and keys should be kept in memory in megabytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  if sizeof(culong) == sizeof((cuint)):
    quit("Cannot handle a 32-bit machine")
  else:
    options.cachesize = (cast[culong](size)) shl 20
  
proc setPageSize(options: var FILEDB_OPENINFO; size: cuint) =
  ## Page size used when a new data based is created
  ## This only effects a new database
  ##
  ## @param pagesize the pagesize used in hash database. This value
  ## should be power of 2. The minimum value is 512 and maximum value
  ## is 262144
  options.bsize = size

proc setNumberBuckets(options: var FILEDB_OPENINFO; num: cuint) =
  ## Set initial number of buckets
  ##
  ## This should be called before the open is called
  ##
  ## @param num the number of buckets should be used
  options.nbuckets = num

proc enablePageMove(options: var FILEDB_OPENINFO) =
  ## Set whether to move pages when close to save disk space
  ##
  ## This only effective on writable database
  options.rearrangepages = 1

proc disablePageMove(options: var FILEDB_OPENINFO) =
  options.rearrangepages = 0


proc setMaxUserInfoLen(options: var FILEDB_OPENINFO; len: int) =
  ## Set and get maximum user information length
  options.userinfolen = cuint(len)
  

proc setMaxNumberConfigs(options: var FILEDB_OPENINFO; num: cuint) =
  ## Set and get maximum number of configurations
  options.numconfigs = num


proc isDBEmpty(dbh: ptr FILEDB_DB): bool =
  ## Check if a DB is empty
  if filedb_is_db_empty(dbh) != 0:
    return true
  else:
    return false


#[
proc splitDataString(dstr: string; nbins, bytesize: int; data: var seq[string]): int =
  ## Given a string `dstr`, chop it up into `nbins` strings of size `bytesize`
  ## Return 0 on success, otherwise some error with parsing the string into bins
  var keyObj = serializeBinary(key)

  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT

  # now retrieve data from database
  let ret = filedb_get_data(filedb.dbh, addr(dbkey), addr(dbdata))
  if ret != 0: return int(ret)

  # Check
  if (int(dbdata.size) mod filedb.nbins) != 0:
    echo "Get: data size not multiple of num configs"
    return -1

  if filedb.bytesize == 0:
    filedb.bytesize = int(dbdata.size) / filedb.nbins

  if int(dbdata.size) != filedb.bytesize * filedb.nbins:
    echo "Get: bytesize of data not compatible with a previous read from this DB"
    return -1

  # Carve up this data into nbin chunks
  newSeq[D](data, filedb.nbins)

  for n in 0..filedb.nbins-1:
    # convert object into a string
    var dbd = FILEDB_DBT(data: addr(dbdata.data[n*filedb.bytesize]), size: cuint(filedb.bytesize))
    data[n] = deserializeBinary[D]($dbd)

  # I have to use free since I use malloc in c code
  cfree(dbdata.data)
  return 0
]#


proc insertBinary(dbh: ptr FILEDB_DB; keyObj: var string; dataObj: var string): int =
  ## Insert a pair of data and key into the database
  ## @param key a key
  ## @param data a user provided data
  ##
  ## @return 0 on successful write, -1 on failure with proper errno set
  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create DBt object
  var dbdata = FILEDB_DBT(data: addr(dataObj[0]), size: cuint(dataObj.len))

  # now it is time to insert
  let ret = filedb_insert_data(dbh, addr(dbkey), addr(dbdata))
  return int(ret)


proc getBinary(dbh: ptr FILEDB_DB; keyObj: var string; data: var string): int =
  ## Get binary `data` for a given binary `keyObj`
  ## return 0 on success, otherwise the key not found
  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create and empty dbt data object
  var dbdata: FILEDB_DBT

  # now retrieve data from database
  let ret = filedb_get_data(dbh, addr(dbkey), addr(dbdata))
  if ret == 0:
    # convert object into a string
    data = $dbdata
    # I have to use free since I use malloc in c code
    cfree(dbdata.data)

  return int(ret)


proc `[]`[K](dbh: ptr FILEDB_DB; key: K): string =
  ## Get data for a given key
  ## @param key user supplied key
  ## @return data on success, otherwise abort
  result = ""
  var keyObj = serializeBinary(key)

  # Get
  let ret = getBinary(dbh, keyObj, result)
  if ret != 0:
    quit("Error retrieving key = " & $key)


proc exist[K](dbh: ptr FILEDB_DB; key: K): bool =
  ## Does this key exist in the store
  ## @param key a key object
  ## @return true if the answer is yes
  echo "In exist: key= ", key
  var keyObj = serializeBinary(key)

  # create key
  var dbkey = FILEDB_DBT(data: addr(keyObj[0]), size: cuint(keyObj.len))
          
  # create DBt object
  var dbdata: FILEDB_DBT

  # now retrieve data from database
  let ret = filedb_get_data(dbh, addr(dbkey), addr(dbdata))
  if ret == 0:
    cfree(dbdata.data)
    result = true
  else:
    result = false


proc allBinaryKeys(dbh: ptr FILEDB_DB): seq[string] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.

  var 
    dbkeys: pointer
    num0:   cuint
    
  # Grab all keys in string form
  filedb_get_all_keys(dbh, addr(dbkeys), addr(num0))
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


proc allBinaryPairs(dbh: ptr FILEDB_DB): seq[tuple[key:string,val:string]] =
  ## Return all available key/value pairs to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.

  var 
    dbkeys: pointer
    dbvals: pointer
    num0:   cuint

  # Grab all keys & data in string form
  filedb_get_all_pairs(dbh, addr(dbkeys), addr(dbvals), addr(num0))
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


proc allKeys[K](dbh: ptr FILEDB_DB): seq[K] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.
  # Grab all the binary keys
  let all_keys = allBinaryKeys(dbh)

  # Hold the result
  newSeq[K](result, all_keys.len)

  # Loop over all the keys and deserialize them
  for i in 0..all_keys.len-1:
    # convert into key object
    result[i] = deserializeBinary[K](all_keys[i])


proc insertUserdata(dbh: ptr FILEDB_DB; user_data: string): int =
  ## Insert user data into the  metadata database
  ##
  ## @param user_data user supplied data
  ## @return returns 0 if success, else failure
  var dd: cstring
  shallowCopy(dd, user_data)
  return filedb_set_user_info(dbh, cast[ptr cuchar](addr(dd[0])), cuint(user_data.len))


proc getUserdata(dbh: ptr FILEDB_DB): string =
  ## Get user user data from the metadata database
  ##
  ## @param user_data user supplied buffer to store user data
  ## @return returns user supplied buffer if success. Otherwise failure. 
  var len: cuint = filedb_max_user_info_len(dbh)
  result = newString(len)
  var ret = filedb_get_user_info(dbh, addr(result[0]), addr(len))
  if ret != 0:
    quit("Error returning user meta-data from db")
  return result


