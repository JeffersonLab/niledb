/*
 * Copyright (C) <2008> Jefferson Science Associates, LLC
 *                      Under U.S. DOE Contract No. DE-AC05-06OR23177
 *
 *                      Thomas Jefferson National Accelerator Facility
 *
 *                      Jefferson Lab
 *                      Scientific Computing Group,
 *                      12000 Jefferson Ave.,      
 *                      Newport News, VA 23606 
 *
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * ----------------------------------------------------------------------------
 * Description:
 *     Pure File Based Hash Database - top level support
 *
 *
 */
#ifndef _FFDB_HEADER_H
#define _FFDB_HEADER_H

/*
 * Still use the key data pair structure
 */
typedef struct {
  void *data;                          /* data                 */
  unsigned int size;                   /* data length in bytes */
} FILEDB_DBT;

/* All configuration info */
typedef void* FILEDB_ALL_CONFIG_INFO;

/* Access method description structure. */
typedef void* FILEDB_DB;

 
/*
 * Structure used to pass parameters to the hashing routines. 
 */
typedef struct {
  unsigned int	bsize;		 /* bucket size */
  unsigned int	nbuckets;	 /* number of buckets */
  unsigned long	cachesize;	 /* bytes to cache */
  int           rearrangepages;  /* to rearrange page on open/close to save
				  * space
				  */
  unsigned int   userinfolen;    /* how many bytes for user information */
  unsigned int   numconfigs;     /* number of configurations */
} FILEDB_OPENINFO;



#ifdef __cplusplus
extern "C"
{
#endif

/*
 * Open a database handle
 * @param fname database filename
 * @param flags database open flags
 * @param mode typical file onwership mode
 * @openinfo user supplied information for opening a database
 * @return a pointer to FILEDB_DB structure. return 0 if something wrong
 */
extern FILEDB_DB*
filedb_dbopen(const char* fname, int flags, int mode, const void* openinfo);


/*
 * Close a database handle
 * @param dbh database
 */
extern int
filedb_close(FILEDB_DB* dbh);


/**
 * Check whether this database is empty or not
 *
 */
extern int
filedb_is_db_empty(FILEDB_DB* dbhh);


/**
 * Set a paticular configuration information
 * 
 * @param db pointer to underlying database
 * @param config a configuration structure to be set
 *
 * @return 0 on success. -1 on failure with a proper errno set
 */
/*
extern int
filedb_set_config(FILEDB_DB* db, FILEDB_CONFIG_INFO* config);
*/

/**
 * Get a paticular configuration information
 *
 * @param db pointer to underlying database
 * @param confignum the configuration number
 * @param config retrieved configuration information will be here
 *
 * @return 0 on success, -1 on failure with a proper errno set
 */
/*
extern int
filedb_get_config (const FILEDB_DB* db, unsigned int confignum, FILEDB_CONFIG_INFO* config);   
*/

/**
 * Set all configurations
 *
 * @param db pointer to underlying database
 * @param nbin number of configs
 *
 * @return 0 on success -1 on failure with a proper errno set
 */
extern int
filedb_set_num_configs(FILEDB_DB* db, unsigned int nbin);


/**
 * Set all configurations
 *
 * @param db pointer to underlying database
 * @param configs array of filenames 
 * @param nbin number of configurations
 *
 * @return 0 on success -1 on failure with a proper errno set
 */
extern int
filedb_set_all_configs(FILEDB_DB* db, const char** configs, unsigned int nbin);


/**
 * Get all configurations
 * caller should free memory of configs->allconfigs
 *
 * @param db pointer to underlying database
 * @param configs all configuration information
 *
 * @return 0 on success -1 on failure with a proper errno set
 */
/*
extern int
filedb_get_all_configs(const FILEDB_DB* db, FILEDB_ALL_CONFIG_INFO* configs);
*/

/**
 * Get number of configurations information
 *
 * @param dbhh pointer to underlying database
 *
 * @return number of configurations allocated
 */
extern unsigned int
filedb_get_num_configs(const FILEDB_DB* dbhh);


/**
 * Set user information for the database
 *
 * @param db pointer to underlying database
 * @param data user data
 * @param len user data len
 *
 * @return 0 on success. -1 on failure with a proper errno
 */
extern int
filedb_set_user_info(FILEDB_DB* db, unsigned char* data, unsigned int len);


/**
 * Get user information for the database
 *
 * @param db pointer to underlying database
 * @param data user data
 * @param len user data len. Caller allocate space for data and pass 
 * initial data length. On return, the actual data length will be stored
 * in len.
 *
 * @return 0 on success. -1 on failure with a proper errno
 * 
 */
extern int
filedb_get_user_info(const FILEDB_DB* db, unsigned char data[], unsigned int* len);


/**
 * Get maximum user information length in bytes allocated
 *
 * @param db pointer to underlying database
 * @return number of bytes allocated for user information
 */
extern unsigned int
filedb_max_user_info_len(const FILEDB_DB* db);


/*
 * A routine which reset the database handle under panic mode
 */
extern void
filedb_dbpanic(FILEDB_DB* dbp);


/**
 * Return all keys to vectors in binary form of strings
 */
extern void
filedb_get_all_keys(FILEDB_DB* dbhh, void* keyss, unsigned int* num);


/**
 * Return all keys & data to vectors in binary form of strings
 */
extern void
filedb_get_all_pairs(FILEDB_DB* dbhh, void* keyss, void* valss, unsigned int* num);


/**
 * get key and data pair from a database pointed by pointer dbh
 *
 * @param dbh database pointer
 * @key key associated with this data. This key must be string form
 * @data data to be stored into the database. It is in string form
 *
 * @return 0 on success. Otherwise failure
 */
extern int
filedb_get_data(FILEDB_DB* dbh, const FILEDB_DBT* key, FILEDB_DBT* data);
  

/**
 * Insert key and data pair in string format into the database
 *
 * @param dbh database pointer
 * @key key associated with this data. This key must be string form
 * @data data to be stored into the database. It is in string form
 *
 * @return 0 on success. Otherwise failure
 */
extern int
filedb_insert_data(FILEDB_DB* dbh, const FILEDB_DBT* key, const FILEDB_DBT* data);


#ifdef __cplusplus
};
#endif

#endif
