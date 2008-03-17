#include <QtGui>
#include <QFile>
#include <iostream>
#include <fstream>
#include "mainwindow.h"
 
using namespace std;


// Construct main window...
//-----------------------------------------------------------------------------
MainWindow::MainWindow()
{
  // load tetlib
  tetlibAPI = new TetlibAPI;
  tetlibPresent = tetlibAPI->loadTetlib();
  this->in = tetlibAPI->in;
  this->out = tetlibAPI->out;
  
  // load nglib
  nglibAPI = new NglibAPI;
  nglibPresent = nglibAPI->loadNglib();
  this->mp = nglibAPI->mp;
  this->ngmesh = nglibAPI->ngmesh;
  this->nggeom = nglibAPI->nggeom;

  // elmergrid
  elmergridAPI = new ElmergridAPI;

  // widgets and utilities
  glWidget = new GLWidget;
  setCentralWidget(glWidget);
  sifWindow = new SifWindow(this);
  meshControl = new MeshControl(this);
  meshControl->nglibPresent = nglibPresent;
  meshControl->tetlibPresent = tetlibPresent;
  meshControl->defaultControls();
  boundaryDivide = new BoundaryDivide(this);
  meshingThread = new MeshingThread;
  meshutils = new Meshutils;

  createActions();
  createMenus();
  createToolBars();
  createStatusBar();
  
  // glWidget emits (list_t*) when a boundary is selected by double clicking:
  connect(glWidget, SIGNAL(signalBoundarySelected(list_t*)), this, SLOT(boundarySelectedSlot(list_t*)));

  // meshingThread emits (void) when the mesh generation is completed:
  connect(meshingThread, SIGNAL(signalMeshOk()), this, SLOT(meshOkSlot()));

  // boundaryDivide emits (double) when "divide button" has been clicked:
  connect(boundaryDivide, SIGNAL(signalDoDivision(double)), this, SLOT(doDivisionSlot(double)));

  nglibInputOk = false;
  tetlibInputOk = false;
  activeGenerator = GEN_UNKNOWN;

  setWindowTitle(tr("Elmer Mesh3D (experimental)"));
}


// dtor...
//-----------------------------------------------------------------------------
MainWindow::~MainWindow()
{
}



// Create status bar...
//-----------------------------------------------------------------------------
void MainWindow::createStatusBar()
{
  statusBar()->showMessage(tr("Ready"));
}


// Create menus...
//-----------------------------------------------------------------------------
void MainWindow::createMenus()
{
  // File menu
  fileMenu = menuBar()->addMenu(tr("&File"));
  fileMenu->addAction(openAct);
  fileMenu->addAction(loadAct);
  fileMenu->addAction(saveAct);
  fileMenu->addSeparator();
  fileMenu->addAction(exitAct);

  // Edit menu
  editMenu = menuBar()->addMenu(tr("&Edit"));
  editMenu->addAction(showsifAct);
  editMenu->addSeparator();
  editMenu->addAction(steadyHeatSifAct);
  editMenu->addAction(linElastSifAct);

  // Mesh menu
  meshMenu = menuBar()->addMenu(tr("&Mesh"));
  meshMenu->addAction(meshcontrolAct);
  meshMenu->addAction(remeshAct);
  meshMenu->addSeparator();
  meshMenu->addAction(boundarydivideAct);
  meshMenu->addAction(boundaryunifyAct);
  meshMenu->addSeparator();
  meshMenu->addAction(hidesurfacemeshAct);
  meshMenu->addAction(hidesharpedgesAct);
  meshMenu->addAction(hideselectedAct);
  meshMenu->addAction(showallAct);
  meshMenu->addAction(resetAct);

  // Help menu
  helpMenu = menuBar()->addMenu(tr("&Help"));
  helpMenu->addAction(aboutAct);
}



// Create tool bars...
//-----------------------------------------------------------------------------
void MainWindow::createToolBars()
{
  // File toolbar
  fileToolBar = addToolBar(tr("&File"));
  fileToolBar->addAction(openAct);
  fileToolBar->addAction(loadAct);
  fileToolBar->addAction(saveAct);
  fileToolBar->addSeparator();
  fileToolBar->addAction(exitAct);
}


// Create actions...
//-----------------------------------------------------------------------------
void MainWindow::createActions()
{
  // File -> Open file
  openAct = new QAction(QIcon(":/icons/fileopen.png"), tr("&Open..."), this);
  openAct->setShortcut(tr("Ctrl+O"));
  openAct->setStatusTip(tr("Open model input file"));
  connect(openAct, SIGNAL(triggered()), this, SLOT(openSlot()));
  
  // File -> Load mesh
  loadAct = new QAction(QIcon(":/icons/fileimport.png"), tr("&Import..."), this);
  loadAct->setShortcut(tr("Ctrl+I"));
  loadAct->setStatusTip(tr("Import Elmer mesh files"));
  connect(loadAct, SIGNAL(triggered()), this, SLOT(loadSlot()));
  
  // File -> Save file
  saveAct = new QAction(QIcon(":/icons/fileexport.png"), tr("&Export..."), this);
  saveAct->setShortcut(tr("Ctrl+E"));
  saveAct->setStatusTip(tr("Export Elmer mesh files"));
  connect(saveAct, SIGNAL(triggered()), this, SLOT(saveSlot()));

  // File -> Exit
  exitAct = new QAction(QIcon(":/icons/exit.png"), tr("E&xit"), this);
  exitAct->setShortcut(tr("Alt+X"));
  exitAct->setStatusTip(tr("Exit"));
  connect(exitAct, SIGNAL(triggered()), this, SLOT(close()));

  // Edit -> Sif
  showsifAct = new QAction(QIcon(":/icons/edit.png"), tr("&Solver input file..."), this);
  showsifAct->setShortcut(tr("Ctrl+S"));
  showsifAct->setStatusTip(tr("Edit solver input file"));
  connect(showsifAct, SIGNAL(triggered()), this, SLOT(showsifSlot()));

  // Edit -> Steady heat conduntion...
  steadyHeatSifAct = new QAction(QIcon(), tr("Heat conduction..."), this);
  steadyHeatSifAct->setStatusTip(tr("Sif skeleton for steady heat conduction"));
  connect(steadyHeatSifAct, SIGNAL(triggered()), this, SLOT(makeSteadyHeatSifSlot()));

  // Edit -> Linear elasticity...
  linElastSifAct = new QAction(QIcon(), tr("Linear elasticity..."), this);
  linElastSifAct->setStatusTip(tr("Sif skeleton for linear elasticity"));
  connect(linElastSifAct, SIGNAL(triggered()), this, SLOT(makeLinElastSifSlot()));

  // Mesh -> Control
  meshcontrolAct = new QAction(QIcon(":/icons/configure.png"), tr("&Configure..."), this);
  meshcontrolAct->setShortcut(tr("Ctrl+C"));
  meshcontrolAct->setStatusTip(tr("Configure mesh generators"));
  connect(meshcontrolAct, SIGNAL(triggered()), this, SLOT(meshcontrolSlot()));

  // Mesh -> Remesh
  remeshAct = new QAction(QIcon(":/icons/redo.png"), tr("&Remesh..."), this);
  remeshAct->setShortcut(tr("Ctrl+R"));
  remeshAct->setStatusTip(tr("Remesh"));
  connect(remeshAct, SIGNAL(triggered()), this, SLOT(remeshSlot()));

  // Mesh -> Divide boundary
  boundarydivideAct = new QAction(QIcon(":/icons/divide.png"), tr("&Divide boundary..."), this);
  boundarydivideAct->setShortcut(tr("Ctrl+D"));
  boundarydivideAct->setStatusTip(tr("Divide boundary by sharp edges"));
  connect(boundarydivideAct, SIGNAL(triggered()), this, SLOT(boundarydivideSlot()));

  // Mesh -> Unify boundary
  boundaryunifyAct = new QAction(QIcon(":/icons/unify.png"), tr("&Unify boundary..."), this);
  boundaryunifyAct->setShortcut(tr("Ctrl+U"));
  boundaryunifyAct->setStatusTip(tr("Unify boundary (merge selected)"));
  connect(boundaryunifyAct, SIGNAL(triggered()), this, SLOT(boundaryunifySlot()));

  // Mesh -> Hide/Show surface mesh
  hidesurfacemeshAct = new QAction(QIcon(), tr("Hide/Show surface mesh..."), this);
  hidesurfacemeshAct->setStatusTip(tr("Hide/show surface mesh (do/do not outline surface elements)"));
  connect(hidesurfacemeshAct, SIGNAL(triggered()), this, SLOT(hidesurfacemeshSlot()));

  // Mesh -> Hide/Show sharp edges
  hidesharpedgesAct = new QAction(QIcon(), tr("Hide/Show sharp edges..."), this);
  hidesharpedgesAct->setStatusTip(tr("Hide/show sharp edges"));
  connect(hidesharpedgesAct, SIGNAL(triggered()), this, SLOT(hidesharpedgesSlot()));

  // Mesh -> Hide/Show selected
  hideselectedAct = new QAction(QIcon(), tr("&Hide/Show selected..."), this);
  hideselectedAct->setStatusTip(tr("Hide/show selected objects"));
  connect(hideselectedAct, SIGNAL(triggered()), this, SLOT(hideselectedSlot()));

  // Mesh -> Show all
  showallAct = new QAction(QIcon(), tr("Show all..."), this);
  showallAct->setStatusTip(tr("Show all boundaries"));
  connect(showallAct, SIGNAL(triggered()), this, SLOT(showallSlot()));

  // Mesh -> Reset
  resetAct = new QAction(QIcon(), tr("Reset model view..."), this);
  resetAct->setStatusTip(tr("Reset model"));
  connect(resetAct, SIGNAL(triggered()), this, SLOT(resetSlot()));

  // Help -> About
  aboutAct = new QAction(QIcon(":/icons/info.png"), tr("Info..."), this);
  aboutAct->setStatusTip(tr("Information about the program"));
  connect(aboutAct, SIGNAL(triggered()), this, SLOT(showaboutSlot()));
}



