#include "../config.h"

void STDCALLBULL FC_FUNC_(mpi_init,MPI_INIT) 
     (int *p) { *p = 0; }
void STDCALLBULL FC_FUNC_(mpi_comm_size,MPI_COMM_SIZE) 
     (int *a, int *b, int *c) { *b = 1; *c = 0;}
void STDCALLBULL FC_FUNC_(mpi_comm_rank,MPI_COMM_RANK) 
     (int *a, int *b, int *c) { *b = 0; *c = 0;}
void STDCALLBULL FC_FUNC_(mpi_recv,MPI_RECV) 
     (int *a,int *b,int *c,int *d,int *e,int *f,int *g,int *h) {}
void STDCALLBULL FC_FUNC_(mpi_send,MPI_SEND)
     (int *a,int *b,int *c,int *d,int *e,int *f,int *g) {}
void STDCALLBULL FC_FUNC_(mpi_bcast,MPI_BCAST) () {}
void STDCALLBULL FC_FUNC_(mpi_barrier,MPI_BARRIER)
     (int *a,int *b) {}
void STDCALLBULL FC_FUNC_(mpi_finalize,MPI_FINALIZE)
     (int *a) {}
void STDCALLBULL FC_FUNC_(mpi_dup_fn,MPI_DUP_FN) () {}
void STDCALLBULL FC_FUNC_(mpi_null_copy_fn,MPI_NULL_COPY_FN) () {}
void STDCALLBULL FC_FUNC_(mpi_buffer_detach,MPI_BUFFER_DETACH) ( void *buf, int *i, int *ierr ) {}
void STDCALLBULL FC_FUNC_(mpi_bsend,MPI_BSEND) (void *a, void *b, void *c, void *d, void *e, void *f, void *g ) {}
void STDCALLBULL FC_FUNC_(mpi_null_delete_fn,MPI_NULL_DELETE_FN) () {}
void STDCALLBULL FC_FUNC_(mpi_buffer_attach,MPI_BUFFER_ATTACH) ( void *buf, int *i, int *ierr ) {}
void STDCALLBULL FC_FUNC_(mpi_allreduce,MPI_ALLREDUCE) () {}
void STDCALLBULL FC_FUNC_(mpi_wtime,MPI_WTIME) () {}
void STDCALLBULL FC_FUNC_(mpi_wtick,MPI_WTICK) () {}
void STDCALLBULL FC_FUNC_(pmpi_wtime,PMPI_WTIME) () {}
void STDCALLBULL FC_FUNC_(pmpi_wtick,PMPI_WTICK) () {}

/* parpack */
void STDCALLBULL FC_FUNC(pdneupd,PDNEUPD) ( void *a, void *b, void *c, void *d, void *e, void *f, void *g, void *a8, void *b9, void *c10, void *d11, void *e12, void *f13, void *g14, void *a15, void *b16, void *c17, void *d18, void *e19, void *a20, void *b21, void *c22, void *d23, void *e24, void *f25, void *g26, void *g27, void *g28,void *g29 ) {}
void STDCALLBULL FC_FUNC(pdseupd,PDSEUPD) ( void *a, void *b, void *c, void *d, void *e, void *f, void *g, void *a8, void *b9, void *c10, void *d11, void *e12, void *f13, void *g14, void *a15, void *b16, void *c17, void *d18, void *e19, void *a20, void *b21, void *c22, void *d23, void *e24, void *f25, void *g26  ) {}
void STDCALLBULL FC_FUNC(pdsaupd,PDSAUPD) ( void *a, void *b, void *c, void *d, void *e, void *f, void *g, void *a8, void *b9, void *c10, void *d11, void *e12, void *f13, void *g14, void *a15, void *b16, void *c17, void *d18, void *e19 ) {}
void STDCALLBULL FC_FUNC(pdnaupd,PDNAUPD) ( void *a, void *b, void *c, void *d, void *e, void *f, void *g, void *a8, void *b9, void *c10, void *d11, void *e12, void *f13, void *g14, void *a15, void *b16, void *c17, void *d18, void *e19 ) {}
