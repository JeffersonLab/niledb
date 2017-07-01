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
##      Pure File Based Hash Database - top level support
## 
## 
## 

## 
##  Still use the key data pair structure
## 

type
  FILEDB_DBT* {.importc: "FILEDB_DBT", header: "ffdb_header.h".} = object
    data* {.importc: "data".}: pointer ##  data
    size* {.importc: "size".}: cuint ##  data length in bytes
  

##  Access method description structure.

type
  FILEDB_DB* = pointer

## 
##  Structure used to pass parameters to the hashing routines. 
## 

type
  FILEDB_OPENINFO* {.importc: "FILEDB_OPENINFO", header: "ffdb_header.h".} = object
    bsize* {.importc: "bsize".}: cuint ##  bucket size
    nbuckets* {.importc: "nbuckets".}: cuint ##  number of buckets
    cachesize* {.importc: "cachesize".}: culong ##  bytes to cache
    rearrangepages* {.importc: "rearrangepages".}: cint ##  to rearrange page on open/close to save
                                                    ##  space
                                                    ## 
    userinfolen* {.importc: "userinfolen".}: cuint ##  how many bytes for user information
    numconfigs* {.importc: "numconfigs".}: cuint ##  number of configurations
  

## 
##  Open a database handle
##  @param fname database filename
##  @param flags database open flags
##  @param mode typical file onwership mode
##  @openinfo user supplied information for opening a database
##  @return a pointer to FILEDB_DB structure. return 0 if something wrong
## 

proc filedb_dbopen*(fname: cstring; flags: cint; mode: cint; openinfo: pointer): ptr FILEDB_DB {.
    importc: "filedb_dbopen", header: "ffdb_header.h".}
## 
##  Close a database handle
##  @param dbh database
## 

proc filedb_close*(dbh: ptr FILEDB_DB): cint {.importc: "filedb_close",
    header: "ffdb_header.h".}
## *
##  Set a paticular configuration information
##  
##  @param db pointer to underlying database
##  @param config a configuration structure to be set
## 
##  @return 0 on success. -1 on failure with a proper errno set
## 
## 
## extern int
## filedb_set_config(FILEDB_DB* db, filedb_config_info_t* config);
## 
## *
##  Get a paticular configuration information
## 
##  @param db pointer to underlying database
##  @param confignum the configuration number
##  @param config retrieved configuration information will be here
## 
##  @return 0 on success, -1 on failure with a proper errno set
## 
## 
## extern int
## filedb_get_config (const FILEDB_DB* db, unsigned int confignum,
## 		   filedb_config_info_t* config);   
## 
## *
##  Set all configurations
## 
##  @param db pointer to underlying database
##  @param configs all configuration information
## 
##  @return 0 on success -1 on failure with a proper errno set
## 
## 
## extern int
## filedb_set_all_configs(FILEDB_DB* db, filedb_all_config_info_t* configs);
## 
## *
##  Get all configurations
##  caller should free memory of configs->allconfigs
## 
##  @param db pointer to underlying database
##  @param configs all configuration information
## 
##  @return 0 on success -1 on failure with a proper errno set
## 
## 
## extern int
## filedb_get_all_configs(const FILEDB_DB* db, filedb_all_config_info_t* configs);
## 
## *
##  Get number of configurations information
## 
##  @param db pointer to underlying database
## 
##  @return number of configurations allocated
## 

proc filedb_num_configs*(db: ptr FILEDB_DB): cuint {.importc: "filedb_num_configs",
    header: "ffdb_header.h".}
## *
##  Set user information for the database
## 
##  @param db pointer to underlying database
##  @param data user data
##  @param len user data len
## 
##  @return 0 on success. -1 on failure with a proper errno
## 

proc filedb_set_user_info*(db: ptr FILEDB_DB; data: ptr cuchar; len: cuint): cint {.
    importc: "filedb_set_user_info", header: "ffdb_header.h".}
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

proc filedb_get_user_info*(db: ptr FILEDB_DB; data: ptr cuchar; len: ptr cuint): cint {.
    importc: "filedb_get_user_info", header: "ffdb_header.h".}
## *
##  Get maximum user information length in bytes allocated
## 
##  @param db pointer to underlying database
##  @return number of bytes allocated for user information
## 

proc filedb_max_user_info_len*(db: ptr FILEDB_DB): cuint {.
    importc: "filedb_max_user_info_len", header: "ffdb_header.h".}
## 
##  A routine which reset the database handle under panic mode
## 

proc filedb_dbpanic*(dbp: ptr FILEDB_DB) {.importc: "filedb_dbpanic",
                                       header: "ffdb_header.h".}
## *
##  Return all keys to vectors in binary form of strings
## 

proc filedb_get_all_keys*(dbhh: ptr FILEDB_DB; keyss: pointer; num: ptr cuint) {.
    importc: "filedb_get_all_keys", header: "ffdb_header.h".}
## *
##  Return all keys & data to vectors in binary form of strings
## 

proc filedb_get_all_pairs*(dbhh: ptr FILEDB_DB; keyss: pointer; valss: pointer;
                          num: ptr cuint) {.importc: "filedb_get_all_pairs",
    header: "ffdb_header.h".}
## *
##  get key and data pair from a database pointed by pointer dbh
## 
##  @param dbh database pointer
##  @key key associated with this data. This key must be string form
##  @data data to be stored into the database. It is in string form
## 
##  @return 0 on success. Otherwise failure
## 

proc filedb_get_data*(dbh: ptr FILEDB_DB; key: ptr FILEDB_DBT; data: ptr FILEDB_DBT): cint {.
    importc: "filedb_get_data", header: "ffdb_header.h".}
## *
##  Insert key and data pair in string format into the database
## 
##  @param dbh database pointer
##  @key key associated with this data. This key must be string form
##  @data data to be stored into the database. It is in string form
## 
##  @return 0 on success. Otherwise failure
## 

proc filedb_insert_data*(dbh: ptr FILEDB_DB; key: ptr FILEDB_DBT; data: ptr FILEDB_DBT): cint {.
    importc: "filedb_insert_data", header: "ffdb_header.h".}