// Mesh -> Control...
//-----------------------------------------------------------------------------
void MainWindow::meshcontrolSlot()
{
  meshControl->tetlibPresent = this->tetlibPresent;
  meshControl->nglibPresent = this->nglibPresent;

  if(!tetlibPresent) {
    meshControl->tetlibPresent = false;
    meshControl->ui.nglibRadioButton->setChecked(true);
    meshControl->ui.tetlibRadioButton->setEnabled(false);
    meshControl->ui.tetlibStringEdit->setEnabled(false);
  }

  if(!nglibPresent) {
    meshControl->nglibPresent = false;
    meshControl->ui.tetlibRadioButton->setChecked(true);
    meshControl->ui.nglibRadioButton->setEnabled(false);
    meshControl->ui.nglibMaxHEdit->setEnabled(false);
    meshControl->ui.nglibFinenessEdit->setEnabled(false);
    meshControl->ui.nglibBgmeshEdit->setEnabled(false);
  }

  if(!tetlibPresent && !nglibPresent) 
    meshControl->ui.elmerGridRadioButton->setChecked(true);  

  meshControl->show();
}



// Mesh -> Divide boundary...
//-----------------------------------------------------------------------------
void MainWindow::boundarydivideSlot()
{
  boundaryDivide->show();
}



// Mesh -> unify boundary...
//-----------------------------------------------------------------------------
void MainWindow::boundaryunifySlot()
{
  mesh_t *mesh = glWidget->mesh;
  int lists = glWidget->lists;
  list_t *list = glWidget->list;

  if(mesh == NULL) {
    logMessage("No boundaries to unify");
    return;
  }
  
  int targetindex = -1;
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    if(l->selected && (l->nature == PDE_BOUNDARY)) {
      if(targetindex < 0) {
	targetindex = l->index;
	break;
      }
    }
  }

  if(targetindex < 0) {
    logMessage("No boundaries selected");
    return;
  }
  
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];    
    if(l->selected && (l->nature == PDE_BOUNDARY)) {

      for(int j=0; j < mesh->surfaces; j++) {
	surface_t *s = &mesh->surface[j];
	if((s->index == l->index) && (s->nature == PDE_BOUNDARY)) 
	  s->index = targetindex;
      }

      for(int j=0; j < mesh->edges; j++) {
	edge_t *e = &mesh->edge[j];
	if((e->index == l->index) && (e->nature == PDE_BOUNDARY)) 
	  e->index = targetindex;
      }

    }
  }
  
  cout << "Selected surfaces marked with index " << targetindex << endl;
  cout.flush();

  glWidget->rebuildLists();

  logMessage("Selected surfaces unified");
}


// Mesh -> Hide/Show surface mesh...
//-----------------------------------------------------------------------------
void MainWindow::hidesurfacemeshSlot()
{
  mesh_t *mesh = glWidget->mesh;
  int lists = glWidget->lists;
  list_t *list = glWidget->list;

  if(mesh == NULL) {
    logMessage("There is no surface mesh to hide/show");
    return;
  }
  
  bool vis = false;
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    if(l->type == SURFACEEDGELIST) 
    {
      l->visible = !l->visible;
      vis = l->visible;

      // do not set visible if the parent surface list is hidden
      int p = l->parent;
      if(p >= 0) {
	list_t *lp = &list[p];
	if(!lp->visible)
	  l->visible = false;
      }
    }
  }

 if ( !vis ) logMessage("Surface mesh hidden");
 else logMessage("Surface mesh shown");
}


// Mesh -> Hide/Show sharp edges...
//-----------------------------------------------------------------------------
void MainWindow::hidesharpedgesSlot()
{
  mesh_t *mesh = glWidget->mesh;
  int lists = glWidget->lists;
  list_t *list = glWidget->list;

  if(mesh == NULL) {
    logMessage("There are no sharp edges to hide/show");
    return;
  }
  
  bool vis = false;
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    if(l->type == SHARPEDGELIST)  {
      l->visible = !l->visible;
      vis = l->visible;
    }
  }
  
  if ( !vis ) logMessage("Sharp edges hidden");
  else logMessage("Sharp edges shown");
}



