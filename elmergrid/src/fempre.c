/*  
   ElmerGrid - A simple mesh generation and manipulation utility  
   Copyright (C) 1995- , CSC - Scientific Computing Ltd.   

   Author: Peter R�back
   Email: Peter.Raback@csc.fi
   Address: CSC - Scientific Computing Ltd.
            Keilaranta 14
            02101 Espoo, Finland

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

/****************************************************************************
*                                                                           *  
*                              Elmergrid                                    *
*                                                                           *
*  This program creates very easily a structured 2D meshes with BCs.        *
*  The element types include 4, 5, 8, 9, 12 and 16-node rectangles and      *
*  3, 6 and 10-node triangles. There is also limited 3D functionality       *
*  with 8, 20 and 27-node cubes and 6-node prisms.                          *
*                                                                           *
*  Note: this software was initially part of Pirfem code, then later        *
*  called Quickmesh, and finally renamed to Elmergrid. The code has never   *
*  been designed and with new features the code has eventually become very  *
*  dirty.                                                                   *
*                                                                           *
****************************************************************************/


#include <stdio.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>

#include "common.h"
#include "nrutil.h"
#include "femdef.h"
#include "femtypes.h"
#include "femmesh.h"
#include "femknot.h"
#include "feminfo.h"
#include "femelmer.h"
#include "femfile.h"
#include "femfact.h"
#include "easymesh.h"



static void Instructions()
{
  printf("****************** Elmergrid ************************\n");
  printf("This program can create simple 2D structured meshes consisting of\n");
  printf("linear, quadratic or cubic rectangles or triangles. The meshes may\n");
  printf("also be extruded and revolved to create 3D forms. In addition many\n");
  printf("mesh formats may be imported into Elmer software. Some options have\n");
  printf("not been properly tested. Contact the author if you face problems.\n\n");

  printf("The program has two operation modes\n");
  printf("A) Command file mode which has the command file as the only argument\n");
  printf("   'ElmerGrid commandfile.eg'\n\n");

  printf("B) Inline mode which expects at least three input parameters\n");
  printf("   'ElmerGrid 1 3 test'\n\n");
  printf("The first parameter defines the input file format:\n");
  printf("1)  .grd      : Elmergrid file format\n");
  printf("2)  .mesh.*   : Elmer input format\n");
  printf("3)  .ep       : Elmer output format\n");
  printf("4)  .ansys    : Ansys input format\n");
  printf("5)  .inp      : Abaqus input format by Ideas\n");
  printf("6)  .fil      : Abaqus output format\n");
  printf("7)  .FDNEUT   : Fidap neutral file\n");
  printf("8)  .d        : Easymesh input format\n");
  printf("9)  .femlab   : Femlab mesh format\n");
  printf("10) .dat      : Fieldview format\n");
  printf("11) .node,.ele: Triangle 2D mesh format\n");
  printf("12) .mesh     : Medit mesh format\n");
  printf("13) .msh      : GID mesh format\n");
  printf("14) .msh      : Gmsh mesh format\n");

  printf("\nThe second parameter defines the output file format:\n");
  printf("1)  .grd      : ElmerGrid file format\n");
  printf("2)  .mesh.*   : ElmerSolver format (also partitioned .part format)\n");
  printf("3)  .ep       : ElmerPost format\n");

#if 0
  printf("5)  .n .e .s  : Easymesh output format\n");
  printf("6)  .inp      : Abaqus input format\n");
  printf("7)  .fidap    : Fidap format\n");
  printf("8)  .side     : free boundaries\n");
  printf("9) .vf        : view factors of a boundary\n");
  printf("10) .map      : mapping matrix between Elmergrid grids\n");
  printf("11) .ep       : Elmer to Elmer mapping.\n");
  printf("12) .ep       : Elmer to Elmer mapping with mapping file.\n");
  printf("13) .ep       : Fastcap input format.\n");
#endif

  printf("\nThe third parameter is the name of the input file.\n");
  printf("If the file does not exist, an example with the same name is created.\n");
  printf("The default output file name is the same with a different suffix.\n\n");

  printf("There are several additional in-line parameters that are\n");
  printf("taken into account only when applicable to the given format.\n");

  printf("-out str             : name of the output file\n");
  printf("-in str              : name of a secondary input file\n");
  printf("-decimals            : number of decimals in the saved mesh (eg. 8)\n");
  printf("-triangles           : rectangles will be divided to triangles\n");
  printf("-merge real          : merges nodes that are close to each other\n");
  printf("-order real[3]       : reorder elements and nodes using c1*x+c2*y+c3*z\n");
  printf("-scale real[3]       : scale the coordinates with vector real[3]\n");
  printf("-translate real[3]   : translate the nodes with vector real[3]\n");
  printf("-rotate real[3]      : rotate around the main axis with angles real[3]\n");
  printf("-clone int[3]        : make ideantilcal copies of the mesh\n");
  printf("-clonesize real[3]   : the size of the mesh to be cloned if larger to the original\n");
  printf("-mirror int[3]       : copy the mesh around the origin in coordinate directions\n");
  printf("-unite               : the meshes will be united\n");
  printf("-polar real          : map 2D mesh to a cylindrical shell with given radius\n");
  printf("-reduce int[2]       : reduce element order at material interval [int1 int2]\n");
  printf("-increase            : increase element order from one to two\n");
  printf("-pelem int[3]        : make p-elements of power int3 at interval [int1 int2]\n");
  printf("-partition int[3]    : the mesh will be partitioned in main directions\n");
  printf("-partorder real[3]   : in the above method, the direction of the ordering\n");
#if PARTMETIS
  printf("-metis int           : the mesh will be partitioned with Metis\n");
#endif
  printf("-periodic int[3]     : declere the periodic coordinate directions\n");
  printf("-bcoffset int        : add an offset to the boundary conditions\n");
  printf("-discont int         : make the boundary to have secondary nodes\n");
  printf("-bulkbound int[3]    : set the union of materials [int1 int2] to be boundary int3\n");
  printf("-boundbound int[3]   : set the union of boundaries [int1 int2] to be boundary int3\n");
  printf("-bulktype int[3]     : set material types in interval [int1 int2] to type int3\n");
  printf("-boundtype int[3]    : set sidetypes in interval [int1 int2] to type int3\n");
  printf("-layer int[2] real[2]: make a boundary layer for given boundary\n");
  printf("-layermove           : in the previous case move the layer to the original boundary\n");
  printf("-3d / -2d / -1d      : mesh is 3, 2 or 1-dimensional\n");
  printf("-isoparam            : ensure that higher order elements are convex\n");
  printf("-nobound             : disable saving of boundary elements\n");
#if 0
  printf("-map str             : file with mapping info for mesh-to-mesh interpolation\n");
#endif
}


static void Goodbye()
{
  printf("\nThank you for using Elmergrid!\n");
  printf("Send bug reports and feature wishes to peter.raback@csc.fi\n");
  exit(0);
}


void InitParameters(struct ElmergridType *eg)
{
  int i;

  eg->inmethod = 0;
  eg->outmethod = 0;
  eg->nofilesin = 1;
  eg->unitemeshes = FALSE;
  eg->triangles = FALSE;
  eg->rotate = FALSE;
  eg->polar = FALSE;
  eg->layers = 0;
  eg->layereps = 0.0;
  eg->layermove = 0;
  eg->partitions = 0;
  eg->elements3d = 0;
  eg->nodes3d = 0;
  eg->metis = 0;
  eg->reduce = FALSE;
  eg->increase = FALSE;
  eg->translate = FALSE;
  eg->isoparam = FALSE;
  eg->dim = 3;
  eg->scale = FALSE;
  eg->order = FALSE;
  eg->boundbounds = 0;
  eg->bulkbounds = 0;
  eg->partorder = FALSE;
  eg->findsides = FALSE;
  eg->pelems = 0;
  eg->saveboundaries = TRUE;
  eg->merge = FALSE;
  eg->bcoffset = FALSE;
  eg->periodic = 0;
  eg->periodicdim[0] = 0;
  eg->periodicdim[1] = 0;
  eg->periodicdim[2] = 0;
  eg->sidemappings = 0;
  eg->bulkmappings = 0;
  eg->clone[0] = eg->clone[1] = eg->clone[2] = 0;
  eg->mirror[0] = eg->mirror[1] = eg->mirror[2] = 0;
  eg->mirrorbc = 0;
  eg->decimals = 12;
  eg->discont = 0;
  eg->advancedmat = 0;
  
  for(i=0;i<MAXSIDEBULK;i++) 
    eg->sidebulk[i] = 0;
}


