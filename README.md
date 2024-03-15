# About
This repo contains a windows batch script that compiles a static library of Mojang's [leveldb fork](https://github.com/mojang/leveldb). To run this script locally: simply clone this repository and run `build.cmd` from the command line. Certain build tools are required to compile this project. Read the beginning of `build.cmd` for more information.

# Context
For the purpose of clarification I will be referring to Mojang's fork of leveldb as _mojang-leveldb_. 

mojang-leveldb is a fork of Google's [leveldb](https://en.wikipedia.org/wiki/LevelDB) database with added support for [zlib](https://en.wikipedia.org/wiki/Zlib). This fork is used as the world storage format for [Minecraft Bedrock edition](https://minecraft.wiki/w/Bedrock_Edition). The compression formats [snappy](https://en.wikipedia.org/wiki/Snappy_(compression)) and [zstd](https://en.wikipedia.org/wiki/Zstd) are also present, however in the context of bedrock edition they currently go unused.

This library should only be used for the purpose of interfacing with Minecraft related data found from bedrock edition.

# Relation to leveldb-mcpe
Prior to March of 2024, leveldb-mcpe was a very old fork of leveldb with added support for zlib compression and native windows support. This fork of leveldb was used as the original groundwork for the world format of [Minecraft Pocket Edition](https://minecraft.wiki/w/Pocket_Edition) which would then later evolve into Bedrock edition. 

As of March of 2024, the leveldb-mcpe codebase was removed off of Mojang's offical github page without notice and was replaced with the current fork. This version of the codebase uses the latest upstream version of the leveldb codebase with offical support for windows, zstd compression, and a cmake build script all provided by Google. A branch of the changes that Mojang has added to their fork can be found [here](https://github.com/google/leveldb/compare/main...Mojang:leveldb:t-yemekonnen/adding_zlib_support).

# Backwards compatibility between leveldb-mcpe and mojang-leveldb
For the vast majority of players nothing will change with the introduction of this new fork. Bedrock edition worlds are still stored with "raw deflate" compression - or a `z_stream` with its `windowBits` set to `-15`. See the documentation for this in the [zlib manual](https://www.zlib.net/manual.html#Advanced) as well as Mojang's [usage of deflateInit2](https://github.com/google/leveldb/compare/main...Mojang:leveldb:t-yemekonnen/adding_zlib_support#diff-1663442e47ad4dc949d7bce0cd92d625bde11f0b7990de1117fc7407ea9673f2R184).

Programmers who are writing tools for bedrock edition might want be aware that there is a slight change of the compression definitions found in this new version. In the original codebase, the `leveldb_options_set_compression` function has support for five different compression algorithms:

```c
enum {
    leveldb_no_compression       = 0,
    leveldb_snappy_compression   = 1,
    leveldb_zlib_compression     = 2, // A zopfli compressor also uses this value.
    leveldb_zstd_compression     = 3, // Unused
    leveldb_zlib_raw_compression = 4
};
```
Whereas the new fork only supports four compression algorithms:
```c
enum {
    leveldb_no_compression       = 0,
    leveldb_snappy_compression   = 1,
    leveldb_zstd_compression     = 2,
    leveldb_zlib_raw_compression = 4
};
```
Attentive readers will have noticed that the `leveldb_zlib_compression` option has now been replaced with `leveldb_zstd_compression` - yet they share the same integer value. Those of you familar with leveldb will know that the id of the compression algorithm used is stored along with the data block stored within the database. What this means in theory is that this new fork is no longer backwards compatible with alpha versions of pocket edition. In practice there are very few people who have acess to these older verions of minecraft.

If you do need to be able to read world data from these older versions of minecraft: I was able to make a copy of the original leveldb-mcpe repository before it was removed, and can be located on my [github account](https://github.com/vhebert-gh/levedb-mcpe-legacy).

# Basic api usage
Using mojang-leveldb is very similar to using leveldb. The main difference is that you must set the compression option to `leveldb_zlib_raw_compression` when opening a database in order to read data from bedrock worlds.

The following is a basic example of how to use the C based api exposed by mojang-leveldb:
```c
#include <leveldb\c.h>
#include <stdio.h>

int main()
{
	// Supply your path here.
	const char* DatabaseDir = "";

    	// Basic database types.
	leveldb_t* Database;
	leveldb_options_t* Options;
	
	// Required for error checking on all database operations.
	char* Status = NULL;

    	// Create config for our database.
	Options = leveldb_options_create();
	leveldb_options_set_create_if_missing(Options, 1);
	
	// Needed to read bedrock world data.
	leveldb_options_set_compression(Options, leveldb_zlib_raw_compression);
	
	// Open world.
	Database = leveldb_open(Options, DatabaseDir, &Status);
	
	// We need these to read and write to the database.
	leveldb_readoptions_t* ReadOptions = leveldb_readoptions_create();
	leveldb_writeoptions_t* WriteOptions = leveldb_writeoptions_create();
	
	// Uncomment to use synchronous writes. 
	//leveldb_writeoptions_set_sync(WriteOptions, 1);
	
	// Create iterator to loop through the entire database.
	leveldb_iterator_t* Iter = leveldb_create_iterator(Database, ReadOptions);
	for (leveldb_iter_seek_to_first(Iter); leveldb_iter_valid(Iter); leveldb_iter_next(Iter))
	{
		size_t KeyLength, ValueLength;
		const char* Key = leveldb_iter_key(Iter, &KeyLength);
		const char* Value = leveldb_iter_value(Iter, &ValueLength);
		printf("Key length: %zu, Value Length %zu\n", KeyLength, ValueLength);
	}
	
	// Destory the iterator.
	// This must be done before closing a database, otherwise an assertion is thrown.
	leveldb_iter_destroy(Iter);
	
	// Close the database.
	leveldb_close(Database);
	
	return 0;
}
```