// libogg's config_types.h for MSVC. The upstream file is a template filled in
// by autoconf or CMake, and this build uses neither, so the MSVC types are
// written out here (libogg 1.3.6, include/ogg/config_types.h.in).
#ifndef __CONFIG_TYPES_H__
#define __CONFIG_TYPES_H__

typedef short ogg_int16_t;
typedef unsigned short ogg_uint16_t;
typedef int ogg_int32_t;
typedef unsigned int ogg_uint32_t;
typedef __int64 ogg_int64_t;
typedef unsigned __int64 ogg_uint64_t;

#endif
