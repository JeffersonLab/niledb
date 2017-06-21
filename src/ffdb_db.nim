## 
##  Copyright (C) <2008> Jefferson Science Associates, LLC
##                       Under U.S. DOE Contract No. DE-AC05-06OR23177
## 
##                       Thomas Jefferson National Accelerator Facility
## 
##                       Jefferson Lab
##                       Scientific Computing Group,
##                       12000 Jefferson Ave.,      
##                       Newport News, VA 23606 
## 
## 
##  This program is free software: you can redistribute it and/or modify
##  it under the terms of the GNU General Public License as published by
##  the Free Software Foundation, either version 3 of the License, or
##  (at your option) any later version.
## 
##  This program is distributed in the hope that it will be useful,
##  but WITHOUT ANY WARRANTY; without even the implied warranty of
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
##  GNU General Public License for more details.
## 
##  You should have received a copy of the GNU General Public License
##  along with this program.  If not, see <http://www.gnu.org/licenses/>.
## 
##  ----------------------------------------------------------------------------
##  Description:
##      Pure File Based Hash Database
## 
##  Author:
##      Jie Chen
##      Scientific Computing Group
##      Jefferson Lab
## 
##  Revision History:
##      $Log: ffdb_db.h,v $
##      Revision 1.3  2009-03-04 19:12:28  edwards
##      Renamed DB_HASH and __db to avoid name collisions with Berkeley DB.
## 
##      Revision 1.2  2009/03/02 23:58:21  chen
##      Change implementation on keys iterator which get keys only
## 
##      Revision 1.1  2009/02/20 20:44:47  chen
##      initial import
## 
## 
## 
## 

type
  pgno_t* = cuint
  indx_t* = cushort

## 
##  Typical return status
## 

const
  FFDB_ERROR* = - 1
  FFDB_SUCCESS* = 0
  FFDB_NOT_FOUND* = 1
  FFDB_SPECIAL* = 2

## 
## Little endian and big endien
## 

when not defined(BYTE_ORDER):
  const
    LITTLE_ENDIAN* = 1234
    BIG_ENDIAN* = 4321
## 
##  Some file open flags may not be available for some machines
## 

## 
##  Errno definition for invalid file type
## 

## 
##  We only have DB_HASH in this package
## 

type
  FFDB_DBTYPE* {.size: sizeof(cint).} = enum
    FFDB_HASH = 1


## 
##  Still use the key data pair structure
## 

type
  FFDB_DBT* {.importc: "FFDB_DBT", header: "ffdb_db.h".} = object
    data* {.importc: "data".}: pointer ##  data
    size* {.importc: "size".}: cuint ##  data length in bytes
  

## 
##  DB access method and cursor operation values.  Each value is an operation
##  code to which additional bit flags are added.
## 
##  Most are not used
## 

const
  FFDB_AFTER* = 1
  FFDB_APPEND* = 2
  FFDB_BEFORE* = 3
  FFDB_CONSUME* = 4
  FFDB_CONSUME_WAIT* = 5
  FFDB_CURRENT* = 6
  FFDB_FIRST* = 7
  FFDB_GET_BOTH* = 8
  FFDB_GET_BOTHC* = 9
  FFDB_GET_BOTH_RANGE* = 10
  FFDB_GET_RECNO* = 11
  FFDB_JOIN_ITEM* = 12
  FFDB_KEYFIRST* = 13
  FFDB_KEYLAST* = 14
  FFDB_LAST* = 15
  FFDB_NEXT* = 16
  FFDB_NEXT_DUP* = 17
  FFDB_NEXT_NODUP* = 18
  FFDB_NODUPDATA* = 19
  FFDB_NOOVERWRITE* = 20
  FFDB_NOSYNC* = 21
  FFDB_POSITION* = 22
  FFDB_PREV* = 23
  FFDB_PREV_DUP* = 24
  FFDB_PREV_NODUP* = 25
  FFDB_SET* = 26
  FFDB_SET_RANGE* = 27
  FFDB_SET_RECNO* = 28
  FFDB_UPDATE_SECONDARY* = 29
  FFDB_WRITECURSOR* = 30
  FFDB_WRITELOCK* = 31