// Mesh -> Hide/Show selected...
//-----------------------------------------------------------------------------
void MainWindow::hideselectedSlot()
{
  mesh_t *mesh = glWidget->mesh;
  int lists = glWidget->lists;
  list_t *list = glWidget->list;

  if(mesh == NULL) {
    logMessage("There is nothing to hide/show");
    return;
  }

  bool surfaceedgelists_visible = false;
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    if(l->type == SURFACEEDGELIST)
      surfaceedgelists_visible |= l->visible;
  } 
  
  bool vis = false;
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    if(l->selected) {
      l->visible = !l->visible;
      vis = l->visible;

      // hide also all the child surfaceedgelist
      int c = l->child;
      if(c >= 0) {
	list_t *lc = &list[c];
	lc->visible = l->visible;
	if(!surfaceedgelists_visible)
	  lc->visible = false;
      }
    }
  }
  
  if ( !vis ) logMessage("Selected objects hidden");
  else logMessage("Selected objects shown");
}


// Mesh -> Show all...
//-----------------------------------------------------------------------------
void MainWindow::showallSlot()
{
  int lists = glWidget->lists;
  list_t *list = glWidget->list;
  
  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    l->visible = true;
  }

  logMessage("All objects visible");
}


// Mesh -> Reset model view...
//-----------------------------------------------------------------------------
void MainWindow::resetSlot()
{
  mesh_t *mesh = glWidget->mesh;
  int lists = glWidget->lists;
  list_t *list = glWidget->list;
  
  if(mesh == NULL) {
    logMessage("There is nothing to reset");
    return;
  }

  for(int i=0; i<lists; i++) {
    list_t *l = &list[i];
    l->visible = true;
    l->selected = false;
  }

  glLoadIdentity();
  glWidget->rebuildLists();
  glWidget->updateGL();

  logMessage("Model reset");
}


// Make boundary division by sharp edges (signalled by boundaryDivide)...
//-----------------------------------------------------------------------------
void MainWindow::doDivisionSlot(double angle)
{
  mesh_t *mesh = glWidget->mesh;

  if(mesh == NULL) {
    logMessage("No mesh to divide");
    return;
  }
  
  meshutils->findSharpEdges(mesh, angle);
  int parts = meshutils->divideSurfaceBySharpEdges(mesh);

  QString qs = "Boundary divided into " + QString::number(parts) + " parts";
  statusBar()->showMessage(qs);
  
  glWidget->rebuildLists();
}



// Edit -> Sif...
//-----------------------------------------------------------------------------
void MainWindow::showsifSlot()
{
  sifWindow->show();
}



// Mesh -> Remesh...
//-----------------------------------------------------------------------------
void MainWindow::remeshSlot()
{
  if(activeGenerator == GEN_UNKNOWN) {
    logMessage("Unable to mesh: no mesh generator");
    return;
  }
  
  if(activeGenerator == GEN_TETLIB) {

    if(!tetlibPresent) {
      logMessage("tetlib functionality unavailable");
      return;
    }
    
    if(!tetlibInputOk) {
      logMessage("Remesh: error: no input data for tetlib");
      return;
    }

    // must have "J" in control string:
    tetlibControlString = meshControl->tetlibControlString;

  } else if(activeGenerator == GEN_NGLIB) {

    if(!nglibPresent) {
      logMessage("nglib functionality unavailable");
      return;
    }

    if(!nglibInputOk) {
      logMessage("Remesh: error: no input data for nglib");
      return;
    }

    char backgroundmesh[1024];
    sprintf(backgroundmesh, "%s",
	    (const char*)(meshControl->nglibBackgroundmesh.toAscii()));
    
    ngmesh = nglibAPI->Ng_NewMesh();
    
    mp->maxh = meshControl->nglibMaxH.toDouble();
    mp->fineness = meshControl->nglibFineness.toDouble();
    mp->secondorder = 0;
    mp->meshsize_filename = backgroundmesh;

  } else if(activeGenerator == GEN_ELMERGRID) {

    // ***** ELMERGRID *****
    meshutils->clearMesh(glWidget->mesh);
    glWidget->mesh = new mesh_t;
    mesh_t *mesh = glWidget->mesh;
    
    elmergridAPI->createElmerMeshStructure(mesh, meshControl->elmerGridControlString.toAscii());

    cout << "Nodes: " << mesh->nodes << endl;
    cout << "Elements: " << mesh->elements << endl;
    cout << "Surfaces: " << mesh->surfaces << endl;
    cout.flush();
    
    for(int i=0; i<mesh->surfaces; i++ )
    {
      surface_t *surface = &mesh->surface[i];

      surface->edges = (int)(surface->code/100);
      surface->edge = new int[surface->edges];
      for(int j=0; j<surface->edges; j++)
        surface->edge[j] = -1;
    }
    meshutils->findSurfaceElementEdges(mesh);

    if(0) meshutils->findSurfaceElementParents(mesh);
 
    meshutils->findSurfaceElementNormals(mesh);
    glWidget->rebuildLists();

    return;
    
  } else {

    logMessage("Remesh: uknown generator type");
    return;

  }

  // Start meshing thread:
  meshingThread->generate(activeGenerator, tetlibControlString,
			  tetlibAPI, ngmesh, nggeom, mp, nglibAPI);

  logMessage("Mesh generation initiated");
  statusBar()->showMessage(tr("Generating mesh..."));
}




// Mesh is ready (signaled by MeshingThread::run):
//-----------------------------------------------------------------------------
void MainWindow::meshOkSlot()
{
  logMessage("Mesh generation completed");

  if(activeGenerator == GEN_TETLIB) {

    makeElmerMeshFromTetlib();

  } else if(activeGenerator == GEN_NGLIB) {

    makeElmerMeshFromNglib();

  } else {
    
    logMessage("MeshOk: error: unknown mesh generator");

  }

  statusBar()->showMessage(tr("Ready"));
}



// File -> Open...
//-----------------------------------------------------------------------------
void MainWindow::openSlot()
{
  QString fileName = QFileDialog::getOpenFileName(this);

  if (!fileName.isEmpty()) {
    
    QFileInfo fi(fileName);
    QString absolutePath = fi.absolutePath();
    QDir::setCurrent(absolutePath);
    
  } else {
    
    logMessage("Unable to open file: file name is empty");
    return;

  }
  
  readInputFile(fileName);
  remeshSlot();
}


// File -> Load...
//-----------------------------------------------------------------------------
void MainWindow::loadSlot()
{
  QString dirName = QFileDialog::getExistingDirectory(this);

  if (!dirName.isEmpty()) {

    logMessage("Loading from directory " + dirName);

  } else {

    logMessage("Unable to load mesh: directory undefined");
    return;

  }
  
  loadElmerMesh(dirName);
}



// File -> Save...
//-----------------------------------------------------------------------------
void MainWindow::saveSlot()
{
  if(glWidget->mesh==NULL) {
    logMessage("Unable to save mesh: no data");
    return;
  }

  QString dirName = QFileDialog::getExistingDirectory(this);

  if (!dirName.isEmpty()) {

    logMessage("Output directory " + dirName);

  } else {

    logMessage("Unable to save: directory undefined");
    return;

  }
  
  saveElmerMesh(dirName);
}



