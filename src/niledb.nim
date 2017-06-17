##   Class for storing keys and corresponding vector of objects from
##     all configurations

import 
  serializetools/serializebin, serializetools/crc32,
  ffdb_db


const
  FILEDB_DEFAULT_PAGESIZE = 8192
  FILEDB_DEFAULT_NUM_BUCKETS = 32


type
  ConfDataStoreDB* = object
    filename:  string           ## database name
    options:   FFDB_HASHINFO    ## all open options
    dbh:       ptr FFDB_DB      ## opened database handle


proc newConfDataStoreDB*(): ConfDataStoreDB =
  ## Empty constructor for a data store for one configuration
  memset(addr(result.options), 0, sizeof((FFDB_HASHINFO)))
  result.options.bsize = FILEDB_DEFAULT_PAGESIZE
  result.options.nbuckets = FILEDB_DEFAULT_NUM_BUCKETS
  #  the other elements will be arranged by file hash package
  
proc setCacheSize*(filedb: var ConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in bytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  filedb.options_.cachesize = size

proc setCacheSizeMB*(filedb: var ConfDataStoreDB; size: cuint) =
  ## How much data and keys should be kept in memory in megabytes
  ##
  ## This should be called before the open is called
  ## @param max_cache_size number of bytes of data and keys should be kept
  ## in memory
  if sizeof(culong) == sizeof((int)):
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
    filedb.options_.cachesize = tsize
  else:
    filedb.options_.cachesize = (cast[culong](size)) shl 20
  
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

proc setMaxUserInfoLen*(this: var ConfDataStoreDB; len: cuint) =
  ## Set and get maximum user information length
  filedb.options.userinfolen = len + 1
  ##  account for possible null terminator on string
  
proc getMaxUserInfoLen*(this: ConfDataStoreDB): cuint {.noSideEffect.} =
  if not dbh: return filedb.options.userinfolen
  return ffdb_max_user_info_len(dbh)

proc setMaxNumberConfigs*(this: var ConfDataStoreDB; num: cuint) =
  ## Set and get maximum number of configurations
  filedb.options.numconfigs = num

proc getMaxNumberConfigs*(this: ConfDataStoreDB): cuint {.noSideEffect.} =
  if not dbh: return filedb.options.numconfigs
  return ffdb_num_configs(dbh)

proc open*(filedb: var ConfDataStoreDB; file: string; open_flags: cint; mode: cint): cint =
  ## Open
  ## @param ``file`` filename holding all data and keys
  ## @param ``open_flags``: can be regular UNIX file open flags such as: O_RDONLY, O_RDWR, O_TRUNC
  ## @param mode regular unix file mode
  ##
  ## @return 0 on success, -1 on failure with proper errno set
  filedb.dbh = openDatabase[K](file, open_flags, mode, addr(filedb.options))
  if not filedb.dbh: return - 1
  return 0

proc close*(filedb: var ConfDataStoreDB): cint =
  var ret: cint = 0
  if filedb.dbh:
    ret = filedb.dbh.close(filedb.dbh)
    filedb.dbh = 0
  return ret
  
proc insert*(filedb: var ConfDataStoreDB; key: K; data: D): cint =
  ## Insert a pair of data and key into the database
  ## data is not ensemble, but a vector of complex.
  ## @param key a key
  ## @param data a user provided data
  ##
  ## @return 0 on successful write, -1 on failure with proper errno set
  var ret: cint = 0
  ##       try {
  ret = insertData(dbh, key, data)
  ##       }
  ##       catch (SerializeException& e) {
  ## 	std::cerr << "ConfDataStoreDB insert error: " << e.what() << std::endl;
  ## 	ret = -1;
  ##       }
  return ret

proc get*(filedb: var ConfDataStoreDB; key: K; data: var D): cint =
  ## Get data for a given key
  ## @param key user supplied key
  ## @param data after the call data will be populated
  ## @return 0 on success, otherwise the key not found
  var ret: cint = 0
  ##       try {
  ret = getData(dbh, key, data)
  ##       }
  ##       catch (SerializeException& e) {
  ## 	std::cerr << "ConfDataStoreDB get error: " << e.what () << std::endl;
  ## 	ret = -1;
  ##       }
  return ret

proc exist*(filedb: var ConfDataStoreDB; key: K): bool =
  ## Does this key exist in the store
  ## @param key a key object
  ## @return true if the answer is yes
  var ret: cint
  ##       try {
  ret = keyExist[K](dbh, key)
  ##       }
  ##       catch (SerializeException& e) {
  ## 	std::cerr << "Key check exist error: " << e.what () << std::endl;
  ## 	ret = 0;
  ##       }
  return ret

proc keys*[K](filedb: ConfDataStoreDB) : seq[K] =
  ## Return all available keys to user
  ## @param keys user suppled an empty vector which is populated
  ## by keys after this call.
  return allKeys(filedb.dbh, keys)

proc keysAndData*[K,D](filedb: ConfDataStoreDB): seq[tuple[K,D] =
  ## ; keys: var vector[K]; values: var vector[D]) =
  ## Return all pairs of keys and data
  ## @param keys user supplied empty vector to hold all keys
  ## @param data user supplied empty vector to hold data
  ## @return keys and data in the vectors having the same size
  return allPairs(dbh, keys, values)

proc flush*(filedb: var ConfDataStoreDB) =
  ## Flush database in memory to disk
  flushDatabase(dbh)

proc storageName*(filedb: ConfDataStoreDB): string {.noSideEffect.} =
  ## Name of database associated with this Data store
  ##
  ## @return database name
  return filename

proc insertUserdata*(filedb: var ConfDataStoreDB; user_data: string): cint =
  ## Insert user data into the  metadata database
  ##
  ## @param user_data user supplied data
  ## @return returns 0 if success, else failure
  return ffdb_set_user_info(dbh, cast[ptr cuchar](user_data.c_str()),
                           user_data.length())

proc getUserdata*(filedb: var ConfDataStoreDB; user_data: var string): cint =
  ## Get user user data from the metadata database
  ##
  ## @param user_data user supplied buffer to store user data
  ## @return returns 0 if success. Otherwise failure.
  var ret: cint
  var len: cuint
  type
    TT = cuchar
  var data: ptr TT
  len = ffdb_max_user_info_len(dbh)
  data = new(TT[len])
  ret = ffdb_get_user_info(dbh, data, addr(len))
  if ret == 0:
    user_data.assign(cast[cstring](data), len)
  deleteArray(data)
  return ret