int InlineParameters(struct ElmergridType *eg,int argc,char *argv[])
{
  int arg,i,dim;
  
  dim = eg->dim;

  printf("Elmergrid reading in-line arguments\n");

  if(strcmp(argv[1],"eg") == 0) eg->inmethod = 0;
  else if(strcmp(argv[1],"ElmerGrid") == 0) eg->inmethod = 1;
  else if(strcmp(argv[1],"ElmerSolver") == 0) eg->inmethod = 2;
  else if(strcmp(argv[1],"ElmerPost") == 0) eg->inmethod = 3;
  else if(strcmp(argv[1],"Ansys") == 0) eg->inmethod = 4;
  else if(strcmp(argv[1],"Ideas") == 0) eg->inmethod = 5;
  else if(strcmp(argv[1],"Abaqus") == 0) eg->inmethod = 6;
  else if(strcmp(argv[1],"Fidap") == 0) eg->inmethod = 7;
  else if(strcmp(argv[1],"Easymesh") == 0) eg->inmethod = 8;
  else if(strcmp(argv[1],"Femlab") == 0) eg->inmethod = 9;
  else if(strcmp(argv[1],"Fieldview") == 0) eg->inmethod = 10;
  else if(strcmp(argv[1],"Triangle") == 0) eg->inmethod = 11;
  else if(strcmp(argv[1],"Medit") == 0) eg->inmethod = 12;
  else eg->inmethod = atoi(argv[1]);

  if(strcmp(argv[2],"ElmerGrid") == 0) eg->outmethod = 1;
  else if(strcmp(argv[2],"ElmerSolver") == 0) eg->outmethod = 2;
  else if(strcmp(argv[2],"ElmerPost") == 0) eg->outmethod = 3;
  else if(strcmp(argv[2],"Fastcap") == 0) eg->outmethod = 13;
  else eg->outmethod = atoi(argv[2]);

  strcpy(eg->filesin[0],argv[3]);
  strcpy(eg->filesout[0],eg->filesin[0]);
  strcpy(eg->mapfile,eg->filesin[0]);


  for(arg=4;arg <argc; arg++) {
    if(strcmp(argv[arg],"-in") ==0 ) {
      if(arg+1 >= argc) {
	printf("The secondary input file name is required as a paramater\n");
	return(1);
      }
      else {
	strcpy(eg->filesin[eg->nofilesin],argv[arg+1]);
	printf("A secondary input file %s will be loaded.\n",eg->filesin[eg->nofilesin]);
	eg->nofilesin++;
      }
    }
    if(strcmp(argv[arg],"-out") == 0) {
      if(arg+1 >= argc) {
	printf("The output name is required as a paramater\n");
	return(2);
      }
      else {
	strcpy(eg->filesout[0],argv[arg+1]);
	printf("Output will be saved to file %s.\n",eg->filesout[0]);
      }
    }

    if(strcmp(argv[arg],"-decimals") == 0) {
      eg->decimals = atoi(argv[arg+1]);
    }

    if(strcmp(argv[arg],"-triangles") ==0) {
      eg->triangles = TRUE;
      printf("The rectangles will be split to triangles.\n");
    }

    if(strcmp(argv[arg],"-merge") == 0) {
      if(arg+1 >= argc) {
	printf("Give a parameter for critical distance.\n");
	return(18);
      }
      else {
	eg->merge = TRUE;
	eg->cmerge = atof(argv[arg+1]);
      }
    }

    if(strcmp(argv[arg],"-order") == 0) {
      if(arg+dim >= argc) {
	printf("Give %d parameters for the order vector.\n",dim);
 	return(11);
      }
      else {
	eg->order = TRUE;
	eg->corder[0] = atof(argv[arg+1]);
	eg->corder[1] = atof(argv[arg+2]);
	if(dim==3) eg->corder[2] = atof(argv[arg+3]);
      }
    }
    if(strcmp(argv[arg],"-autoorder") == 0) {
      eg->order = 2;
    }

    if(strcmp(argv[arg],"-scale") == 0) {
      if(arg+dim >= argc) {
	printf("Give %d parameters for the scaling.\n",dim);
 	return(12);
     }
      else {
	eg->scale = TRUE;
	eg->cscale[0] = atof(argv[arg+1]);
	eg->cscale[1] = atof(argv[arg+2]);
	if(dim==3) eg->cscale[2] = atof(argv[arg+3]);
      }
    }

    if(strcmp(argv[arg],"-translate") == 0) {
      if(arg+dim >= argc) {
	printf("Give %d parameters for the translate vector.\n",dim);
	return(17);
      }
      else {
	eg->translate = TRUE;
	eg->ctranslate[0] = atof(argv[arg+1]);
	eg->ctranslate[1] = atof(argv[arg+2]);
	if(dim == 3) eg->ctranslate[2] = atof(argv[arg+3]);
      }
    }

    if(strcmp(argv[arg],"-rotate") == 0 || strcmp(argv[arg],"-rotate") == 0) {
      if(arg+dim >= argc) {
	printf("Give three parameters for the rotation angles.\n");
	return(16);
      }
      else {
	eg->rotate = TRUE;
	eg->crotate[0] = atof(argv[arg+1]);
	eg->crotate[1] = atof(argv[arg+2]);
	eg->crotate[2] = atof(argv[arg+3]);
      }
    }

    if(strcmp(argv[arg],"-clone") == 0) {
      if(arg+dim >= argc) {
	printf("Give the number of clones in each %d directions.\n",dim);
 	return(13);
     }
      else {
	eg->clone[0] = atoi(argv[arg+1]);
	eg->clone[1] = atoi(argv[arg+2]);
	if(dim == 3) eg->clone[2] = atoi(argv[arg+3]);
      }
    }
    if(strcmp(argv[arg],"-clonesize") == 0) {
      if(arg+dim >= argc) {
	printf("Give the clone size in each %d directions.\n",dim);
 	return(15);
      }
      else {
	eg->clonesize[0] = atof(argv[arg+1]);
	eg->clonesize[1] = atof(argv[arg+2]);
	if(dim == 3) eg->clonesize[2] = atof(argv[arg+3]);
      }
    }

    if(strcmp(argv[arg],"-mirror") == 0) {
      if(arg+dim >= argc) {
	printf("Give the symmetry of the coordinate directions, eg. 1 1 0\n");
      }
      else {
	eg->mirror[0] = atoi(argv[arg+1]);
	eg->mirror[1] = atoi(argv[arg+2]);
	if(dim == 3) eg->mirror[2] = atoi(argv[arg+3]);
      }
    }
    if(strcmp(argv[arg],"-mirrorbc") == 0) {
      if(arg+1 >= argc) {
	printf("Give the number of symmetry BC.\n");
 	return(14);
      }
      else {
	eg->mirrorbc = atoi(argv[arg+1]);
      }
    }

    if(strcmp(argv[arg],"-unite") ==0) {
      eg->unitemeshes = TRUE;
      printf("The meshes will be united.\n");
    }   

    if(strcmp(argv[arg],"-polar") == 0) {
      eg->polar = TRUE;
      printf("Making transformation to polar coordinates.\n");
      if(arg+1 >= argc) {
	printf("The preferred radius is required as a parameter\n");
	eg->polarradius = 1.0;
      }
      else {
	eg->polarradius = atoi(argv[arg+1]);
      }
    }

    if(strcmp(argv[arg],"-reduce") == 0) {
      if(arg+2 >= argc) {
	printf("Give two material for the interval.\n");
 	return(8);
      }
      else {
	eg->reduce = TRUE;      
	eg->reducemat1 = atoi(argv[arg+1]);
	eg->reducemat2 = atoi(argv[arg+2]);
      }
    }
    if(strcmp(argv[arg],"-increase") == 0) {
      eg->increase = TRUE;
    }
    if(strcmp(argv[arg],"-pelem") == 0) {
      for(i=arg+1;i<argc && strncmp(argv[i],"-",1); i++) 
	eg->pelemmap[3*eg->pelems+i-1-arg] = atoi(argv[i]);
      eg->pelems++;
    } 
    if(strcmp(argv[arg],"-partition") == 0) {
      if(arg+dim >= argc) {
	printf("The number of partitions in %d dims is required as paramaters.\n",dim);
	return(3);
      }
      else {
	eg->partdim[0] = atoi(argv[arg+1]);
	eg->partdim[1] = atoi(argv[arg+2]);
	if(dim == 3) eg->partdim[2] = atoi(argv[arg+3]);
	eg->partitions = 1;
	for(i=0;i<3;i++) {
	  if(eg->partdim[i] < 1) eg->partdim[i] = 1;
	  eg->partitions *= eg->partdim[i];
	}
	printf("The mesh will be partitioned with simple division to %d partitions.\n",
	       eg->partitions);
      }
    }
    if(strcmp(argv[arg],"-partorder") == 0) {
      if(arg+dim >= argc) {
	printf("Give %d parameters for the order vector.\n",dim);
 	return(4);
      }
      else {
	eg->partorder = 1;
	eg->partcorder[0] = atof(argv[arg+1]);
	eg->partcorder[1] = atof(argv[arg+2]);
	if(dim==3) eg->partcorder[2] = atof(argv[arg+3]);
      }
    }

    if(strcmp(argv[arg],"-metis") == 0) {
#if PARTMETIS
      if(arg+1 >= argc) {
	printf("The number of partitions is required as a parameter\n");
	return(5);
      }
      else {
	eg->metis = atoi(argv[arg+1]);
	printf("The mesh will be partitioned with Metis to %d partitions.\n",eg->metis);
      }
#else
      printf("This version of ElmerGrid was compiled without Metis library!\n");
#endif     
    }

    if(strcmp(argv[arg],"-periodic") == 0) {
      if(arg+dim >= argc) {
	printf("Give the periodic coordinate directions (e.g. 1 1 0)\n");
 	return(9);
      }
      else {
	eg->periodicdim[0] = atoi(argv[arg+1]);
	eg->periodicdim[1] = atoi(argv[arg+2]);
	if(dim == 3) eg->periodicdim[2] = atoi(argv[arg+3]);
      }
    }

    if(strcmp(argv[arg],"-discont") == 0) {
      if(arg+1 >= argc) {
	printf("Give the discontinuous boundary conditions.\n");
 	return(10);
      }
      else {
	eg->discontbounds[eg->discont] = atoi(argv[arg+1]);
	eg->discont++;
      }
    }
 
    if(strcmp(argv[arg],"-boundbound") == 0) {
      for(i=arg+1;i<=arg+3 && i<argc; i++) {
	eg->boundbound[3*eg->boundbounds+i-(1+arg)] = atoi(argv[i]);
	if((i-arg)%3 == 0) eg->boundbounds++;
      }
    } 
    if(strcmp(argv[arg],"-bulkbound") == 0) {
      for(i=arg+1;i<=arg+3 && i<argc; i++) {
	eg->bulkbound[3*eg->bulkbounds+i-(1+arg)] = atoi(argv[i]);
	if((i-arg)%3 == 0) eg->bulkbounds++;
      }
    } 
    if(strcmp(argv[arg],"-boundtype") == 0) {
      for(i=arg+1;i<argc && strncmp(argv[i],"-",1); i++) 
	eg->sidemap[3*eg->sidemappings+i-1-arg] = atoi(argv[i]);
      eg->sidemappings++;
    } 
    if(strcmp(argv[arg],"-bulktype") == 0) {
      for(i=arg+1;i<argc && strncmp(argv[i],"-",1); i++) 
	eg->bulkmap[3*eg->bulkmappings+i-1-arg] = atoi(argv[i]);
      eg->bulkmappings++;
    } 

    if(strcmp(argv[arg],"-layer") == 0) {
      if(arg+4 >= argc) {
	printf("Give four parameters for the layer: boundary, elements, thickness, ratio.\n");
	return(19);
      }
      else if(eg->layers == MAXBOUNDARIES) {
	printf("There can only be %d layers, sorry.\n",MAXBOUNDARIES);
	return(20);
      }
      else {
	eg->layerbounds[eg->layers] = atoi(argv[arg+1]);
	eg->layernumber[eg->layers] = atoi(argv[arg+2]);
	eg->layerthickness[eg->layers] = atof(argv[arg+3]);
	eg->layerratios[eg->layers] = atof(argv[arg+4]);
	eg->layerparents[eg->layers] = 0;
	eg->layers++;
      }
    }
    if(strcmp(argv[arg],"-layermove") == 0) {
      eg->layermove = TRUE;
    }

    if(strcmp(argv[arg],"-3d") == 0) {
      eg->dim = dim = 3;
    }
    if(strcmp(argv[arg],"-2d") == 0) {
      eg->dim = dim = 2;
    }
    if(strcmp(argv[arg],"-1d") == 0) {
      eg->dim = dim = 1;
    }

    if(strcmp(argv[arg],"-isoparam") == 0) {
      eg->isoparam = TRUE;
    }
    if(strcmp(argv[arg],"-nobound") == 0) {
      eg->saveboundaries = FALSE;
    }

    /* The following keywords are not actively used */

    if(strcmp(argv[arg],"-map") ==0) {
      if(arg+1 >= argc) {
	printf("Give the name of the mapping file\n");
	return(7);
      }
      else {
	strcpy(eg->mapfile,argv[arg+1]);
	printf("Mapping file is %s\n",eg->mapfile);
      }
    }
    if(strcmp(argv[arg],"-bcoffset") == 0) {
      eg->bcoffset = atoi(argv[arg+1]);
    }
    if(strcmp(argv[arg],"-noelements") == 0) {
      eg->elements3d = atoi(argv[arg+1]);
    }
    if(strcmp(argv[arg],"-nonodes") == 0) {
      eg->nodes3d = atoi(argv[arg+1]);
    }

    if(strcmp(argv[arg],"-sidefind") == 0) {
      eg->findsides = 0;
      for(i=arg+1;i<argc && strncmp(argv[i],"-",1); i++) {
	eg->sidebulk[i-1-arg] = atoi(argv[i]);
	eg->findsides++;
      }
    } 
    if(strcmp(argv[arg],"-findbound") == 0) {
      eg->findsides = 0;
      for(i=arg+1;i+1<argc && strncmp(argv[i],"-",1); i += 2) {
	eg->sidebulk[i-1-arg] = atoi(argv[i]);
	eg->sidebulk[i-arg] = atoi(argv[i+1]);
	eg->findsides++;
      }
    } 
  }

  {
    char *ptr1;
    ptr1 = strchr(eg->filesout[0], '.');
    if (ptr1) *ptr1 = '\0';
    ptr1 = strchr(eg->mapfile, '.');
    if (ptr1) *ptr1 = '\0';
  }

  printf("Output will be saved to file %s.\n",eg->filesout[0]);

  return(0);
}