## *
##  Two different cursor type: one traverse key the other traverse data
## 

const
  FFDB_KEY_CURSOR* = 0x00001001
  FFDB_DATA_CURSOR* = 0x00001004

## *
##  Forward decleration of cursor
## 

type
  ffdb_cursor_t* {.importc: "ffdb_cursor_t", header: "ffdb_db.h".} = object
    get* {.importc: "get".}: proc (c: ptr ffdb_cursor_t; key: ptr FFDB_DBT;
                               data: ptr FFDB_DBT; flags: cuint): cint ##  Get routine
                                                                 ##  If data is null (0), caller is not interested in data
    ##  Close this cursor
    close* {.importc: "close".}: proc (c: ptr ffdb_cursor_t): cint ##  type of this cursor
    `type`* {.importc: "type".}: cint ##  internal pointer
    internal* {.importc: "internal".}: pointer


##  Access method description structure.

type
  FFDB_DB* {.importc: "FFDB_DB", header: "ffdb_db.h".} = object
    `type`* {.importc: "type".}: FFDB_DBTYPE ##  Underlying db type.
    close* {.importc: "close".}: proc (a2: ptr FFDB_DB): cint
    del* {.importc: "del".}: proc (a2: ptr FFDB_DB; a3: ptr FFDB_DBT; a4: cuint): cint
    get* {.importc: "get".}: proc (a2: ptr FFDB_DB; a3: ptr FFDB_DBT; a4: ptr FFDB_DBT;
                               a5: cuint): cint
    put* {.importc: "put".}: proc (a2: ptr FFDB_DB; a3: ptr FFDB_DBT; a4: ptr FFDB_DBT;
                               a5: cuint): cint
    sync* {.importc: "sync".}: proc (a2: ptr FFDB_DB; a3: cuint): cint
    cursor* {.importc: "cursor".}: proc (a2: ptr FFDB_DB; a3: ptr ptr ffdb_cursor_t;
                                     `type`: cuint): cint
    internal* {.importc: "internal".}: pointer ##  Access method private.
    fd* {.importc: "fd".}: proc (a2: ptr FFDB_DB): cint


## 
##  Hash database magic number and version
## 

const
  FFDB_HASHMAGIC* = 0xCECE3434
  FFDB_HASHVERSION* = 5

## 
##  How do we store key and data on a page
##  1) key and data try to be on the primary page
##  2) key points to pageno and offset where data are
## 

const
  FFDB_STORE_EMBED* = 0x00FFDDEE
  FFDB_STORE_INDIRECT* = 0x00FF1100

## 
##  Structure used to pass parameters to the hashing routines. 
## 

type
  FFDB_HASHINFO* {.importc: "FFDB_HASHINFO", header: "ffdb_db.h".} = object
    bsize* {.importc: "bsize".}: cuint ##  bucket size
    nbuckets* {.importc: "nbuckets".}: cuint ##  number of buckets
    cachesize* {.importc: "cachesize".}: culong ##  bytes to cache
    rearrangepages* {.importc: "rearrangepages".}: cint ##  to rearrange page on open/close to save
                                                    ##  space
                                                    ## 
    userinfolen* {.importc: "userinfolen".}: cuint ##  how many bytes for user information
    numconfigs* {.importc: "numconfigs".}: cuint ##  number of configurations
    hash* {.importc: "hash".}: proc (a2: pointer; a3: cuint): cuint ##  hash function
                                                           ##  key compare func
    cmp* {.importc: "cmp".}: proc (a2: ptr FFDB_DBT; a3: ptr FFDB_DBT): cint


