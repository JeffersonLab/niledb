## A fast file-hash DB. The interface is Key/Value pair
## semantics. Storage of these pairs is into strings, and uses an
## underlying `filehash` package implemented over a Berkeley Sleepy Cat
## file-hash database. A single integer index is provided to allow the
## grouping of the values from many DB's but with a single key.
## 
## The `filehash` DB provides page-level checksums and supports caching
## of pages for fast retrievals and storage. Multi-threading reading is
## supported. The DB scales well, an in production, has been used to hold
## up to 80GB single files with O(100K) keys.
## 
## The [serializetools](https://github.com/JeffersonLab/serializetools) module provides 
## tools for serialization and deserialization of keys and values to/from strings.
## 


import niledb/private/ffdb_header
include niledb/private/niledb_internal
import tables, os
import 
  serializetools/serializebin, serializetools/serialstring

# Pass these in at the top level, thus getting easy access to the base path
# It would be cleaner to push them into ffdb_header since that is where the
# "C" calls are invoked
# Surely there is a cleaner way to get these paths at compile time? 
# NOTE: instantationInfo only works within templates
from strutils import strip

#{.passC: "-I" & strip(staticExec("nimble path niledb")) & "/filehash" .}
#{.passL: strip(staticExec("nimble path niledb")) & "/filehash/libfilehash.a" .}

{.passC: "-I" & strip(staticExec("pwd")) & "/filehash" .}
{.passL: strip(staticExec("pwd")) & "/filehash/libfilehash.a" .}


## Main type
type
  ConfDataStoreDB* = object
    filename:  string           ## database name
    options:   FILEDB_OPENINFO  ## all open options
    dbh:       ptr FILEDB_DB    ## opened database handle


proc newConfDataStoreDB*(): ConfDataStoreDB =
  ## Empty constructor for a single configurations data store
  result.options = newDataStoreDB()
  #  the other elements will be arranged by file hash package
  