// Load mesh files in elmer-format:
//-----------------------------------------------------------------------------
void MainWindow::loadElmerMesh(QString dirName)
{
  logMessage("Loading elmer mesh files");

  QFile file;
  QDir::setCurrent(dirName);

  // Header:
  file.setFileName("mesh.header");
  if(!file.exists()) {
    logMessage("mesh.header does not exist");
    return;
  }

  file.open(QIODevice::ReadOnly);
  QTextStream mesh_header(&file);

  int nodes, elements, surfaces, types, type, ntype;

  mesh_header >> nodes >> elements >> surfaces;
  mesh_header >> types;

  int elements_zero_d = 0;
  int elements_one_d = 0;
  int elements_two_d = 0;
  int elements_three_d = 0;
  
  for(int i=0; i<types; i++) {
    mesh_header >> type >> ntype;
    
    switch(type/100) {
    case 1:
      elements_zero_d += ntype;
      break;
    case 2:
      elements_one_d += ntype;
      break;
    case 3:
    case 4:
      elements_two_d += ntype;
      break;
    case 5:
    case 8:
      elements_three_d += ntype;
      break;
    default:
      cout << "Unknown element family (possibly not implamented)" << endl;
      cout.flush();
      exit(0);
    }
  }
  
  file.close();

  cout << "Summary:" << endl;
  cout << "Nodes: " << nodes << endl;
  cout << "point elements: " << elements_zero_d << endl;
  cout << "edge elements: " << elements_one_d << endl;
  cout << "surface elements: " << elements_two_d << endl;
  cout << "volume elements: " << elements_three_d << endl;
  cout.flush();

  // Allocate the new mesh:
  meshutils->clearMesh(glWidget->mesh);
  glWidget->mesh = new mesh_t;
  mesh_t *mesh = glWidget->mesh;
  
  mesh->nodes = nodes;
  mesh->node = new node_t[nodes];

  mesh->points = elements_zero_d;
  mesh->point = new point_t[mesh->points];

  mesh->edges = elements_one_d;
  mesh->edge = new edge_t[mesh->edges];

  mesh->surfaces = elements_two_d;
  mesh->surface = new surface_t[mesh->surfaces];

  mesh->elements = elements_three_d;
  mesh->element = new element_t[mesh->elements];

  // Nodes:
  file.setFileName("mesh.nodes");
  if(!file.exists()) {
    logMessage("mesh.nodes does not exist");
    return;
  }

  file.open(QIODevice::ReadOnly);
  QTextStream mesh_node(&file);
  
  int number, index;
  double x, y, z;

  for(int i=0; i<nodes; i++) {
    node_t *node = &mesh->node[i];
    mesh_node >> number >> index >> x >> y >> z;
    node->x[0] = x;
    node->x[1] = y;
    node->x[2] = z;
    node->index = index;
  }

  file.close();  

  // Elements:
  file.setFileName("mesh.elements");
  if(!file.exists()) {
    logMessage("mesh.elements does not exist");
    meshutils->clearMesh(mesh);
    return;
  }

  file.open(QIODevice::ReadOnly);
  QTextStream mesh_elements(&file);

  int current_point = 0;
  int current_edge = 0;
  int current_surface = 0;
  int current_element = 0;

  point_t *point = NULL;
  edge_t *edge = NULL;
  surface_t *surface = NULL;
  element_t *element = NULL;

  for(int i=0; i<elements; i++) {
    mesh_elements >> number >> index >> type;

    switch(type/100) {
    case 1:
      point = &mesh->point[current_point++];
      point->nature = PDE_BULK;
      point->index = index;
      point->code = type;
      point->nodes = point->code % 100;
      point->node = new int[point->nodes];
      for(int j=0; j < point->nodes; j++) {
	mesh_elements >> point->node[j];
	point->node[j] -= 1;
      }
      point->edges = 2;
      point->edge = new int[point->edges];
      point->edge[0] = -1;
      point->edge[1] = -1;
      break;

    case 2:
      edge = &mesh->edge[current_edge++];
      edge->nature = PDE_BULK;
      edge->index = index;
      edge->code = type;
      edge->nodes = edge->code % 100;
      edge->node = new int[edge->nodes];
      for(int j=0; j < edge->nodes; j++) {
	mesh_elements >> edge->node[j];
	edge->node[j] -= 1;
      }
      edge->surfaces = 0;
      edge->surface = new int[edge->surfaces];
      edge->surface[0] = -1;
      edge->surface[1] = -1;

      break;

    case 3:
    case 4:
      surface = &mesh->surface[current_surface++];
      surface->nature = PDE_BULK;
      surface->index = index;
      surface->code = type;
      surface->nodes = surface->code % 100;
      surface->node = new int[surface->nodes];
      for(int j=0; j < surface->nodes; j++) {
	mesh_elements >> surface->node[j];
	surface->node[j] -= 1;
      }      
      surface->edges = (int)(surface->code/100);
      surface->edge = new int[surface->edges];
      for(int j=0; j<surface->edges; j++)
	surface->edge[j] = -1;
      surface->elements = 2;
      surface->element = new int[surface->elements];
      surface->element[0] = -1;
      surface->element[1] = -1;

      break;

    case 5:
    case 8:
      element = &mesh->element[current_element++];
      element->nature = PDE_BULK;
      element->index = index;
      element->code = type;
      element->nodes = element->code % 100;
      element->node = new int[element->nodes];
      for(int j=0; j < element->nodes; j++) {
	mesh_elements >> element->node[j];
	element->node[j] -= 1;
      }
      break;

    default:
      cout << "Unknown element type (possibly not implemented" << endl;
      cout.flush();
      exit(0);
      break;
    }

  }

  file.close();

  // Boundary elements:
  file.setFileName("mesh.boundary");
  if(!file.exists()) {
    logMessage("mesh.boundary does not exist");
    meshutils->clearMesh(mesh);
    return;
  }

  file.open(QIODevice::ReadOnly);
  QTextStream mesh_boundary(&file);

  int parent0, parent1;
  for(int i=0; i<surfaces; i++) {
    mesh_boundary >> number >> index >> parent0 >> parent1 >> type;

    switch(type/100) {
    case 1:
      point = &mesh->point[current_point++];
      point->nature = PDE_BOUNDARY;
      point->index = index;
      point->edges = 2;
      point->edge = new int[point->edges];
      point->edge[0] = parent0-1;
      point->edge[1] = parent0-1;
      point->code = type;
      point->nodes = point->code % 100;
      point->node = new int[point->nodes];
      for(int j=0; j < point->nodes; j++) {
	mesh_elements >> point->node[j];
	point->node[j] -= 1;
      }
      break;

    case 2:
      edge = &mesh->edge[current_edge++];
      edge->nature = PDE_BOUNDARY;
      edge->index = index;
      edge->surfaces = 2;
      edge->surface = new int[edge->surfaces];
      edge->surface[0] = parent0-1;
      edge->surface[1] = parent1-1;
      edge->code = type;
      edge->nodes = edge->code % 100;
      edge->node = new int[edge->nodes];      
      for(int j=0; j < edge->nodes; j++) {
	mesh_boundary >> edge->node[j];
	edge->node[j] -= 1;
      }

      break;

    case 3:
    case 4:
      surface = &mesh->surface[current_surface++];
      surface->nature = PDE_BOUNDARY;
      surface->index = index;
      surface->elements = 2;
      surface->element = new int[surface->elements];
      surface->element[0] = parent0-1;
      surface->element[1] = parent1-1;
      surface->code = type;
      surface->nodes = surface->code % 100;
      surface->node = new int[surface->nodes];
      for(int j=0; j < surface->nodes; j++) {
	mesh_boundary >> surface->node[j];
	surface->node[j] -= 1;
      }
      surface->edges = (int)(surface->code/100);
      surface->edge = new int[surface->edges];
      for(int j=0; j<surface->edges; j++)
	surface->edge[j] = -1;      
      
      break;

    case 5:
    case 8:
      // can't be boundary elements
      break;

    default:
      break;
    }
  }

  file.close();

  // Todo: should we always do this?
  meshutils->findSurfaceElementEdges(mesh);
  meshutils->findSurfaceElementNormals(mesh);

  // Finalize:
  logMessage("Ready");

  glWidget->rebuildLists();
}