int LoadCommands(char *prefix,struct ElmergridType *eg,
		 struct GridType *grid, int mode,int info) 
{
  char filename[MAXFILESIZE];
  char command[MAXLINESIZE],params[MAXLINESIZE],*cp;

  FILE *in;
  int i,j,k,l,error=0;

  if(mode == 0) { 
    AddExtension(prefix,filename,"eg");
    if ((in = fopen(filename,"r")) == NULL) {
      printf("LoadCommands: opening of the file '%s' wasn't succesfull !\n",filename);
      return(1);
    }    
    if(info) printf("Loading ElmerGrid commands from file '%s'.\n",filename);    
  }
  else if(mode == 1) {
    AddExtension(prefix,filename,"grd");
    if ((in = fopen(filename,"r")) == NULL) {
      printf("LoadCommands: opening of the file '%s' wasn't succesfull !\n",filename);
      return(1);
    }    
    if(info) printf("Loading ElmerGrid commands from file '%s'.\n",filename);
  }



  for(;;) {
    if(GetCommand(command,params,in)) {
      printf("Reached the end of command file\n");
      goto end;
    }    

    if(mode == 0) {
      if(strstr(command,"INPUT FILE")) {
	sscanf(params,"%s",&eg->filesin[0]);
      }
      else if(strstr(command,"OUTPUT FILE")) {
	sscanf(params,"%s",&eg->filesout[0]);
      }
      else if(strstr(command,"INPUT MODE")) {
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);

	if(strstr(params,"ELMERGRID")) eg->inmethod = 1;
	if(strstr(params,"ELMERSOLVER")) eg->inmethod = 2;
	if(strstr(params,"ELMERPOST")) eg->inmethod = 3;
	if(strstr(params,"ANSYS")) eg->inmethod = 4;
	if(strstr(params,"IDEAS")) eg->inmethod = 5;
	if(strstr(params,"ABAQUS")) eg->inmethod = 6;
	if(strstr(params,"FIDAP")) eg->inmethod = 7;
	if(strstr(params,"EASYMESH")) eg->inmethod = 8;
	if(strstr(params,"FEMLAB")) eg->inmethod = 9;
	if(strstr(params,"FIELDVIEW")) eg->inmethod = 10;
	if(strstr(params,"TRIANGLE")) eg->inmethod = 11;
	if(strstr(params,"MEDIT")) eg->inmethod = 12;
	if(strstr(params,"GID")) eg->inmethod = 13;
	if(strstr(params,"GMSH")) eg->inmethod = 14;
	else sscanf(params,"%d",&eg->inmethod);
      }
      else if(strstr(command,"OUTPUT MODE")) {
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);

	if(strstr(params,"ELMERGRID")) eg->outmethod = 1;
	if(strstr(params,"ELMERSOLVER")) eg->outmethod = 2;
	if(strstr(params,"ELMERPOST")) eg->outmethod = 3;
	if(strstr(params,"FASTCAP")) eg->outmethod = 13;
	else sscanf(params,"%d",&eg->outmethod);	
      }
    }    

    if(strstr(command,"DECIMALS")) {
      sscanf(params,"%d",&eg->decimals);
    }
    else if(strstr(command,"TRIANGLES")) {
      for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
      if(strstr(params,"TRUE")) eg->triangles = TRUE;      
    }
    else if(strstr(command,"MERGE NODES")) {
      eg->merge = TRUE;
      sscanf(params,"%le",&eg->cmerge);
    }
    else if(strstr(command,"UNITE")) {
      for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
      if(strstr(params,"TRUE")) eg->unitemeshes = TRUE;      
    }
    else if(strstr(command,"ORDER NODES")) {
      eg->order = TRUE;
      if(eg->dim == 1) 
	sscanf(params,"%le",&eg->corder[0]);
      else if(eg->dim == 2) 
	sscanf(params,"%le%le",&eg->corder[0],&eg->corder[1]);
      else if(eg->dim == 3) 
	sscanf(params,"%le%le%le",&eg->corder[0],&eg->corder[1],&eg->corder[2]);
    }
    else if(strstr(command,"SCALE")) {
      eg->scale = TRUE;
      if(eg->dim == 1) 
	sscanf(params,"%le",&eg->cscale[0]);
      else if(eg->dim == 2) 
	sscanf(params,"%le%le",&eg->cscale[0],&eg->cscale[1]);
      else if(eg->dim == 3) 
	sscanf(params,"%le%le%le",&eg->cscale[0],&eg->cscale[1],&eg->cscale[2]);
    }
    else if(strstr(command,"TRANSLATE")) {
      eg->translate = TRUE;
      if(eg->dim == 1) 
	sscanf(params,"%le",&eg->ctranslate[0]);
      else if(eg->dim == 2) 
	sscanf(params,"%le%le",&eg->ctranslate[0],&eg->ctranslate[1]);
      else if(eg->dim == 3) 
	sscanf(params,"%le%le%le",&eg->ctranslate[0],&eg->ctranslate[1],&eg->ctranslate[2]);
    }
    else if(strstr(command,"ROTATE MESH")) {
      eg->rotate = TRUE;
      if(eg->dim == 1) 
	sscanf(params,"%le",&eg->crotate[0]);
      else if(eg->dim == 2) 
	sscanf(params,"%le%le",&eg->crotate[0],&eg->crotate[1]);
      else if(eg->dim == 3) 
	sscanf(params,"%le%le%le",&eg->crotate[0],&eg->crotate[1],&eg->crotate[2]);
    }
    else if(strstr(command,"CLONE")) {
      if(strstr(command,"CLONE SIZE")) {
	if(eg->dim == 1) 
	  sscanf(params,"%le",&eg->clonesize[0]);
	else if(eg->dim == 2) 
	  sscanf(params,"%le%le",&eg->clonesize[0],&eg->clonesize[1]);
	else if(eg->dim == 3) 
	  sscanf(params,"%le%le%le",&eg->clonesize[0],&eg->clonesize[1],&eg->clonesize[2]);	
      }
      else {
	if(eg->dim == 1) 
	  sscanf(params,"%d",&eg->clone[0]);
	else if(eg->dim == 2) 
	  sscanf(params,"%d%d",&eg->clone[0],&eg->clone[1]);
	else if(eg->dim == 3) 
	  sscanf(params,"%d%d%d",&eg->clone[0],&eg->clone[1],&eg->clone[2]);
      }
    }
    else if(strstr(command,"MIRROR")) {
      if(eg->dim == 1) 
	sscanf(params,"%d",&eg->mirror[0]);
      else if(eg->dim == 2) 
	sscanf(params,"%d%d",&eg->mirror[0],&eg->mirror[1]);
      else if(eg->dim == 3) 
	sscanf(params,"%d%d%d",&eg->mirror[0],&eg->mirror[1],&eg->mirror[2]);
    }
    else if(strstr(command,"POLAR RADIUS")) {
      eg->polar = TRUE;
      sscanf(params,"%le",&eg->polarradius);
    }
    else if(strstr(command,"REDUCE DEGREE")) {
      eg->reduce = TRUE;
      sscanf(params,"%d%d",&eg->reducemat1,&eg->reducemat2);
    }
    else if(strstr(command,"INCREASE DEGREE")) {
      for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
      if(strstr(params,"TRUE")) eg->increase = TRUE;      
    }
    else if(strstr(command,"ADVANCED ELEMENTS")) {
      printf("Loading advanced element definitions\n");
      
      for(i=0;i<MAXMATERIALS;i++) {
	if(i>0) Getline(params,in);
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"END")) break;
		
	sscanf(params,"%d%d%d%d%d%d",
	       &eg->advancedelem[6*i],&eg->advancedelem[6*i+1],&eg->advancedelem[6*i+2],
	       &eg->advancedelem[6*i+3],&eg->advancedelem[6*i+4],&eg->advancedelem[6*i+5]);
      }  
      eg->advancedmat = i;
      printf("Found %d definitions for p-elements.\n",i);
    }
    else if(strstr(command,"POWER ELEMENTS")) {
      printf("Loading p-type element definitions\n");
      
      for(i=0;i<MAXMATERIALS;i++) {
	if(i>0) Getline(params,in);
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"END")) break;
	sscanf(params,"%d%d%d",
	       &eg->pelemmap[3*i],&eg->pelemmap[3*i+1],&eg->pelemmap[3*i+2]);
      }  
      eg->pelems = i;
      printf("Found %d definitions for p-elements.\n",i);
    }
    else if(strstr(command,"METIS")) {
#if PARTMETIS
      sscanf(params,"%d",&eg->metis);
#else
      printf("This version of ElmerGrid was compiled without Metis library!\n");
#endif
    }
    else if(strstr(command,"PARTITION ORDER")) {
      eg->partorder = 1;
      if(eg->dim == 2) sscanf(params,"%le%le",&eg->partcorder[0],&eg->partcorder[1]);
      if(eg->dim == 3) sscanf(params,"%le%le%le",&eg->partcorder[0],
			      &eg->partcorder[1],&eg->partcorder[2]);      
    }
    else if(strstr(command,"PARTITION")) {
      if(eg->dim == 2) sscanf(params,"%d%d",&eg->partdim[0],&eg->partdim[1]);
      if(eg->dim == 3) sscanf(params,"%d%d%d",&eg->partdim[0],&eg->partdim[1],&eg->partdim[2]);
      eg->partitions = 1;
      for(i=0;i<eg->dim;i++) {
	if(eg->partdim[i] < 1) eg->partdim[i] = 1;
	eg->partitions *= eg->partdim[i];
      }
    }
    else if(strstr(command,"PERIODIC")) {
      if(eg->dim == 2) sscanf(params,"%d%d",&eg->periodicdim[0],&eg->periodicdim[1]);
      if(eg->dim == 3) sscanf(params,"%d%d%d",&eg->periodicdim[0],
			      &eg->periodicdim[1],&eg->periodicdim[2]);
    }

    else if(strstr(command,"BOUNDARY BOUNDARY")) {
      for(i=0;i<MAXBOUNDARIES;i++) {
	if(i>0) Getline(params,in);
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"END")) break;
	cp = params;      
	sscanf(params,"%d%d%d",&eg->boundbound[3*i+2],&eg->boundbound[3*i],&eg->boundbound[3*i+1]);
      }
      printf("Found %d boundary boundary definitions\n",i);
      eg->boundbounds = i;
    }
    else if(strstr(command,"MATERIAL BOUNDARY")) {
      for(i=0;i<MAXBOUNDARIES;i++) {
	if(i>0) Getline(params,in);
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"END")) break;
	cp = params;      
	sscanf(params,"%d%d%d",&eg->bulkbound[3*i+2],&eg->bulkbound[3*i],&eg->bulkbound[3*i+1]);
      }
      printf("Found %d material boundary definitions\n",i);
      eg->bulkbounds = i;
    }

    else if(strstr(command,"RENUMBER BOUNDARY")) {
      for(i=0;i<MAXBOUNDARIES;i++) {
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"END")) break;
	cp = params;      
	sscanf(params,"%d%d%d",&eg->sidemap[3*i],&eg->sidemap[3*i+1],&eg->sidemap[3*i+2]);
      }
      printf("Found %d boundary mappings\n",i);
      eg->sidemappings = i;
    }
    else if(strstr(command,"RENUMBER MATERIAL")) {
      for(i=0;i<MAXBOUNDARIES;i++) {
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"END")) break;
	cp = params;      
	sscanf(params,"%d%d%d",&eg->bulkmap[3*i],&eg->bulkmap[3*i+1],&eg->bulkmap[3*i+2]);
      }
      printf("Found %d material mappings\n",i);
      eg->bulkmappings = i;
    }

    else if(strstr(command,"BOUNDARY LAYER")) {
      if(strstr(command,"BOUNDARY LAYER MOVE")) {
	for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	if(strstr(params,"TRUE")) eg->layermove = TRUE;
      }
      else if(strstr(command,"BOUNDARY LAYER EPSILON")) {
	sscanf(params,"%le",&eg->layereps);
      }
      else {
	for(i=0;i<MAXBOUNDARIES;i++) {
	  if(i>0) Getline(params,in);
	  for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
	  cp = params;      

	  if(strstr(params,"END") || strstr(params,"End") ) break;
	  eg->layerbounds[i] = next_int(&cp);
	  eg->layernumber[i] = next_int(&cp);
	  eg->layerthickness[i] = next_real(&cp);
	  eg->layerratios[i] = next_real(&cp);
	  eg->layerparents[i] = next_int(&cp);	  
	}
	printf("Found %d boundary layers\n",i);
	eg->layers = i;
      }
    }
    else if(strstr(command,"DIMENSION")) {
      sscanf(params,"%d",&eg->dim);
    }
    else if(strstr(command,"ISOPARAMETRIC")) {
      for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
      if(strstr(params,"TRUE")) eg->isoparam = TRUE;
    }
    else if(strstr(command,"NO BOUNDARY")) {
      for(j=0;j<MAXLINESIZE;j++) params[j] = toupper(params[j]);
      if(strstr(params,"TRUE")) eg->saveboundaries = FALSE;
    }
    else if(strstr(command,"EXTRUDED")) {
      grid->dimension = 3;
      grid->autoratio = FALSE;    

      if(strstr(command,"EXTRUDED DIVISIONS")) {
	sscanf(params,"%d",&grid->zcells);		
      }
      else if(strstr(command,"EXTRUDED LIMITS")) {
	cp = params;
	for(i=0;i<=grid->zcells;i++) grid->z[i] = next_real(&cp);
      }
      else if(strstr(command,"EXTRUDED ELEMENTS")) {
	cp = params;
	for(i=1;i<=grid->zcells;i++) grid->zelems[i] = next_int(&cp);
      }
      else if(strstr(command,"EXTRUDED RATIOS")) {
	cp = params;
	for(i=1;i<=grid->zcells;i++) grid->zexpand[i] = next_real(&cp);
      }
      else if(strstr(command,"EXTRUDED DENSITIES")) {
	cp = params;
	for(i=1;i<=grid->zcells;i++) grid->zdens[i] = next_real(&cp);
      }
      else if(strstr(command,"EXTRUDED STRUCTURE")) {
	for(i=1;i<= grid->zcells;i++) {
	  if(i>1) Getline(params,in);
	  sscanf(params,"%d %d %d\n",
		 &grid->zfirstmaterial[i],&grid->zlastmaterial[i],&grid->zmaterial[i]); 
	}
      }

    }
  }