## 
##  Internal byte swapping code if we are using little endian
## 
## 
##  Little endian <==> big endian 32-bit swap macros.
## 	M_32_SWAP	swap a memory location
## 	P_32_SWAP	swap a referenced memory location
## 	P_32_COPY	swap from one location to another
## 

template M_32_SWAP*(a: untyped): void =
  var ttmp: cuint
  (cast[cstring](addr(a)))[0] = (cast[cstring](addr(ttmp)))[3]
  (cast[cstring](addr(a)))[1] = (cast[cstring](addr(ttmp)))[2]
  (cast[cstring](addr(a)))[2] = (cast[cstring](addr(ttmp)))[1]
  (cast[cstring](addr(a)))[3] = (cast[cstring](addr(ttmp)))[0]

template P_32_SWAP*(a: untyped): void =
  var ttmp: cuint
  (cast[cstring](a))[0] = (cast[cstring](addr(ttmp)))[3]
  (cast[cstring](a))[1] = (cast[cstring](addr(ttmp)))[2]
  (cast[cstring](a))[2] = (cast[cstring](addr(ttmp)))[1]
  (cast[cstring](a))[3] = (cast[cstring](addr(ttmp)))[0]

template P_32_COPY*(a, b: untyped): void =
  (cast[cstring](addr((b))))[0] = (cast[cstring](addr((a))))[3]
  (cast[cstring](addr((b))))[1] = (cast[cstring](addr((a))))[2]
  (cast[cstring](addr((b))))[2] = (cast[cstring](addr((a))))[1]
  (cast[cstring](addr((b))))[3] = (cast[cstring](addr((a))))[0]

## 
##  Little endian <==> big endian 16-bit swap macros.
## 	M_16_SWAP	swap a memory location
## 	P_16_SWAP	swap a referenced memory location
## 	P_16_COPY	swap from one location to another
## 

template M_16_SWAP*(a: untyped): void =
  var ttmp: cushort
  (cast[cstring](addr(a)))[0] = (cast[cstring](addr(ttmp)))[1]
  (cast[cstring](addr(a)))[1] = (cast[cstring](addr(ttmp)))[0]

template P_16_SWAP*(a: untyped): void =
  var ttmp: cushort
  (cast[cstring](a))[0] = (cast[cstring](addr(ttmp)))[1]
  (cast[cstring](a))[1] = (cast[cstring](addr(ttmp)))[0]

template P_16_COPY*(a, b: untyped): void =
  (cast[cstring](addr((b))))[0] = (cast[cstring](addr((a))))[1]
  (cast[cstring](addr((b))))[1] = (cast[cstring](addr((a))))[0]

const
  FFDB_DEFAULT_UINFO_LEN* = 4000

## *
##  The file contains user provided information right after
##  the header page
## 

type
  ffdb_user_info_t* {.importc: "ffdb_user_info_t", header: "ffdb_db.h".} = object
    len* {.importc: "len".}: cuint
    uinfo* {.importc: "uinfo".}: ptr cuchar


## *
##  The file contains configuration information right after the above
##  user information 
## 

const
  FFDB_MAX_FNAME* = 128

type
  ffdb_config_info_t* {.importc: "ffdb_config_info_t", header: "ffdb_db.h".} = object
    config* {.importc: "config".}: cint ##  configuration number
    index* {.importc: "index".}: cint ##  index into all configurations
    inserted* {.importc: "inserted".}: cint ##  configuration inserted
    `type`* {.importc: "type".}: cint ##  type of configuration (fixed)
    mtime* {.importc: "mtime".}: cint ##  modified time of this config
    fname* {.importc: "fname".}: array[FFDB_MAX_FNAME, char]


## *
##  All configuration information 
## 

type
  ffdb_all_config_info_t* {.importc: "ffdb_all_config_info_t", header: "ffdb_db.h".} = object
    numconfigs* {.importc: "numconfigs".}: cint
    allconfigs* {.importc: "allconfigs".}: ptr ffdb_config_info_t


