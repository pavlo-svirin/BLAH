/*
 *  File :     blah_job_registry_scan_by_subject.c
 *
 *  Author :   Francesco Prelz ($Author: fprelz $)
 *  e-mail :   "francesco.prelz@mi.infn.it"
 *
 *  Revision history :
 *   5-May-2009 Original release
 *
 *  Description:
 *   Executable to look up for entries in the BLAH job registry
 *   that match a given proxy subject, and print them in variable
 *   formats.
 *
 *  Copyright (c) 2007 Istituto Nazionale di Fisica Nucleare (INFN).
 *   All rights reserved.
 *   See http://grid.infn.it/grid/license.html for license details.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include "classad_c_helper.h"
#include "job_registry.h"
#include "config.h"

void
undo_escapes(char *string)
{
  char *rp,*wp,ec;
  char nc2,nc3;

  if (string == NULL) return;

  for (rp = string, wp = string; (*rp != '\000'); rp++, wp++)
   {
    if (*rp == '\\')
     {
      ec = *(rp+1);
      switch (ec)
       {
        case 'a': *wp = '\a'; rp++; break;
        case 'b': *wp = '\b'; rp++; break;
        case 'f': *wp = '\f'; rp++; break;
        case 'n': *wp = '\n'; rp++; break;
        case 'r': *wp = '\r'; rp++; break;
        case 't': *wp = '\t'; rp++; break;
        case 'v': *wp = '\v'; rp++; break;
        case '\\': *wp = '\\'; rp++; break;
        case '\?': *wp = '\?'; rp++; break;
        case '\'': *wp = '\''; rp++; break;
        case '\"': *wp = '\"'; rp++; break;
        default: 
          /* Do we have a numeric escape sequence ? */
          if ( (nc2 = *(rp+2)) != '\000' &&
               (nc3 = *(rp+3)) != '\000' )
           {

            if (ec == 'x')
             {
              /* hex char */
              if (nc2 >= 'A' && nc2 <= 'F') nc2 -= ('A' - '9' - 1);
              if (nc2 >= 'a' && nc2 <= 'f') nc2 -= ('a' - '9' - 1);
              if (nc3 >= 'A' && nc3 <= 'F') nc3 -= ('A' - '9' - 1);
              if (nc3 >= 'a' && nc3 <= 'f') nc3 -= ('a' - '9' - 1);
              nc2 -= '0';
              nc3 -= '0';
              if (nc2 >= 0 && nc2 <= 15 && nc3 >= 0 && nc3 <= 15)
               {
                *wp = (nc2*16 + nc3);
                rp+=3; 
                break;
               }
             }
            if (ec >= '0' && ec <= '9' && nc2 >= '0' && nc2 <= '9' &&
                                          nc3 >= '0' && nc3 <= '9')
             {
              /* Octal char */
              ec  -= '0';
              nc2 -= '0';
              nc3 -= '0';
              *wp = (ec * 64 + nc2 * 8 + nc3);
              rp+=3; 
              break;
             }
           }
          if (ec == '0') *wp = '\0'; rp++; break;
          /* True 'default' case: Nothing could be figured out */
          if (rp != wp) *wp = *rp;
       } 
     }
    else if (rp != wp) *wp = *rp;
   }
  /* Terminate the string */
  if (rp != wp) *wp = '\000';
}

typedef enum format_type_e
{
  NO_FORMAT,
  FORMAT_INT,
  FORMAT_STRING,
  FORMAT_FLOAT,
  FORMAT_UNKNOWN
} format_type;