end:
  printf("Read commands from a file\n");

  return(0);
}


int RotateTranslateScale(struct FemType *data,struct ElmergridType *eg)
{
  int i,j,k;
  Real x,y,z,xz,yz,yx,zx,zy,xy,cx,cy,cz;

  if(eg->scale) {
    printf("Scaling mesh with vector [%.3lg %.3lg %.3lg]\n",
	   eg->cscale[0],eg->cscale[1],eg->cscale[2]);
    for(i=1;i<=data->noknots;i++) {
      data->x[i] *= eg->cscale[0]; 
      data->y[i] *= eg->cscale[1]; 
      if(data->dim == 3) data->z[i] *= eg->cscale[2]; 
    }
    printf("Scaling of mesh finished.\n");
  }
  
  if(eg->rotate) {
    printf("Rotating mesh with degrees [%.3lg %.3lg %.3lg]\n",
	   eg->crotate[0],eg->crotate[1],eg->crotate[2]);
    cx = FM_PI * eg->crotate[0]/180.0;
    cy = FM_PI * eg->crotate[1]/180.0;
    cz = FM_PI * eg->crotate[2]/180.0;

    for(i=1;i<=data->noknots;i++) {

      x = data->x[i];
      if(data->dim >= 2) y = data->y[i];
      else y = 0.0;
      if(data->dim >= 3) z = data->z[i];
      else z = 0.0;

      xz = x*cos(cz) + y*sin(cz);
      yz = -x*sin(cz) + y*cos(cz);
      
      if(data->dim == 3) {
	yx = yz*cos(cx) + z*sin(cx);
	zx = -yz*sin(cx) + z*cos(cx);
	
	zy = zx*cos(cy) + xz*sin(cy);
	xy = -zx*sin(cy) + xz*cos(cy);
	
	data->x[i] = xy;
	data->y[i] = yx;
	data->z[i] = zy;
      }	
      else {
	data->x[i] = xz;
	data->y[i] = yz;  
      }
    }
    printf("Rotation of mesh finished.\n");
  }

  if(eg->translate) {
    printf("Translating the mesh with vector [%.3lg %.3lg %.3lg]\n",
	   eg->ctranslate[0],eg->ctranslate[1],eg->ctranslate[2]);
    for(i=1;i<=data->noknots;i++) {
      data->x[i] += eg->ctranslate[0];
      data->y[i] += eg->ctranslate[1];
      if(data->dim == 3) data->z[i] += eg->ctranslate[2];
    }
    printf("Translation of mesh finished.\n");
  }

  return(0);
}