## 
##  Open a database handle
##  @param fname database filename
##  @param flags database open flags
##  @param mode typical file onwership mode
##  @openinfo user supplied information for opening a database
##  @return a pointer to FFDB_DB structure. return 0 if something wrong
## 

proc ffdb_dbopen*(fname: cstring; flags: cint; mode: cint; openinfo: ptr FFDB_HASHINFO): ptr FFDB_DB {.
    importc: "ffdb_dbopen", header: "ffdb_db.h".}
## *
##  Set a paticular configuration information
##  
##  @param db pointer to underlying database
##  @param config a configuration structure to be set
## 
##  @return 0 on success. -1 on failure with a proper errno set
## 

proc ffdb_set_config*(db: ptr FFDB_DB; config: ptr ffdb_config_info_t): cint {.
    importc: "ffdb_set_config", header: "ffdb_db.h".}
## *
##  Get a paticular configuration information
## 
##  @param db pointer to underlying database
##  @param confignum the configuration number
##  @param config retrieved configuration information will be here
## 
##  @return 0 on success, -1 on failure with a proper errno set
## 

proc ffdb_get_config*(db: ptr FFDB_DB; confignum: cuint;
                     config: ptr ffdb_config_info_t): cint {.
    importc: "ffdb_get_config", header: "ffdb_db.h".}
## *
##  Set all configurations
## 
##  @param db pointer to underlying database
##  @param configs all configuration information
## 
##  @return 0 on success -1 on failure with a proper errno set
## 

proc ffdb_set_all_configs*(db: ptr FFDB_DB; configs: ptr ffdb_all_config_info_t): cint {.
    importc: "ffdb_set_all_configs", header: "ffdb_db.h".}
## *
##  Get all configurations
##  caller should free memory of configs->allconfigs
## 
##  @param db pointer to underlying database
##  @param configs all configuration information
## 
##  @return 0 on success -1 on failure with a proper errno set
## 

proc ffdb_get_all_configs*(db: ptr FFDB_DB; configs: ptr ffdb_all_config_info_t): cint {.
    importc: "ffdb_get_all_configs", header: "ffdb_db.h".}
## *
##  Get number of configurations information
## 
##  @param db pointer to underlying database
## 
##  @return number of configurations allocated
## 

proc ffdb_num_configs*(db: ptr FFDB_DB): cuint {.importc: "ffdb_num_configs",
    header: "ffdb_db.h".}
## *
##  Set user information for the database
## 
##  @param db pointer to underlying database
##  @param data user data
##  @param len user data len
## 
##  @return 0 on success. -1 on failure with a proper errno
## 

proc ffdb_set_user_info*(db: ptr FFDB_DB; data: ptr cuchar; len: cuint): cint {.
    importc: "ffdb_set_user_info", header: "ffdb_db.h".}
## *
##  Get user information for the database
## 
##  @param db pointer to underlying database
##  @param data user data
##  @param len user data len. Caller allocate space for data and pass 
##  initial data length. On return, the actual data length will be stored
##  in len.
## 
##  @return 0 on success. -1 on failure with a proper errno
##  
## 

proc ffdb_get_user_info*(db: ptr FFDB_DB; data: ptr cuchar; len: ptr cuint): cint {.
    importc: "ffdb_get_user_info", header: "ffdb_db.h".}
## *
##  Get maximum user information length in bytes allocated
## 
##  @param db pointer to underlying database
##  @return number of bytes allocated for user information
## 

proc ffdb_max_user_info_len*(db: ptr FFDB_DB): cuint {.
    importc: "ffdb_max_user_info_len", header: "ffdb_db.h".}
## 
##  A routine which reset the database handle under panic mode
## 

proc ffdb_dbpanic*(dbp: ptr FFDB_DB) {.importc: "ffdb_dbpanic", header: "ffdb_db.h".}
