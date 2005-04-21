/*******************************************************************************
 *
 *       ELMER, A Computational Fluid Dynamics Program.
 *
 *       Copyright 1st April 1995 - , Center for Scientific Computing,
 *                                    Finland.
 *
 *       All rights reserved. No part of this program may be used,
 *       reproduced or transmitted in any form or by any means
 *       without the written permission of CSC.
 *
 ******************************************************************************/

/*******************************************************************************
 *
 * Provide system time / memory usage.
 *
 *******************************************************************************
 *
 *                     Author:       Juha Ruokolainen
 *
 *                    Address: Center for Scientific Computing
 *                                Tietotie 6, P.O. BOX 405
 *                                  02101 Espoo, Finland
 *                                  Tel. +358 0 457 2723
 *                                Telefax: +358 0 457 2302
 *                              EMail: Juha.Ruokolainen@csc.fi
 *
 *                       Date: 26 Sep 1995
 *
 *                Modified by:
 *
 *       Date of modification:
 *
 ******************************************************************************/


#ifndef WIN32

  #include <sys/types.h>
  #include <sys/times.h>
  #include <sys/param.h>

  #include <sys/time.h>
  #include <sys/resource.h>

  static struct rusage usage;

  static struct timeval tp;
  static struct timezone tzp;

#if defined(UNICOS)
  double CPUTIME( )
#elif defined(AIX)
  double cputime( )
#else
  double cputime_( )
#endif
  {
      getrusage( RUSAGE_SELF, &usage );
      return (double) usage.ru_utime.tv_sec + usage.ru_utime.tv_usec*1.0e-6;
  }

#if defined(UNICOS)
  double REALTIME( )
#elif defined(AIX)
  double realtime( )
#else
  double realtime_( )
#endif
  {
      gettimeofday( &tp,&tzp );
      return (double) tp.tv_sec + tp.tv_usec*1.0e-6;
  }

#if defined(UNICOS)
  double CPUMEMORY( )
#elif defined(AIX)
  double cpumemory( )
#else
  double cpumemory_( )
#endif
  { 
    getrusage( RUSAGE_SELF, &usage );
    return (double) 1.0 * usage.ru_maxrss;
  }


#else

  #include <sys/types.h>
  #include <time.h>

  __declspec(dllexport) double __stdcall REALTIME( )
  {
     return clock() / (double)CLOCKS_PER_SEC;
  }

  __declspec(dllexport) double __stdcall CPUTIME( )
  {
     return clock() / (double)CLOCKS_PER_SEC;
  }

  __declspec(dllexport) double __stdcall CPUMEMORY( )
  {
     return 0.0;
  }


#endif