int main(int argc, char *argv[])
{
  int i,j,k,l,inmethod,outmethod,info,errorstat;
  int nogrids,nomeshes,nofile,dim,elementsredone=0;
  int nodes3d,elements3d;
  Real mergeeps;
  char prefix[MAXFILESIZE];
  struct GridType *grids;
  struct CellType *cell[MAXCASES];
  struct FemType data[MAXCASES];
  struct BoundaryType *boundaries[MAXCASES];
  struct ElmergridType eg;
  long ii;

  printf("\nStarting program Elmergrid\n");

  InitParameters(&eg);
  grids = (struct GridType*)malloc((size_t) (MAXCASES)*sizeof(struct GridType));     
  InitGrid(grids);
  info = TRUE;

  if(argc == 2) {
    errorstat = LoadCommands(argv[1],&eg,grids,0,info);     
    if(errorstat) Goodbye();
  }
  else if(argc < 4) {
    Instructions();
    Goodbye();
  } 
  else {
    errorstat = InlineParameters(&eg,argc,argv);
    if(errorstat) Goodbye();
  }


  if(!eg.outmethod || !eg.inmethod) {
    printf("Please define the input and output formats\n");
  }
  if(eg.inmethod != 1) {
    if(eg.outmethod == 1 || eg.outmethod == 8 || eg.outmethod == 9 || eg.outmethod == 10) {
      printf("input of type %d can't create output of type %d\n",
	     eg.inmethod,eg.outmethod);
      errorstat++;
      Goodbye();
    }
  }
  if(eg.inmethod != 8 && eg.outmethod == 5) {
    printf("To write Easymesh format you need to read easymesh format!\n");
    errorstat++;
  }


  /**********************************/
  printf("\nElmergrid loading data:\n");

  dim = eg.dim;
  nofile = 0;
  nomeshes = 0;
  nogrids = 0;
  inmethod = eg.inmethod;
  outmethod = eg.outmethod;


 read_another_file:    

  switch (inmethod) {

  case 1:        
    if(LoadElmergrid(&grids,&nogrids,eg.filesin[nofile],info) == 1) {   
      if(dim == 3) ExampleGrid3D(&grids,&nogrids,info);
      if(dim == 2) ExampleGrid2D(&grids,&nogrids,info);
      if(dim == 1) ExampleGrid1D(&grids,&nogrids,info);
      SaveElmergrid(grids,nogrids,eg.filesin[nofile],info); 
      printf("Because file %s didn't exist, it was created for you.\n",eg.filesin[nofile]);
      Goodbye();
    }

    LoadCommands(eg.filesin[nofile],&eg,grids,1,info); 
    break;

  case 2: 
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    if(LoadElmerInput(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],info))
      Goodbye();
    nomeshes = nofile+1;
    if(boundaries[nofile]->created) data[nofile].noboundaries = 1;
    break;

  case 3: 
    if(LoadSolutionElmer(&(data[nofile]),TRUE,eg.filesin[nofile],info)) 
      Goodbye();
    nomeshes = nofile+1;
    break;

  case 4:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    if(LoadAnsysInput(&(data[0]),boundaries[0],eg.filesin[nofile],info)) 
      Goodbye();
    nomeshes = nofile+1;
    break;

  case 5: 
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    if(LoadAbaqusInput(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],TRUE)) 
      Goodbye();
    nomeshes = nofile+1;
    break;

  case 6:
    if(LoadAbaqusOutput(&(data[nofile]),eg.filesin[nofile],TRUE))
      Goodbye();
    nomeshes = nofile+1;
    break;

  case 7:
    if(LoadFidapInput(&(data[nofile]),eg.filesin[nofile],TRUE))
      Goodbye();
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	

    ElementsToBoundaryConditions(&(data[nofile]),boundaries[nofile],TRUE);

    nomeshes = nofile+1;
    break;

  case 8: 
    {
      int sides;
      InitializeKnots(&(data[nofile]));
      if( Easymesh(argc,argv,&data[nofile].noknots,
		   &data[nofile].noelements,&sides)) 
	Goodbye();	

      data[nofile].dim = 2;
      data[nofile].coordsystem = COORD_CART2;
      data[nofile].maxnodes = 3;

      AllocateKnots(&(data[nofile]));
      boundaries[nofile] = (struct BoundaryType*)
	malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	

      if(EasymeshCopy(&(data[nofile]),boundaries[nofile]))
	Goodbye();

      nomeshes = nofile + 1;
    }
  break;

 case 9:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    if(LoadFemlabMesh(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],info)) 
      Goodbye();
    nomeshes = nofile + 1;
    break;

 case 99:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    if(LoadFemlab3Mesh(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],info)) 
      Goodbye();
    nomeshes = nofile + 1;
    break;


  case 10:
    if(LoadFieldviewInput(&(data[nofile]),eg.filesin[nofile],TRUE))
      Goodbye();
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    ElementsToBoundaryConditions(&(data[nofile]),boundaries[nofile],TRUE);
    nomeshes = 1;
    break;

  case 11:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    for(j=0;j<MAXBOUNDARIES;j++) 
      boundaries[nofile][j].created = FALSE;
    if (LoadTriangleInput(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],TRUE))
      Goodbye();
    nomeshes = 1;
    break;

  case 12:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    for(j=0;j<MAXBOUNDARIES;j++) 
      boundaries[nofile][j].created = FALSE;
    if (LoadMeditInput(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],TRUE))
      Goodbye();
    nomeshes = 1;
    break;

  case 13:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    for(j=0;j<MAXBOUNDARIES;j++) 
      boundaries[nofile][j].created = FALSE;
    if (LoadGidInput(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],TRUE))
      Goodbye();
    nomeshes = 1;
    break;

  case 14:
    boundaries[nofile] = (struct BoundaryType*)
      malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
    for(j=0;j<MAXBOUNDARIES;j++) 
      boundaries[nofile][j].created = FALSE;
    if (LoadGmshInput(&(data[nofile]),boundaries[nofile],eg.filesin[nofile],TRUE))
      Goodbye();
    nomeshes = 1;
    break;

  default:
    Instructions();
    Goodbye();
  }  

  nofile++;
  if(nofile < eg.nofilesin) goto read_another_file;


  /***********************************/


 redoelements:

  printf("\nElmergrid creating and manipulating meshes:\n");

  if(nogrids > nomeshes && outmethod != 1) { 

    nomeshes = nogrids;
    for(k=0;k<nogrids;k++) {

      CreateCells(&(grids[k]),&(cell[k]),info);  

      CreateKnots(&(grids[k]),cell[k],&(data[k]),0,0);

      boundaries[k] = (struct BoundaryType*)
	malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 

      for(j=0;j<MAXBOUNDARIES;j++) 
	boundaries[k][j].created = FALSE;

      if(grids[k].noboundaries > 0) {
	for(j=0;j<grids[k].noboundaries;j++) {
	  if(grids[k].boundsolid[j] < 4) {
	    CreateBoundary(cell[k],&(data[k]),&(boundaries[k][j]),
			   grids[k].boundext[j],grids[k].boundint[j],
			   1,grids[k].boundtype[j]);  
	  } 
	  else { 
	    CreatePoints(cell[k],&(data[k]),&(boundaries[k][j]),
			 grids[k].boundext[j],grids[k].boundint[j],
			 grids[k].boundsolid[j],grids[k].boundtype[j]); 	    
	  }

	}
      }
    }

  }

  for(k=0;k<nomeshes;k++) {
    if(!eg.discont) {
      for(j=0;j<grids[k].noboundaries;j++) 
	if(grids[k].boundsolid[j] == 2) {
	  eg.discontbounds[eg.discont] = grids[k].boundtype[j];
	  eg.discont++;	  
	}
    }

    if(eg.discont) {
      for(i=1;i<=eg.discont;i++) 
	SetDiscontinuousBoundary(&(data[k]),boundaries[k],eg.discontbounds[i-1],2,info);
    }
  }


  for(k=0;k<nomeshes;k++) {
    if(nogrids && (eg.triangles || grids[k].triangles == TRUE))
      ElementsToTriangles(&data[k],boundaries[k],info);
  }

  if(eg.layers) {
    for(k=0;k<nomeshes;k++) 
      CreateBoundaryLayer(&data[k],boundaries[k],eg.layers,
			  eg.layerbounds, eg.layernumber, eg.layerratios, eg.layerthickness,
			  eg.layerparents, eg.layermove, eg.layereps, info);
  }

  for(k=0;k<nomeshes;k++) {
    if(eg.polar || data[k].coordsystem == COORD_POLAR) {
      if(!eg.polar) eg.polarradius = grids[k].polarradius;
      PolarCoordinates(&data[k],eg.polarradius,info);
    }
  }

  if(outmethod != 1 && dim != 2 && eg.dim != 2) { 
    j = MAX(nogrids,1);

    for(k=0;k<j;k++) {
      if(grids[k].dimension == 3 || grids[k].rotate) {

	boundaries[j] = (struct BoundaryType*)
	  malloc((size_t) (MAXBOUNDARIES)*sizeof(struct BoundaryType)); 	
	
	for(i=0;i<MAXBOUNDARIES;i++) 
	  boundaries[j][i].created = FALSE;

	CreateKnotsExtruded(&(data[k]),boundaries[k],&(grids[k]),
			    &(data[j]),boundaries[j],info);

	if(nogrids) {
	  elements3d = MAX(eg.elements3d, grids[k].wantedelems3d);
	  nodes3d = MAX(eg.nodes3d, grids[k].wantednodes3d);
	  
	  if(elements3d) {
	    if( abs(data[j].noelements - elements3d) / (1.0*elements3d) > 0.01 && elementsredone < 5 ) {
	      grids[k].wantedelems *= pow(1.0*elements3d / data[j].noelements, (2.0/3.0));
	      elementsredone++;
	    }
	    else elementsredone = 0;
	  }
	  else if(nodes3d) {
	    if( abs(data[j].noknots - nodes3d) / (1.0*nodes3d) > 0.01 && elementsredone < 5 ) {
	      grids[k].wantedelems *= pow(1.0*nodes3d / data[j].noknots, (2.0/3.0));
	      elementsredone++;
	    }
	    else elementsredone = 0;
	  }
	  
	  if(elementsredone) {
	    nomeshes = 0;
	    for(i=0;i < nogrids;i++) SetElementDivision(&(grids[i]),info);
	    
	    DestroyKnots(&data[j]);
	    DestroyKnots(&data[k]);
	    free(cell[k]);
	    
	    if(info) printf("Iteration %d of elements number targiting %d in 2D\n",
			    elementsredone,grids[k].wantedelems);
	    goto redoelements;
	  }
	}	

	data[k] = data[j];
	boundaries[k] = boundaries[j];
      }
    }
  }


  if(eg.unitemeshes) {
    for(k=1;k<nomeshes;k++)
      UniteMeshes(&data[0],&data[k],boundaries[0],boundaries[k],info);
    nomeshes = nogrids = 1;
  }
  

  if(eg.clone[0] || eg.clone[1] || eg.clone[2]) {
    for(k=0;k<nomeshes;k++) {
      CloneMeshes(&data[k],boundaries[k],eg.clone,eg.clonesize,FALSE,info);
      mergeeps = fabs(eg.clonesize[0]+eg.clonesize[1]+eg.clonesize[2]) * 1.0e-8;
      MergeElements(&data[k],boundaries[k],eg.order,eg.corder,mergeeps,TRUE,TRUE);
    }
  }

  if(eg.mirror[0] || eg.mirror[1] || eg.mirror[2]) {
    for(k=0;k<nomeshes;k++) {
      MirrorMeshes(&data[k],boundaries[k],eg.mirror,FALSE,eg.clonesize,eg.mirrorbc,info);
      mergeeps = fabs(eg.clonesize[0]+eg.clonesize[1]+eg.clonesize[2]) * 1.0e-8;
      MergeElements(&data[k],boundaries[k],eg.order,eg.corder,mergeeps,FALSE,TRUE);
    }
  }

  if(nomeshes > 1) {
    strcpy(prefix,eg.filesout[0]);
    for(k=0;k<nomeshes;k++)
      sprintf(eg.filesout[k],"%s%d",prefix,k+1);
  }

  for(k=0;k<nomeshes;k++) {
    if(nogrids && grids[k].reduceordermatmax) {
      eg.reduce = TRUE;
      eg.reducemat1 = grids[k].reduceordermatmin;
      eg.reducemat2 = grids[k].reduceordermatmax;
    }
    if(eg.reduce) 
      ReduceElementOrder(&data[k],eg.reducemat1,eg.reducemat2);
  }

  for(k=0;k<nomeshes;k++) {
    if(eg.increase) IncreaseElementOrder(&data[k],TRUE);
  }
 
  for(k=0;k<nomeshes;k++) {
    if(eg.merge) {
      MergeElements(&data[k],boundaries[k],eg.order,eg.corder,eg.cmerge,FALSE,TRUE);
    }
    else if(eg.order) {
      ReorderElements(&data[k],boundaries[k],eg.order,eg.corder,TRUE);
    }
    if(eg.isoparam) {
      IsoparametricElements(&data[k],boundaries[k],TRUE,info);
    }
  }  

  for(k=0;k<nomeshes;k++) 
    if(eg.findsides) 
      SideToBulkElements(&data[k],boundaries[k],eg.sidebulk,FALSE,info);


  for(k=0;k<nomeshes;k++) {
    if(eg.bulkbounds || eg.boundbounds) {
      int *boundnodes,noboundnodes;
      boundnodes = Ivector(1,data[k].noknots);
      
      if(eg.bulkbounds) {
	for(l=0;l<eg.bulkbounds;l++) {
	  FindBulkBoundary(&data[k],eg.bulkbound[3*l],eg.bulkbound[3*l+1],
			   boundnodes,&noboundnodes,info);
	  FindNewBoundaries(&data[k],boundaries[k],boundnodes,eg.bulkbound[3*l+2],info);
	}
      }
      if(eg.boundbounds) {
	for(l=0;l<eg.boundbounds;l++) {	
	  FindBoundaryBoundary(&data[k],boundaries[k],eg.boundbound[3*l],eg.boundbound[3*l+1],
			       boundnodes,&noboundnodes,info);
	  FindNewBoundaries(&data[k],boundaries[k],boundnodes,eg.boundbound[3*l+2],info);
	}
      }
      free_Ivector(boundnodes,1,data[k].noknots);
    }

    if(eg.bulkbounds || eg.boundbounds)
      SeparateCartesianBoundaries(&data[k],boundaries[k],info);
  }


  for(k=0;k<nomeshes;k++) {
    if(data[k].variables == 0) {
      CreateVariable(&data[k],1,1,0.0,"Number",FALSE);
      for(i=1;i<=data[k].alldofs[1];i++)
	data[k].dofs[1][i] = (Real)(i);
    }
  }

  for(k=0;k<nomeshes;k++) {
    RotateTranslateScale(&data[k],&eg);
  }

  if(eg.bcoffset) {
    printf("Addiing offset of %d to the BCs\n",eg.bcoffset);

    for(k=0;k<nomeshes;k++) {
      for(j=0;j < MAXBOUNDARIES;j++) {
	if(!boundaries[k][j].created) continue;
	for(i=1; i <= boundaries[k][j].nosides; i++) 
	  boundaries[k][j].types[i] += eg.bcoffset;
      }
    }
    printf("Renumbering boundary types finished\n");
  }

  if(eg.sidemappings) {
    int currenttype;
    
    for(l=0;l<eg.sidemappings;l++) 
      printf("Setting boundary types between %d and %d to %d\n",
	     eg.sidemap[3*l],eg.sidemap[3*l+1],eg.sidemap[3*l+2]);

    for(k=0;k<nomeshes;k++) {
      for(j=0;j < MAXBOUNDARIES;j++) {
	if(!boundaries[k][j].created) continue;
	
	for(i=1; i <= boundaries[k][j].nosides; i++) {
	  if(currenttype = boundaries[k][j].types[i]) {
	    for(l=0;l<eg.sidemappings;l++) {
	      if(currenttype >= eg.sidemap[3*l] && currenttype <= eg.sidemap[3*l+1]) {
		boundaries[k][j].types[i] = eg.sidemap[3*l+2];
		currenttype = -1;
	      }
	    }
	  }
	}
      }
    }
    printf("Renumbering boundary types finished\n");
  }
  
  if(eg.bulkmappings) {
    int currenttype;
    for(l=0;l<eg.bulkmappings;l++) 
      printf("Setting material types between %d and %d to %d\n",
	     eg.bulkmap[3*l],eg.bulkmap[3*l+1],eg.bulkmap[3*l+2]);
    for(k=0;k<nomeshes;k++) {
      for(j=1;j<=data[k].noelements;j++) {
	currenttype = data[k].material[j];
	for(l=0;l<eg.bulkmappings;l++) {
	  if(currenttype >= eg.bulkmap[3*l] && currenttype <= eg.bulkmap[3*l+1]) {
	    data[k].material[j] = eg.bulkmap[3*l+2];
	    currenttype = -1;
	  }
	}
      }
    }
    printf("Renumbering material indexes finished\n");
  }


  for(k=0;k<nomeshes;k++) {
    if(eg.periodicdim[0] || eg.periodicdim[1] || eg.periodicdim[2]) {
      if(info) printf("There seems to be peridic boundaries\n");
      FindPeriodicNodes(&data[k],eg.periodicdim,info);
    }
  } 
   
  for(k=0;k<nomeshes;k++) {
    if(eg.partitions > 1)
#if 1
      PartitionSimple(&data[k],eg.partdim,eg.periodicdim,eg.partorder,eg.partcorder,info);	
#else
      PartitionSimpleNodes(&data[k],eg.partdim,eg.periodicdim,eg.partorder,eg.partcorder,info);	
#endif
#if PARTMETIS
    else if(eg.metis > 1) 
      PartitionMetis(&data[k],eg.metis,info);
#endif
    if(eg.partitions > 1 || eg.metis > 1) 
      OptimizePartitioning(&data[k],boundaries[k],info);
  }

  if(eg.pelems) {
    int currenttype;
    for(l=0;l<eg.pelems;l++)  
      printf("Setting element between materials %d and %d to have p=%d.\n",
	     eg.bulkmap[3*l],eg.bulkmap[3*l+1],eg.bulkmap[3*l+2]);
    for(k=0;k<nomeshes;k++) {
      data[k].pelemtypes = Ivector(1,data[k].noelements); 
      data[k].pelems = TRUE;

      for(j=1;j<=data[k].noelements;j++) {
	currenttype = data[k].material[j];
	for(l=0;l<eg.pelems;l++) {
	  if(currenttype >= eg.pelemmap[3*l] && currenttype <= eg.pelemmap[3*l+1]) {
	    data[k].pelemtypes[j] = eg.pelemmap[3*l+2];
	    currenttype = -1;
	  }
	}
      }
    }
    printf("Creating p-elements finished\n");
  }
  if(eg.advancedmat) {
    int currenttype;
    for(k=0;k<nomeshes;k++) {
      data[k].pelemtypes = Ivector(1,data[k].noelements); 
      data[k].pelems = 2;
      for(j=1;j<=data[k].noelements;j++) 
	data[k].pelemtypes[j] = 1;

      for(l=0;l<eg.advancedmat;l++) {
	printf("Setting element of material %d to have advanced settings [%d %d %d %d %d]\n",
	       eg.advancedelem[6*l],eg.advancedelem[6*l+1],eg.advancedelem[6*l+2],
	       eg.advancedelem[6*l+3],eg.advancedelem[6*l+4],eg.advancedelem[6*l+5]);
	
	for(j=1;j<=data[k].noelements;j++) {
	  if( data[k].material[j] == eg.advancedelem[6*l]) {
	    data[k].pelemtypes[j] = eg.advancedelem[6*l+1] + 10*eg.advancedelem[6*l+2] + 
	      100*eg.advancedelem[6*l+3] + 1000*eg.advancedelem[6*l+4] + 10000*eg.advancedelem[6*l+5];
	  }
	}
      }
    }
    printf("Creating advanced elements finished\n");
  }


  /********************************/
  printf("\nElmergrid saving data:\n");

  switch (outmethod) {
  case 1:
    SaveElmergrid(grids,nogrids,eg.filesout[0],info);
    break; 

  case 2:
    for(k=0;k<nomeshes;k++) {
      if(data[k].nopartitions > 1) 
	SaveElmerInputPartitioned(&data[k],boundaries[k],eg.filesout[k],eg.decimals,info);
      else
	SaveElmerInput(&data[k],boundaries[k],eg.filesout[k],eg.decimals,0,info);
    }
    break;

  case 3:
  case 4:
    for(k=0;k<nomeshes;k++) {
      SaveSolutionElmer(&data[k],boundaries[k],eg.saveboundaries ? MAXBOUNDARIES:0,
			eg.filesout[k],eg.decimals,info);
    }
    break;

  case 5:
    EasymeshSave();
    break;

  case 6:
    for(k=0;k<nogrids;k++)
      SaveAbaqusInput(&data[k],eg.filesout[k],info); 
    break;
    
  case 7:
    for(k=0;k<nogrids;k++)
      SaveFidapOutput(&data[k],eg.filesout[k],info,1,data[k].dofs[1]);
    break;
    
  case 8:
    for(k=0;k<nogrids;k++) {   
      for(i=0;i<grids[k].noboundaries;i++)
	if(boundaries[k][i].created == TRUE) {
	  sprintf(prefix,"%s%d",eg.filesout[k],i+1);
	  SaveBoundary(&data[k],&boundaries[k][i],prefix,info);
	}
    }
    break;
    
  case 9:
    for(k=0;k<nogrids;k++) {   
      for(i=0;i<grids[k].noboundaries;i++)
	if(boundaries[k][i].created == TRUE) {
	  sprintf(prefix,"%s%d",eg.filesout[k],i+1);
	  boundaries[k][i].vf = Rmatrix(1,boundaries[k][i].nosides,
					1,boundaries[k][i].nosides);
	  boundaries[k][i].vfcreated = TRUE;
	  SideAreas(&data[k],&boundaries[k][i]);
	  ViewFactors(&data[k],&boundaries[k][i],TRUE);      
	  SaveViewFactors(&data[k],&boundaries[k][i],prefix,info);
	}
    }
    break;
    
  case 10:
    if(nogrids <= 1) printf("No mapping possible for %d grid.\n",nogrids);
    for(k=0;k<nogrids-1;k++) {
      sprintf(prefix,"%s%dto%d",eg.filesout[0],k+1,k+2);
      SaveGridToGridMapping(cell[k],&(grids[k]),cell[k+1],&(grids[k+1]),prefix);
      sprintf(prefix,"%s%dto%d",eg.filesout[0],k+2,k+1);
      SaveGridToGridMapping(cell[k+1],&(grids[k+1]),cell[k],&(grids[k]),prefix);
    }
    break;

  case 11:
    if(LoadSolutionElmer(&(data[1]),FALSE,eg.filesin[1],info)) {
      printf("The reading of the input file %s was not succesfull\n",eg.filesin[1]);
      Goodbye();
    }
    ElmerToElmerMap(&(data[0]),&(data[1]),TRUE);
    sprintf(prefix,"%s%s%s",eg.filesin[1],"_",eg.filesin[0]);
    SaveSolutionElmer(&(data[1]),boundaries[0],0,prefix,eg.decimals,TRUE);
    break;

  case 12:
    if(LoadSolutionElmer(&(data[1]),FALSE,eg.filesout[1],info)) {
      printf("The reading of the input file %s was not succesfull\n",eg.filesout[1]);
      Goodbye();
    }
    if(ElmerToElmerMapQuick(&(data[0]),&(data[1]),eg.mapfile,info))
      Goodbye();
    sprintf(prefix,"%s%s%s",eg.filesin[1],"_",eg.filesin[0]);
    SaveSolutionElmer(&(data[1]),boundaries[0],0,prefix,eg.decimals,TRUE);
    break;

  case 13:    
    for(k=0;k<nomeshes;k++) {
      SaveFastcapInput(&data[k],boundaries[k],eg.filesout[k],eg.decimals,info);
    }
    break;


  default:
    Instructions();
    break;
  }    

  Goodbye();
  return(0);
}