format_type
get_format_type(char *fmt, int which, int *totfmts)
{
  char *pc;
  char *sp;
  char *start, *end;
  int nf = 0;
  format_type result = NO_FORMAT;

  start = fmt;
  for(start = fmt; ((pc = strchr(start, '%')) != NULL); start = end+1)
   {
    end = pc;
    if (*(pc+1) == '%') continue;

    for (end = pc+1; *end != '\000'; end++)
     {
      /* Skip over format qualifiers */
      if (*end <  '0' || ( *end >  '9' && *end != '#' &&
          *end != ' ' && *end != '-' && *end != '+' &&
          *end != '\'' && *end != '.' && *end != 'l' &&
          *end != 'L' && *end != 'h' && *end != 'q' &&
          *end != 'j' && *end != 'q' && *end != 'z' &&
          *end != 't' ) ) break;
     }

    if (*end == '\000') break;

    nf++;
    if (nf == which)
     {
      switch (*end)
       {
        case 's':
          result = FORMAT_STRING;
          break;
        case 'x':
        case 'X':
        case 'o':
        case 'd':
        case 'i':
        case 'u':
          result = FORMAT_INT;
          break;
        case 'a':
        case 'A':
        case 'e':
        case 'E':
        case 'f':
        case 'F':
        case 'g':
        case 'G':
          result = FORMAT_FLOAT;
          break;
        default:
          result = FORMAT_UNKNOWN;
       }
      if (totfmts == NULL) break;
     }
   }
  if (totfmts != NULL) *totfmts = nf;
  return result;
}