proc setCacheSize*(filedb: var ConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in bytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  setCacheSize(filedb.options, size)


proc setCacheSizeMB*(filedb: var ConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in megabytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  setCacheSizeMB(filedb.options, size)

  
proc setPageSize*(filedb: var ConfDataStoreDB; size: cuint) =
  ## Page size used when a new data based is created
  ## This only effects a new database
  ##
  ## @param pagesize the pagesize used in hash database. This value
  ## should be power of 2. The minimum value is 512 and maximum value
  ## is 262144
  setPageSize(filedb.options, size)


proc setNumberBuckets*(filedb: var ConfDataStoreDB; num: cuint) =
  ## Set initial number of buckets
  ##
  ## This should be called before the open is called
  ##
  ## @param num the number of buckets should be used
  setNumberBuckets(filedb.options, num)


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


proc open*(filedb: var ConfDataStoreDB; file: string; open_flags: cint; mode: cint): int =
  ## ``file``: open filename holding all data and keys.
  ## ``open_flags``: can be regular UNIX file open flags such as: O_RDONLY, O_RDWR, O_TRUNC
  ## ``mode`` regular unix file mode
  ##
  ## Return 0 on success, -1 on failure with proper errno set
  # Check if te file is zero-size, if so, remove it.
  # Zero-size files causes problems filehash with the
  if fileExists(file):
    if getFileSize(file) == 0:
      removeFile(file)

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

  # Convert data into binary form
  var dataObj = serializeBinary(data)

  # now it is time to insert
  let ret = insertBinary(filedb.dbh, keyObj, dataObj)
  return ret


proc insert*[K,D](filedb: var ConfDataStoreDB; kv: Table[K,D]): int =
  ## Insert a table of key/value pairs `kv` into the database
  result = 0
  for k,v in pairs(kv):
    let ret = filedb.insert(k,v)
    if ret != 0: return ret


proc getBinary*(filedb: ConfDataStoreDB; key: string; data: var string): int =
  ## Get `data` for a given `key`
  ## return 0 on success, otherwise the key not found
  # Convert key to a string
  var keyObj: string
  shallowCopy(keyObj, key)

  # Output
  return getBinary(filedb.dbh, keyObj, data)


proc get*[K,D](filedb: ConfDataStoreDB; key: K; data: var D): int =
  ## Get `data` for a given `key`
  ## return 0 on success, otherwise the key not found
  # Convert key to a string
  var keyObj = serializeBinary(key)

  # Output
  var dataObj: string
  let ret = getBinary(filedb.dbh, keyObj, dataObj)
  if ret == 0:
    # convert object into a string
    data = deserializeBinary[D](dataObj)

  return int(ret)


proc `[]`*[K](filedb: ConfDataStoreDB; key: K): string =
  ## Get the representative string of data for a given `key`
  return filedb.dbh[key]


proc exist*[K](filedb: ConfDataStoreDB; key: K): bool =
  ## Does the `key` exist in the DB
  ## @param key a key object
  ## @return true if the answer is yes
  return exist[K](filedb.dbh, key)


proc allBinaryKeys*(filedb: ConfDataStoreDB): seq[string] =
  ## Returns all available keys to user
  return allBinaryKeys(filedb.dbh)


proc allBinaryPairs*(filedb: ConfDataStoreDB): seq[tuple[key:string,val:string]] =
  ## Return a sequence of tuples of all available key/value pairs
  return allBinaryPairs(filedb.dbh)


proc allKeys*[K](filedb: ConfDataStoreDB): seq[K] =
  ## Return all available keys to user
  return allKeys[K](filedb.dbh)


proc allPairs*[K,D](filedb: ConfDataStoreDB): Table[K,D] =
  ## Return a table of all pairs of keys and values
  let all_pairs = allBinaryPairs(filedb.dbh)
    
  result = initTable[K,D](rightSize(all_pairs.len))

  # Loop over all the keys and deserialize them
  for i in 0..all_pairs.len-1:
    result[deserializeBinary[K](all_pairs[i].key)] = deserializeBinary[D](all_pairs[i].val)


#[
proc flush*(filedb: var ConfDataStoreDB) =
  ## Flush database in memory to disk
  discard filedb.dbh.sync(filedb.dbh, 0)
]#


proc storageName*(filedb: ConfDataStoreDB): string {.noSideEffect.} =
  ## Return name of database associated with this Data store
  return filedb.filename


proc insertUserdata*(filedb: var ConfDataStoreDB; user_data: string): int =
  ## Insert user data into the metadata database
  ##
  ## @param user_data user supplied data
  ## @return returns 0 if success, else failure
  return insertUserdata(filedb.dbh, user_data)


proc getUserdata*(filedb: ConfDataStoreDB): string =
  ## Get user user data from the metadata database
  ##
  ## @param user_data user supplied buffer to store user data
  ## @return returns user supplied buffer if success. Otherwise failure. 
  return getUserdata(filedb.dbh)




#------------------------------------------------------------------
## Main type support multi-configurations
type
  Filedb_all_config_info_t* = object
    index:     int                            ## configuration number
    fname:     string                         ## filename of single-config


  AllConfDataStoreDB* = object
    nbins:     int                            ## number of configurations
    bytesize:  int                            ## byte size of each element of a configuration
    empty:     bool                           ## is db initialized?
    filename:  string                         ## database name
    allcfgs:   seq[string]                    ## info on the configs in use
    options:   FILEDB_OPENINFO                ## all open options
    dbh:       ptr FILEDB_DB                  ## opened database handle


proc newAllConfDataStoreDB*(): AllConfDataStoreDB =
  ## Empty constructor for a multi-configuration data store
  result.options = newDataStoreDB()
  result.empty = true
  result.nbins = 0
  result.bytesize = 0
  #  the other elements will be arranged by file hash package
  

proc newAllConfDataStoreDB*(num: int): AllConfDataStoreDB =
  ## Constructor from some number of configurations
  result.options = newDataStoreDB()
  result.empty = true
  result.nbins = num
  result.bytesize = 0
  #result.allcfgs = newSeq[Filedb_all_config_info_t](num)
  

proc setCacheSize*(filedb: var AllConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in bytes
  ##
  ## This should be called before the open is called
  ## ``max_cache_size`` number of bytes of data and keys should be kept
  ## in memory
  setCacheSize(filedb.options, size)


proc setCacheSizeMB*(filedb: var AllConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in megabytes
  ##
  ## This should be called before the open is called
  ## ``max_cache_size`` number of bytes of data and keys should be kept
  ## in memory
  setCacheSizeMB(filedb.options, size)

  
proc setPageSize*(filedb: var AllConfDataStoreDB; size: cuint) =
  ## Page size used when a new data based is created
  ## This only effects a new database
  ##
  ## ``pagesize`` the pagesize used in hash database. This value
  ## should be power of 2. The minimum value is 512 and maximum value
  ## is 262144
  setPageSize(filedb.options, size)


proc setNumberBuckets*(filedb: var AllConfDataStoreDB; num: cuint) =
  ## Set initial number of buckets
  ##
  ## This should be called before the open is called
  ##
  ## ``num`` the number of buckets should be used
  setNumberBuckets(filedb.options, num)


proc enablePageMove*(filedb: var AllConfDataStoreDB) =
  ## Set whether to move pages when close to save disk space
  ##
  ## This only effective on writable database
  filedb.options.rearrangepages = 1


proc disablePageMove*(filedb: var AllConfDataStoreDB) =
  filedb.options.rearrangepages = 0


proc setMaxUserInfoLen*(filedb: var AllConfDataStoreDB; len: int) =
  ## Set and get maximum user information length
  filedb.options.userinfolen = cuint(len)
  ##  account for possible null terminator on string

  
proc getMaxUserInfoLen*(filedb: AllConfDataStoreDB): int {.noSideEffect.} =
  if filedb.dbh == nil: 
    return int(filedb.options.userinfolen)
  return int(filedb_max_user_info_len(filedb.dbh))


proc setMaxNumberConfigs*(filedb: var AllConfDataStoreDB; num: int) =
  ## Set and get maximum number of configurations
  filedb.nbins = num
  filedb.options.numconfigs = cuint(num)


proc getMaxNumberConfigs*(filedb: AllConfDataStoreDB): int {.noSideEffect.} =
  if filedb.dbh == nil: 
    return int(filedb.options.numconfigs)
  return int(filedb_get_num_configs(filedb.dbh))


proc open*(filedb: var AllConfDataStoreDB; file: string; open_flags: cint; mode: cint): int =
  ## Open
  ## ``file`` filename holding all data and keys
  ## ``open_flags``: can be regular UNIX file open flags such as: O_RDONLY, O_RDWR, O_TRUNC
  ## ``mode`` regular unix file mode
  ##
  ## Return 0 on success, -1 on failure with proper errno set
  # Remove an empty file. Otherwise, filehash has problems.
  filedb.empty = false
  if fileExists(file):
    if getFileSize(file) == 0:
      removeFile(file)
      filedb.empty = true
  else:
    filedb.empty = true

  # open the file
  var foo: cstring = file
  filedb.filename = file
  filedb.dbh = filedb_dbopen(foo, open_flags, mode, addr(filedb.options))
  if filedb.dbh == nil: return -1

  # check if DB is empty
  if not filedb.empty:
    filedb.empty = isDBEmpty(filedb.dbh)

  # Okay, most definitely confirmed empty or not
  if filedb.empty:
    if filedb.nbins == 0:
      echo "One has to set the number of configurations before opening an empty DB"
      return -1

    # set num configs
    if filedb.allcfgs.len == 0:
      # The config names are not set, so go for a generic set
      if filedb_set_num_configs(filedb.dbh, cuint(filedb.nbins)) != 0:
        quit("Error setting num configs")
    else:
      # The config names are set, so use them
      if filedb.nbins != filedb.allcfgs.len:
        quit("Ooops, the number of filename names in allcfgs does not match the set val = " & $filedb.nbins)
      # Have to use a C-array
      var ffs = allocCStringArray(filedb.allcfgs)
      if filedb_set_all_configs(filedb.dbh, ffs, cuint(filedb.nbins)) != 0:
        quit("Error setting all configs")
      deallocCStringArray(ffs)
  else:
    # Read and possibly check the number of configs
    let nfound = int(filedb_get_num_configs(filedb.dbh))
    if filedb.nbins == 0:
      filedb.nbins = nfound
    else:
      if nfound != filedb.nbins:
        quit("Number of configs in EDB= " & $nfound & " does not agree the desired val= " & $filedb.nbins)

  return 0


proc close*(filedb: var AllConfDataStoreDB): cint =
  ## Close a databaseZA
  return filedb_close(filedb.dbh)
  

proc insert*[K,D](filedb: var AllConfDataStoreDB; key: K; data: seq[D]): int =
  ## Insert a pair of data and key into the database
  ## ``key`` a key
  ## ``data`` a user provided data
  ## Return 0 on successful write, -1 on failure with proper errno set
  # Sanity checks
  if data.len != filedb.nbins:
    quit("Insert: number of data elements= " & $data.len & "  not same as nbins= " & $filedb.nbins)

  # create key
  var keyObj = serializeBinary(key)
          
  # Data to insert
  var dstr: string = serializeBinary(data[0])

  # Set bytesize if not already set
  if filedb.bytesize == 0:
    filedb.bytesize = dstr.len
 
  # Convert data into binary form
  for i in 1..filedb.nbins-1:
    dstr.add(serializeBinary(data[i]))

  # now it is time to insert
  let ret = insertBinary(filedb.dbh, keyObj, dstr)
  return ret


proc insert*[K,D](filedb: var AllConfDataStoreDB; kv: Table[K,seq[D]]): int =
  ## Insert a table of key/value pairs ``kv`` into the database
  result = 0
  for k,v in pairs(kv):
    let ret = filedb.insert(k,v)
    if ret != 0: return ret


proc get*[K,D](filedb: var AllConfDataStoreDB; key: K; data: var seq[D]): int =
  ## Get data for a given key
  ## ``key`` user supplied key
  ## ``data`` after the call data will be populated
  ## Return 0 on success, otherwise the key not found
  # Create key
  var keyObj = serializeBinary(key)

  # Output
  var dataObj: string

  # now retrieve data from database
  let ret = getBinary(filedb.dbh, keyObj, dataObj)
  if ret != 0: return ret

  # Check
  if (dataObj.len mod filedb.nbins) != 0:
    echo "Get: data size not multiple of num configs"
    return -1

  if filedb.bytesize == 0:
    filedb.bytesize = dataObj.len div filedb.nbins

  if dataObj.len != filedb.bytesize * filedb.nbins:
    echo "Get: bytesize of data not compatible with a previous read from this DB"
    return -1

  # Carve up this data into nbin chunks
  newSeq[D](data, filedb.nbins)

  # work var
  var dbd = newString(filedb.bytesize)

  var nb = 0
  for n in 0..filedb.nbins-1:
    # each substring is turned back into data
    copyMem(addr(dbd[0]), addr(dataObj[nb]), filedb.bytesize)
    data[n] = deserializeBinary[D](dbd)
    nb += filedb.bytesize

  # I have to use free since I use malloc in c code
  return 0



proc `[]`*[K](filedb: AllConfDataStoreDB; key: K): string =
  ## Get data for a given key
  ## @param key user supplied key
  ## @return data on success, otherwise abort
  return filedb.dbh[key]


proc exist*[K](filedb: AllConfDataStoreDB; key: K): bool =
  ## Does this key exist in the store
  ## @param key a key object
  ## @return true if the answer is yes
  echo "In allconf exist: key= ", key
  return exist[K](filedb.dbh, key)


proc allBinaryKeys*(filedb: AllConfDataStoreDB): seq[string] =
  ## Return all available keys to user
  ## ``keys`` user suppled an empty vector which is populated
  ## by keys after this call.
  return allBinaryKeys(filedb.dbh)


proc allBinaryPairs*(filedb: AllConfDataStoreDB): seq[tuple[key:string,val:string]] =
  ## Return all available key/value pairs to user
  ## ``keys`` user suppled an empty vector which is populated
  ## by keys after this call.
  return allBinaryPairs(filedb.dbh)


proc allKeys*[K](filedb: AllConfDataStoreDB): seq[K] =
  ## Return all available keys to user
  ## ``keys`` user suppled an empty vector which is populated
  ## by keys after this call.
  # Grab all the binary keys
  return allKeys[K](filedb.dbh)


proc allPairs*[K,D](filedb: var AllConfDataStoreDB): Table[K,seq[D]] =
  ## Return all pairs of keys and values in a table
  ## NOTE: expects the data payload (the seq[D]) to be the same
  ## size for each configuration
  var all_pairs = allBinaryPairs(filedb)
    
  # Check
  if filedb.nbins == 0:
    quit("AllConf not initialized with number of configs")

  # Carve up this data into nbin chunks
  result = initTable[K,seq[D]](rightSize(all_pairs.len))

  # Loop over all the pairs and deserialize them
  var nn = 0
  for dd in mitems(all_pairs):
    if (dd.val.len mod filedb.nbins) != 0:
      quit("Get: data size not multiple of num configs")

    # If first time through, we may reset the bytesize
    if filedb.bytesize == 0:
      let bsize = dd.val.len div filedb.nbins
      filedb.bytesize = bsize

    # Split up the val-string into nbin chunks
    var data = newSeq[D](filedb.nbins)

    for n in 0..filedb.nbins-1:
      # convert object into a string and deserialize it
      var dbd = newString(filedb.bytesize)
      copyMem(addr(dbd[0]), addr(dd.val[n*filedb.bytesize]), filedb.bytesize)
      data[n] = deserializeBinary[D]($dbd)

    # Deserialize the key
    result[deserializeBinary[K](dd.key)] = data
    inc(nn)


#[
proc flush*(filedb: var AllConfDataStoreDB) =
  ## Flush database in memory to disk
  discard filedb.dbh.sync(filedb.dbh, 0)
]#


proc storageName*(filedb: AllConfDataStoreDB): string {.noSideEffect.} =
  ## Name of database associated with this Data store
  ##
  ## @return database name
  return filedb.filename


proc insertUserdata*(filedb: var AllConfDataStoreDB; user_data: string): int =
  ## Insert user data into the  metadata database
  ##
  ## @param user_data user supplied data
  ## @return returns 0 if success, else failure
  return insertUserdata(filedb.dbh, user_data)


proc getUserdata*(filedb: AllConfDataStoreDB): string =
  ## Get user user data from the metadata database
  ##
  ## @param user_data user supplied buffer to store user data
  ## @return returns user supplied buffer if success. Otherwise failure. 
  return getUserdata(filedb.dbh)

