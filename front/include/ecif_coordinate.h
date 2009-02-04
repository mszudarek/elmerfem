/***********************************************************************
*
*       ELMER, A Computational Fluid Dynamics Program.
*
*       Copyright 1st April 1995 - , CSC - IT Center for Science Ltd.,
*                                    Finland.
*
*       All rights reserved. No part of this program may be used,
*       reproduced or transmitted in any form or by any means
*       without the written permission of CSC.
*
*                Address: CSC - IT Center for Science Ltd.
*                         Keilaranta 14, P.O. BOX 405
*                         02101 Espoo, Finland
*                         Tel.     +358 0 457 2001
*                         Telefax: +358 0 457 2302
*                         EMail:   Jari.Jarvinen@csc.fi
************************************************************************/

/***********************************************************************
Program:    ELMER Front
Module:     ecif_timestep.h
Language:   C++
Date:       01.10.98
Version:    1.00
Author(s):  Martti Verho
Revisions:

Abstract:   A Base class for timestepping scheme parameter

************************************************************************/

#ifndef _ECIF_COORDINATE_
#define _ECIF_COORDINATE_

#include "ecif_def.h"
#include "ecif_parameter.h"


// ****** Coordinate parameter class ******
class Coordinate : public Parameter{
public:
  Coordinate();
  Coordinate(int pid);
  Coordinate(int pid, char* data_string, char* param_name);
  int getLastId() {return last_id;}
  void setLastId(int lid) {last_id = lid;}
  const char* getGuiName() { return "Coordinate"; }
  const char* getArrayName() { return "Coordinate"; }
  const char* getEmfName() { return "Coordinate"; }
  const char* getSifName() { return "Coordinate"; }
  ecif_parameterType getParameterType() { return ECIF_COORDINATE; }
  static void initClass(Model* model);
  void setName(char* param_name);
protected:
  static int last_id;
  static Model* model;
};


#endif