// Write out mesh files in elmer-format:
//-----------------------------------------------------------------------------
void MainWindow::saveElmerMesh(QString dirName)
{
  logMessage("Saving elmer mesh files");

  statusBar()->showMessage(tr("Saving..."));

  QDir dir(dirName);
  if ( !dir.exists() ) dir.mkdir(dirName);
  dir.setCurrent(dirName);

  QFile file;
  mesh_t *mesh = glWidget->mesh;
  
  // Elmer's elements codes are smaller than 1000
  int maxcode = 1000;
  int *bulk_by_type = new int[maxcode];
  int *boundary_by_type = new int[maxcode];

  for(int i=0; i<maxcode; i++) {
    bulk_by_type[i] = 0;
    boundary_by_type[i] = 0;
  }

  for(int i=0; i < mesh->elements; i++) {
    element_t *e = &mesh->element[i];

    if(e->nature == PDE_BULK) 
      bulk_by_type[e->code]++;

    if(e->nature == PDE_BOUNDARY)
      boundary_by_type[e->code]++;
  }

  for(int i=0; i < mesh->surfaces; i++) {
    surface_t *s = &mesh->surface[i];

    if(s->nature == PDE_BULK)
      bulk_by_type[s->code]++;

    if(s->nature == PDE_BOUNDARY)
      boundary_by_type[s->code]++;
  }

  for(int i=0; i < mesh->edges; i++) {
    edge_t *e = &mesh->edge[i];

    if(e->nature == PDE_BULK)
      bulk_by_type[e->code]++;

    if(e->nature == PDE_BOUNDARY)
      boundary_by_type[e->code]++;
  }

  for(int i=0; i < mesh->points; i++) {
    point_t *p = &mesh->point[i];

    if(p->nature == PDE_BULK)
      bulk_by_type[p->code]++;

    if(p->nature == PDE_BOUNDARY)
      boundary_by_type[p->code]++;
  }

  int bulk_elements = 0;
  int boundary_elements = 0;
  int element_types = 0;

  for(int i=0; i<maxcode; i++) {
    bulk_elements += bulk_by_type[i];
    boundary_elements += boundary_by_type[i];

    if((bulk_by_type[i]>0) || (boundary_by_type[i]>0))
      element_types++;
  }

  // Header:
  file.setFileName("mesh.header");
  file.open(QIODevice::WriteOnly);
  QTextStream mesh_header(&file);

  cout << "Saving " << mesh->nodes << " nodes\n";
  cout << "Saving " << bulk_elements << " elements\n";
  cout << "Saving " << boundary_elements << " boundary elements\n";
  cout.flush();

  mesh_header << mesh->nodes << " ";
  mesh_header << bulk_elements << " ";
  mesh_header << boundary_elements << "\n";

  mesh_header << element_types << "\n";

  for(int i=0; i<maxcode; i++) {
    int j = bulk_by_type[i] + boundary_by_type[i];
    if(j > 0) 
      mesh_header << i << " " << j << "\n";
  }

  file.close();

  // Nodes:
  file.setFileName("mesh.nodes");
  file.open(QIODevice::WriteOnly);
  QTextStream nodes(&file);
  
  for(int i=0; i < mesh->nodes; i++) {
    node_t *node = &mesh->node[i];

    int index = node->index;

    nodes << i+1 << " " << index << " ";
    nodes << node->x[0] << " ";
    nodes << node->x[1] << " ";
    nodes << node->x[2] << "\n";
  }

  file.close();

  // Elements:
  file.setFileName("mesh.elements");
  file.open(QIODevice::WriteOnly);
  QTextStream mesh_element(&file);

  int current = 0;

  for(int i=0; i < mesh->elements; i++) {
    element_t *e = &mesh->element[i];
    int index = e->index;
    if(index < 1)
      index = 1;
    if(e->nature == PDE_BULK) {
      mesh_element << ++current << " ";
      mesh_element << index << " ";
      mesh_element << e->code << " ";
      for(int j=0; j < e->nodes; j++) 
	mesh_element << e->node[j]+1 << " ";
      mesh_element << "\n";
    }
  }

  for(int i=0; i < mesh->surfaces; i++) {
    surface_t *s = &mesh->surface[i];
    int index = s->index;
    if(index < 1)
      index = 1;
    if(s->nature == PDE_BULK) {
      mesh_element << ++current << " ";
      mesh_element << index << " ";
      mesh_element << s->code << " ";
      for(int j=0; j < s->nodes; j++) 
	mesh_element << s->node[j]+1 << " ";
      mesh_element << "\n";
    }
  }

  for(int i=0; i < mesh->edges; i++) {
    edge_t *e = &mesh->edge[i];
    int index = e->index;
    if(index < 1)
      index = 1;
    if(e->nature == PDE_BULK) {
      mesh_element << ++current << " ";
      mesh_element << index << " ";
      mesh_element << e->code << " ";
      for(int j=0; j<e->nodes; j++)
	mesh_element << e->node[j]+1 << " ";
      mesh_element << "\n";
    }
  }

  for(int i=0; i < mesh->points; i++) {
    point_t *p = &mesh->point[i];
    int index = p->index;
    if(index < 1)
      index = 1;
    if(p->nature == PDE_BULK) {
      mesh_element << ++current << " ";
      mesh_element << index << " ";
      mesh_element << p->code << " ";
      for(int j=0; j < p->nodes; j++)
	mesh_element << p->node[j]+1 << " ";
      mesh_element << "\n";
    }
  }

  file.close();
  
  // Boundary elements:
  file.setFileName("mesh.boundary");
  file.open(QIODevice::WriteOnly);
  QTextStream mesh_boundary(&file);

  current = 0;

  for(int i=0; i < mesh->surfaces; i++) {
    surface_t *s = &mesh->surface[i];
    int e0 = s->element[0] + 1;
    int e1 = s->element[1] + 1;
    if(e0 < 0)
      e0 = 0;
    if(e1 < 0)
      e1 = 0;
    int index = s->index;
    if(index < 1)
      index = 1;
    if(s->nature == PDE_BOUNDARY) {
      mesh_boundary << ++current << " ";
      mesh_boundary << index << " ";
      mesh_boundary << e0 << " " << e1 << " ";
      mesh_boundary << s->code << " ";
      for(int j=0; j < s->nodes; j++) 
	mesh_boundary << s->node[j]+1 << " ";
      mesh_boundary << "\n";
    }
  }

  for(int i=0; i < mesh->edges; i++) {
    edge_t *e = &mesh->edge[i];
    int s0 = e->surface[0] + 1;
    int s1 = e->surface[1] + 1;
    if(s0 < 0)
      s0 = 0;
    if(s1 < 0)
      s1 = 0;
    int index = e->index;
    if(index < 1)
      index = 1;
    if(e->nature == PDE_BOUNDARY) {
      mesh_boundary << ++current << " ";
      mesh_boundary << index << " ";
      mesh_boundary << s0 << " " << s1 << " ";
      mesh_boundary << e->code << " ";
      for(int j=0; j < e->nodes; j++) 
	mesh_boundary << e->node[j]+1 << " ";
      mesh_boundary << "\n";
    }
  }

  for(int i=0; i < mesh->points; i++) {
    point_t *p = &mesh->point[i];
    int e0 = p->edge[0] + 1;
    int e1 = p->edge[1] + 1;
    if(e0 < 0)
      e0 = 0;
    if(e1 < 0)
      e1 = 0;
    int index = p->index;
    if(index < 1)
      index = 1;
    if(p->nature == PDE_BOUNDARY) {
      mesh_boundary << ++current << " ";
      mesh_boundary << index << " ";
      mesh_boundary << e0 << " " << e1 << " ";
      mesh_boundary << p->code << " ";
      for(int j=0; j < p->nodes; j++) 
	mesh_boundary << p->node[j]+1 << " ";
      mesh_boundary << "\n";
    }
  }

  file.close();

  // Sif:
  file.setFileName("skeleton.sif");
  file.open(QIODevice::WriteOnly);
  QTextStream sif(&file);

  QApplication::setOverrideCursor(Qt::WaitCursor);
  sif << sifWindow->textEdit->toPlainText();
  QApplication::restoreOverrideCursor();

  file.close();

  // ELMERSOLVER_STARTINFO:
  file.setFileName("ELMERSOLVER_STARTINFO");
  file.open(QIODevice::WriteOnly);
  QTextStream startinfo(&file);

  startinfo << "skeleton.sif\n1\n";

  file.close();

  delete [] bulk_by_type;
  delete [] boundary_by_type;

  statusBar()->showMessage(tr("Ready"));
}