#define USAGE_STRING "ERROR Usage: %s (<-s (proxy subject)>|<-h (proxy subject hash>) [-j job status] \"Optional arg1 format\" arg1 \"Optional arg2 format\" arg2, etc.\n"
int
main(int argc, char *argv[])
{
  char *registry_file=NULL, *registry_file_env=NULL;
  int need_to_free_registry_file = FALSE;
  const char *default_registry_file = "blah_job_registry.bjr";
  char *my_home;
  job_registry_entry hen, *ren;
  char *cad;
  classad_context pcad;
  config_handle *cha;
  config_entry *rge;
  job_registry_handle *rha;
  FILE *fd;
  char *arg = "";
  int iarg;
  char *looked_up_subject = NULL;
  char *lookup_subject = NULL;
  char *lookup_hash = NULL;
  int cur_arg;
  int format_args;
  int select_by_job_status = -1;
  int ifr;
  int njobs = 0;
  format_type first_fmt;
  int nfmts;
 
  if (argc < 2)
   {
    fprintf(stderr,USAGE_STRING,argv[0]);
    return 1;
   }

  cur_arg = 1;

  while (argv[cur_arg][0] == '-')
   {
    format_args = -1;
    /* Look up for command line switches */
    if (strlen(argv[cur_arg]) > 2)
     {
      arg = argv[cur_arg] + 2;
      if (argc > (cur_arg+1))
       {
        format_args = cur_arg+1;
       }
     }
    else if (argc > (cur_arg+1))
     {
      arg = argv[cur_arg+1]; 
       if (argc > (cur_arg+2))
        {
         format_args = cur_arg+2;
        }
     }

    if (strlen(arg) <= 0)
     {
      fprintf(stderr,USAGE_STRING,argv[0]);
      return 1;
     }

    switch (argv[cur_arg][1])
     {
      case 'h':
        if (lookup_hash != NULL)
         {
          fprintf(stderr,USAGE_STRING,argv[0]);
          return 1;
         }
        lookup_hash = arg;
        break;
      case 's':
        if (lookup_hash != NULL)
         {
          fprintf(stderr,USAGE_STRING,argv[0]);
          return 1;
         }
        job_registry_compute_subject_hash(&hen, arg);
        lookup_subject = arg;
        lookup_hash = hen.subject_hash;
        break;
      case 'j':
        select_by_job_status = atoi(arg);
        break;
      default:
        fprintf(stderr,USAGE_STRING,argv[0]);
        return 1;
     }
    if ((format_args > 0) && (format_args < argc)) cur_arg = format_args;
    else break;
   }
    
  if (lookup_hash == NULL)
   {
    fprintf(stderr,USAGE_STRING,argv[0]);
    return 1;
   }

  cha = config_read(NULL); /* Read config from default locations. */
  if (cha != NULL)
   {
    rge = config_get("job_registry",cha);
    if (rge != NULL) registry_file = rge->value;
   }

  /* Env variable takes precedence */
  registry_file_env = getenv("BLAH_JOB_REGISTRY_FILE");
  if (registry_file_env != NULL) registry_file = registry_file_env;

  if (registry_file == NULL)
   {
    my_home = getenv("HOME");
    if (my_home == NULL) my_home = ".";
    registry_file = (char *)malloc(strlen(default_registry_file)+strlen(my_home)+2);
    if (registry_file != NULL) 
     {
      sprintf(registry_file,"%s/%s",my_home,default_registry_file);
      need_to_free_registry_file = TRUE;
     }
    else 
     {
      fprintf(stderr,"ERROR %s: Out of memory.\n",argv[0]);
      if (cha != NULL) config_free(cha);
      return 1;
     }
   }

  rha=job_registry_init(registry_file, NO_INDEX);

  if (rha == NULL)
   {
    fprintf(stderr,"ERROR %s: error initialising job registry: %s\n",argv[0],
            strerror(errno));
    if (cha != NULL) config_free(cha);
    if (need_to_free_registry_file) free(registry_file);
    return 2;
   }

  /* Filename is stored in job registry handle. - Don't need these anymore */
  if (cha != NULL) config_free(cha);
  if (need_to_free_registry_file) free(registry_file);

  looked_up_subject = job_registry_lookup_subject_hash(rha, lookup_hash);
  if (looked_up_subject == NULL)
   {
    fprintf(stderr,"%s: Hash %s is not found in registry %s.\n",argv[0],
            lookup_hash, rha->path);
    job_registry_destroy(rha);
    return 5;
   } else {
    if ((lookup_subject != NULL) && 
        (strcmp(looked_up_subject, lookup_subject) != 0))
     {
      fprintf(stderr, "%s: Warning: cached subject (%s) differs from the requested subject (%s)\n", argv[0], looked_up_subject, lookup_subject);
     }
    free(looked_up_subject);
   }

  fd = job_registry_open(rha, "r");
  if (fd == NULL)
   {
    fprintf(stderr,"ERROR %s: error opening job registry: %s\n",argv[0],
            strerror(errno));
    job_registry_destroy(rha);
    return 2;
   }

  if (job_registry_rdlock(rha, fd) < 0)
   {
    fprintf(stderr,"ERROR %s: error read-locking job registry: %s\n",argv[0],
            strerror(errno));
    fclose(fd);
    job_registry_destroy(rha);
    return 2;
   }

  if (format_args > 0)
   {
    for (ifr = format_args; ifr < argc; ifr+=2) undo_escapes(argv[ifr]);
   }

  while ((ren = job_registry_get_next_hash_match(rha, fd, lookup_hash)) != NULL)
   {
    /* Is the current entry in the requested job status ? */
    if ((select_by_job_status > 0) && (ren->status != select_by_job_status))
      continue;

    njobs++;

    cad = job_registry_entry_as_classad(rha, ren);
    if (cad != NULL)
     {
      if (format_args <= 0)
       {
        printf("%s\n",cad);
       }
      else
       {
        if ((pcad = classad_parse(cad)) == NULL)
         {
          fprintf(stderr,"ERROR %s: Cannot parse classad %s.\n",argv[0],cad);
          free(cad);
          free(ren);
          continue;
         }
        for (ifr = format_args; ifr < argc; ifr+=2)
         {
          first_fmt = get_format_type(argv[ifr], 1, &nfmts);
          if (nfmts == 0) { ifr--; continue; }
          if (nfmts > 1) { continue; } /* Deal with one conversion at a time */
          if ((ifr+1) >= argc)
           {
            printf(argv[ifr]);
           }
          else
           {
            if (strncmp(argv[ifr+1], "Njob", 4) == 0)
             {
              /* Print the order number of the job */
              if (first_fmt == FORMAT_INT) printf(argv[ifr],njobs);
             }
            else if (classad_get_dstring_attribute(pcad, argv[ifr+1], &arg) == C_CLASSAD_NO_ERROR)
             {
              if (first_fmt == FORMAT_STRING) printf(argv[ifr],arg);
              free(arg);
             }
            else if (classad_get_int_attribute(pcad, argv[ifr+1], &iarg) == C_CLASSAD_NO_ERROR)
             {
              if (first_fmt == FORMAT_INT) printf(argv[ifr],iarg);
             }
           }
         }
        classad_free(pcad); 
       }
      free(cad);
     }
    else 
     {
      fprintf(stderr,"ERROR %s: Out of memory.\n",argv[0]);
      free(ren);
      job_registry_destroy(rha);
      return 3;
     }
    free(ren);
   }

  fclose(fd);

  job_registry_destroy(rha);
  return 0;
}