// Boundady selected by double clicking (signaled by glWidget::select):
//-----------------------------------------------------------------------------
void MainWindow::boundarySelectedSlot(list_t *l)
{
  QString qs;

  if(l->index < 0) {
    statusBar()->showMessage("Ready");    
    return;
  }

  if(!l->selected) {
    if(l->type == SURFACELIST) {
      qs = "Selected surface " + QString::number(l->index);
    } else if(l->type == EDGELIST) {
      qs = "Selected edge " + QString::number(l->index);
    } else {
      qs = "Selected object " + QString::number(l->index) + " (type unknown)";
    }
  } else {
    if(l->type == SURFACELIST) {
      qs = "Unselected surface " + QString::number(l->index);
    } else if(l->type == EDGELIST) {
      qs = "Unselected edge " + QString::number(l->index);
    } else {
      qs = "Unselected object " + QString::number(l->index) + " (type unknown)";
    }
  }

  statusBar()->showMessage(qs);    
  
  // Find the boundary condition block in sif:
  if(l->nature == PDE_BOUNDARY) {
    QTextEdit *te = sifWindow->textEdit;
    QTextCursor cursor = te->textCursor();
    
    te->moveCursor(QTextCursor::Start);
    qs = "Target boundaries(1) = " + QString::number(l->index);
    bool found = te->find(qs);
    
    // Select and highlight bc block:
    if(found) {
      te->moveCursor(QTextCursor::Up);
      te->moveCursor(QTextCursor::Up);
      te->find("Boundary");
      
      cursor.movePosition(QTextCursor::StartOfWord, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      cursor.select(QTextCursor::BlockUnderCursor);
    }
  }

  // Find the body block in sif:
  if(l->nature == PDE_BULK) {
    QTextEdit *te = sifWindow->textEdit;
    QTextCursor cursor = te->textCursor();

    te->moveCursor(QTextCursor::Start);
    qs = "Target bodies(1) = " + QString::number(l->index);
    bool found = te->find(qs);
    
    // Select and highlight body block:
    if(found) {
      te->moveCursor(QTextCursor::Up);
      te->moveCursor(QTextCursor::Up);
      te->moveCursor(QTextCursor::Up);
      te->find("Body");
      
      cursor.movePosition(QTextCursor::StartOfWord, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      te->moveCursor(QTextCursor::Down, QTextCursor::KeepAnchor);
      cursor.select(QTextCursor::BlockUnderCursor);
    }
  }
}




// Read input file and populate mesh generator's input structures:
//-----------------------------------------------------------------------------
void MainWindow::readInputFile(QString fileName)
{
  char cs[1024];

  QFileInfo fi(fileName);
  QString absolutePath = fi.absolutePath();
  QString baseName = fi.baseName();
  QString fileSuffix = fi.suffix();
  QString baseFileName = absolutePath + "/" + baseName;
  sprintf(cs, "%s", (const char*)(baseFileName.toAscii()));

  activeGenerator = GEN_UNKNOWN;
  tetlibInputOk = false;
  nglibInputOk = false;

  // Choose generator according to fileSuffix:
  //------------------------------------------
  if((fileSuffix == "smesh") || 
     (fileSuffix == "poly")) {

    if(!tetlibPresent) {
      logMessage("unable to mesh - tetlib unavailable");
      return;
    }

    activeGenerator = GEN_TETLIB;
    cout << "Selected tetlib for smesh/poly-format" << endl;

    in->deinitialize();
    in->initialize();
    in->load_poly(cs);

    tetlibInputOk = true;

  } else if(fileSuffix == "off") {

    if(!tetlibPresent) {
      logMessage("unable to mesh - tetlib unavailable");
      return;
    }

    activeGenerator = GEN_TETLIB;
    cout << "Selected tetlib for off-format" << endl;

    in->deinitialize();
    in->initialize();
    in->load_off(cs);

    tetlibInputOk = true;

  } else if(fileSuffix == "ply") {

    if(!tetlibPresent) {
      logMessage("unable to mesh - tetlib unavailable");
      return;
    }

    activeGenerator = GEN_TETLIB;
    cout << "Selected tetlib for ply-format" << endl;

    in->deinitialize();
    in->initialize();
    in->load_ply(cs);

    tetlibInputOk = true;

  } else if(fileSuffix == "mesh") {

    if(!tetlibPresent) {
      logMessage("unable to mesh - tetlib unavailable");
      return;
    }

    activeGenerator = GEN_TETLIB;
    cout << "Selected tetlib for mesh-format" << endl;

    in->deinitialize();
    in->initialize();
    in->load_medit(cs);

    tetlibInputOk = true;

  } else if(fileSuffix == "stl") {

    // for stl there are two alternative generators:
    if(meshControl->generatorType == GEN_NGLIB) {
      
      cout << "nglib" << endl;

      if(!nglibPresent) {
	logMessage("unable to mesh - nglib unavailable");
	return;
      }
      
      activeGenerator = GEN_NGLIB;
      cout << "Selected nglib for stl-format" << endl;

      nglibAPI->Ng_Init();
      
      nggeom = nglibAPI->Ng_STL_LoadGeometry((const char*)(fileName.toAscii()), 0);
      
      if(!nggeom) {
	logMessage("Ng_STL_LoadGeometry failed");
	return;
      }
      
      int rv = nglibAPI->Ng_STL_InitSTLGeometry(nggeom);
      cout << "InitSTLGeometry: NG_result=" << rv << endl;
      cout.flush();
      
      nglibInputOk = true;
      
    } else {

      if(!tetlibPresent) {
	logMessage("unable to mesh - tetlib unavailable");
	return;
      }
      
      activeGenerator = GEN_TETLIB;
      cout << "Selected tetlib for stl-format" << endl;
      
      in->deinitialize();
      in->initialize();
      in->load_stl(cs);
      
      tetlibInputOk = true;
      
    }

  } else if((fileSuffix == "grd") ||
	    (fileSuffix == "FDNEUT") ||
	    (fileSuffix == "msh") ||
	    (fileSuffix == "mphtxt") ||
	    (fileSuffix == "unv")) {

    activeGenerator = GEN_ELMERGRID;
    cout << "Selected elmergrid" << endl;

    int errstat = elmergridAPI->loadElmerMeshStructure((const char*)(fileName.toAscii()));
    
    if (errstat)
      logMessage("loadElmerMeshStructure failed!");

    return;

  } else {

    logMessage("Unable to open file: file type unknown");
    activeGenerator = GEN_UNKNOWN;
    return;

  }
}
  


// Populate elmer's mesh structure and make GL-lists (tetlib):
//-----------------------------------------------------------------------------
void MainWindow::makeElmerMeshFromTetlib()
{
  meshutils->clearMesh(glWidget->mesh);
  glWidget->mesh = tetlibAPI->createElmerMeshStructure();

  glWidget->rebuildLists();

  logMessage("Input file processed");
}


// Populate elmer's mesh structure and make GL-lists (nglib):
//-----------------------------------------------------------------------------
void MainWindow::makeElmerMeshFromNglib()
{
  meshutils->clearMesh(glWidget->mesh);
  nglibAPI->ngmesh = this->ngmesh;
  glWidget->mesh = nglibAPI->createElmerMeshStructure();

  glWidget->rebuildLists();

  logMessage("Input file processed");
}



// Make solver input file for steady heat conduction...
//-----------------------------------------------------------------------------
void MainWindow::makeSteadyHeatSifSlot()
{
  if(glWidget->mesh == NULL) {
    logMessage("Unable to create sif: no mesh");
    return;
  }
  
  int dim = glWidget->mesh->dim, cdim = glWidget->mesh->cdim;

  if(dim < 1) {
    logMessage("Model dimension inconsistent with SIF syntax");
    return;
  }

  QTextEdit *te = sifWindow->textEdit;

  te->clear();

  te->append("! Sif skeleton for steady heat conduction\n");

  te->append("Header");
  te->append("  CHECK KEYWORDS Warn");
  te->append("  Mesh DB \".\" \".\"");
  te->append("  Include Path \"\"");
  te->append("  Results Directory \"\"");
  te->append("End\n");
  
  te->append("Simulation");
  te->append("  Max Output Level = 4");
  te->append("  Coordinate System = \"Cartesian\"");
  te->append("  Coordinate Mapping(3) = 1 2 3");
  te->append("  Simulation Type = \"Steady State\"");
  te->append("  Steady State Max Iterations = 1");
  te->append("  Output Intervals = 1");
  te->append("  Solver Input File = \"skeleton.sif\"");
  te->append("  Post File = \"skeleton.ep\"");
  te->append("End\n");

  te->append("Constants");
  te->append("  Gravity(4) = 0 -1 0 9.82");
  te->append("  Stefan Boltzmann = 5.67e-08");
  te->append("End\n");

  // Body blocks:
  //-------------
  makeSifBodyBlocks();

  te->append("Equation 1");
  te->append("  Name = \"Heat equation\"");
  te->append("  Active Solvers(1) = 1");
  te->append("End\n");

  te->append("Solver 1");
  te->append("  Exec Solver = \"Always\"");
  te->append("  Equation = \"Heat Equation\"");
  te->append("  Variable = \"Temperature\"");
  te->append("  Variable Dofs = 1");
  te->append("  Linear System Solver = \"Iterative\"");
  te->append("  Linear System Iterative Method = \"BiCGStab\"");
  te->append("  Linear System Max Iterations = 350");
  te->append("  Linear System Convergence Tolerance = 1.0e-08");
  te->append("  Linear System Abort Not Converged = True");
  te->append("  Linear System Preconditioning = \"ILU0\"");
  te->append("  Linear System Residual Output = 1");
  te->append("  Nonlinear System Convergence Tolerance = 1.0e-08");
  te->append("  Nonlinear System Max Iterations = 1");
  te->append("  Steady State Convergence Tolerance = 1.0e-08");
  te->append("End\n");

  te->append("Material 1");
  te->append("  Name = \"Material1\"");
  te->append("  Density = 1");
  te->append("  Heat Conductivity = 1");
  te->append("End\n");

  te->append("Body Force 1");
  te->append("  Name = \"BodyForce1\"");
  te->append("  Heat Source = 1");
  te->append("End\n");

  // BC-blocks:
  //-----------
  QString BCtext = "!  Temperature = 0\n!  Heat flux = 0";
  makeSifBoundaryBlocks(BCtext);
}



// Make solver input file for linear elasticity...
//-----------------------------------------------------------------------------
void MainWindow::makeLinElastSifSlot()
{
  if(glWidget->mesh == NULL) {
    logMessage("Unable to create sif: no mesh");
    return;
  }
  
  int dim = glWidget->mesh->dim, cdim = glWidget->mesh->cdim;

  if(dim < 1) {
    logMessage("Model dimension inconsistent with SIF syntax");
    return;
  }

  QTextEdit *te = sifWindow->textEdit;

  te->clear();

  te->append("! Sif skeleton for linear elasticity\n");

  te->append("Header");
  te->append("  CHECK KEYWORDS Warn");
  te->append("  Mesh DB \".\" \".\"");
  te->append("  Include Path \"\"");
  te->append("  Results Directory \"\"");
  te->append("End\n");
  
  te->append("Simulation");
  te->append("  Max Output Level = 4");
  te->append("  Coordinate System = \"Cartesian\"");
  te->append("  Coordinate Mapping(3) = 1 2 3");
  te->append("  Simulation Type = \"Steady State\"");
  te->append("  Steady State Max Iterations = 1");
  te->append("  Output Intervals = 1");
  te->append("  Solver Input File = \"skeleton.sif\"");
  te->append("  Post File = \"skeleton.ep\"");
  te->append("End\n");

  te->append("Constants");
  te->append("  Gravity(4) = 0 -1 0 9.82");
  te->append("  Stefan Boltzmann = 5.67e-08");
  te->append("End\n");

  // Body blocks:
  //-------------
  makeSifBodyBlocks();

  te->append("Equation 1");
  te->append("  Name = \"Elasticity analysis\"");
  te->append("  Active Solvers(1) = 1");
  te->append("End\n");

  te->append("Solver 1");
  te->append("  Exec Solver = \"Always\"");
  te->append("  Equation = \"Elasticity analysis\"");
  te->append("  Procedure = \"StressSolve\" \"StressSolver\"");
  te->append("  Variable = \"Displacement\"");
  if(cdim == 3)
    te->append("  Variable Dofs = 3");
  if(cdim == 2)
    te->append("  Variable Dofs = 2");
  if(cdim == 1)
    te->append("  Variable Dofs = 1");
  te->append("  Linear System Solver = \"Iterative\"");
  te->append("  Linear System Iterative Method = \"BiCGStab\"");
  te->append("  Linear System Max Iterations = 350");
  te->append("  Linear System Convergence Tolerance = 1.0e-08");
  te->append("  Linear System Abort Not Converged = True");
  te->append("  Linear System Preconditioning = \"ILU0\"");
  te->append("  Linear System Residual Output = 1");
  te->append("  Nonlinear System Convergence Tolerance = 1.0e-08");
  te->append("  Nonlinear System Max Iterations = 1");
  te->append("  Steady State Convergence Tolerance = 1.0e-08");
  te->append("End\n");

  te->append("Material 1");
  te->append("  Name = \"Material1\"");
  te->append("  Density = 1");
  te->append("  Youngs modulus = 1");
  te->append("  Poisson ratio = 0.3");
  te->append("End\n");

  te->append("Body Force 1");
  te->append("  Name = \"BodyForce1\"");
  if(cdim >= 1) 
    te->append("  Stress BodyForce 1 = 1");
  if(cdim >= 2) 
    te->append("  Stress BodyForce 2 = 0");
  if(cdim >= 3) 
    te->append("  Stress BodyForce 3 = 0");
  te->append("End\n");

  // BC-blocks:
  //-----------
  QString BCtext = "";
  if(cdim >= 1)
    BCtext.append("!  Displacement 1 = 0");
  if(cdim >= 2)
    BCtext.append("\n!  Displacement 2 = 0");
  if(cdim >= 3)
    BCtext.append("\n!  Displacement 3 = 0");
  makeSifBoundaryBlocks(BCtext);
}


// Make body blocks in SIF:
//-----------------------------------------------------------------------------
void MainWindow::makeSifBodyBlocks()
{
  mesh_t *mesh = glWidget->mesh;
  QTextEdit *te = sifWindow->textEdit;

  // find out mesh domain ids:
  // -------------------------
  char str[1024];
  int maxindex=-1;
  for( int i=0; i<mesh->elements; i++)
  {
    element_t *element=&mesh->element[i];
    if ( element->nature==PDE_BULK && element->index > maxindex )
      maxindex = element->index;
  }

  for( int i=0; i<mesh->surfaces; i++)
  {
    element_t *element=&mesh->surface[i];
    if ( element->nature==PDE_BULK && element->index > maxindex )
      maxindex = element->index;
  }

  for( int i=0; i<mesh->edges; i++)
  {
    element_t *element=&mesh->edge[i];
    if ( element->nature==PDE_BULK && element->index > maxindex )
      maxindex = element->index;
  }

  for( int i=0; i<mesh->points; i++)
  {
    element_t *element=&mesh->point[i];
    if ( element->nature==PDE_BULK && element->index > maxindex )
      maxindex = element->index;
  }
  maxindex++;

  if(maxindex == 0)
    return;

  bool *body_tmp = new bool[maxindex];
  int  *body_id  = new  int[maxindex];

  for(int i=0; i<maxindex; i++)
    body_tmp[i] = false;

  maxindex = 0;

  for(int i=0; i <mesh->elements; i++) {
    element_t *element = &mesh->element[i];

    if(element->nature == PDE_BULK)
      if ( !body_tmp[element->index] ) {
        body_tmp[element->index] = true;
        body_id[maxindex++] = element->index;
      }
  }

  for(int i=0; i <mesh->surfaces; i++) {
    element_t *element = &mesh->surface[i];
    if(element->nature == PDE_BULK)
      if ( !body_tmp[element->index] ) {
        body_tmp[element->index] = true;
        body_id[maxindex++] = element->index;
      }
  }

  for(int i=0; i <mesh->edges; i++) {
    element_t *element = &mesh->edge[i];
    if(element->nature == PDE_BULK)
      if ( !body_tmp[element->index] ) {
        body_tmp[element->index] = true;
        body_id[maxindex++] = element->index;
      }
  }

  for(int i=0; i <mesh->points; i++) {
    element_t *element = &mesh->point[i];
    if(element->nature == PDE_BULK)
      if ( !body_tmp[element->index] ) {
        body_tmp[element->index] = true;
        body_id[maxindex++] = element->index;
      }
  }

  te->append("Body 1");
  te->append("  Name = \"Body1\"");
  sprintf( str, "  Target Bodies(%d) =", maxindex );
  for( int i=0; i<maxindex; i++ ) 
     sprintf( str, "%s %d", str, max(body_id[i],1) );

  delete [] body_tmp;
  delete [] body_id;

  te->append(str);
  te->append("  Body Force = 1");
  te->append("  Equation = 1");
  te->append("  Material = 1");
  te->append("End\n");
}


// Make boundary condition blocks in SIF:
//-----------------------------------------------------------------------------
void MainWindow::makeSifBoundaryBlocks(QString BCtext)
{
  mesh_t *mesh = glWidget->mesh;
  QTextEdit *te = sifWindow->textEdit;

  int maxindex = -1;
  for(int i=0; i < mesh->surfaces; i++) {
    element_t *element = &mesh->surface[i];
    if((element->nature == PDE_BOUNDARY) && (element->index > maxindex))
      maxindex = element->index;
  }
  for(int i=0; i < mesh->edges; i++) {
    element_t *element = &mesh->edge[i];
    if((element->nature == PDE_BOUNDARY) && (element->index > maxindex))
      maxindex = element->index;
  }
  for(int i=0; i < mesh->points; i++) {
    element_t *element = &mesh->point[i];
    if((element->nature == PDE_BOUNDARY) && (element->index > maxindex))
      maxindex = element->index;
  }
  maxindex++;

  if(maxindex == 0)
    return;

  bool *tmp = new bool[maxindex];

  for(int i=0; i<maxindex; i++) tmp[i] = false;

  for(int i=0; i < mesh->surfaces; i++) {
    element_t *element = &mesh->surface[i];
    if( element->nature == PDE_BOUNDARY )
      tmp[element->index] = true;
  }
  for(int i=0; i < mesh->edges; i++) {
    element_t *element = &mesh->edge[i];
    if( element->nature == PDE_BOUNDARY )
      tmp[element->index] = true;
  }
  for(int i=0; i < mesh->points; i++) {
    element_t *element = &mesh->point[i];
    if( element->nature == PDE_BOUNDARY )
      tmp[element->index] = true;
  }

  int j = 0;
  for(int i=1; i < maxindex; i++) {
    if(tmp[i]) {
      te->append("Boundary condition " + QString::number(++j));
      te->append("  Target boundaries(1) = " + QString::number(i));
      te->append(BCtext);
      te->append("End\n");
    }
  }

  delete [] tmp;
}



// About dialog...
//-----------------------------------------------------------------------------
void MainWindow::showaboutSlot()
{
  QMessageBox::about(this, tr("Information about Mesh3D"),
		     tr("Mesh3D is a preprocessor for three dimensional "
			"modeling with Elmer finite element software. "
			"The program can use elmergrid, tetlib, and nglib, "
			"as finite element mesh generators:\n\n"
			"http://www.csc.fi/elmer/\n"
			"http://tetgen.berlios.de/\n"
			"http://www.hpfem.jku.at/netgen/\n\n"
			"Written by Mikko Lyly, Juha Ruokolainen, and "
			"Peter R�back, 2008"));
}


// Log message...
//-----------------------------------------------------------------------------
void MainWindow::logMessage(QString message)
{
  cout << string(message.toAscii()) << endl;
  statusBar()->showMessage(message);
  cout.flush();
}
