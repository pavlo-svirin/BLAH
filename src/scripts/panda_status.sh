#!/bin/bash

# File:     slurm_status.sh
# Author:   Jaime Frey (jfrey@cs.wisc.edu)
# Based on code by David Rebatto (david.rebatto@mi.infn.it)
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#     http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License.
#

. `dirname $0`/blah_load_config.sh

#if [ -x ${blah_libexec_directory}/slurm_status.py ] ; then
#    exec ${blah_libexec_directory}/slurm_status.py "$@"
#fi

#if [ -z "$slurm_binpath" ] ; then
#  slurm_binpath=/usr/bin
#fi

usage_string="Usage: $0 [-w] [-n]"

echo $0 "$@" >>/tmp/slurm.debug

###############################################################
# Parse parameters
###############################################################

#while getopts "wn" arg 
#do
#    case "$arg" in
#    w) getwn="yes" ;;
#    n) ;;
#    
#    -) break ;;
#    ?) echo $usage_string
#       exit 1 ;;
#    esac
#done

shift `expr $OPTIND - 1`

pars=$*
proxy_dir=~/.blah_jobproxy_dir



export X509_CERT_DIR=/panda/grid-security3/certificates
export X509_USER_PROXY=/panda/proxy

PANDA_HOME=/panda/client
. ${PANDA_HOME}/bin/activate 2>&1 1>/dev/null
#. ${PANDA_HOME}/bin/activate 
#exec 2>>/tmp/stderr



for  reqfull in $pars ; do
  reqjob=`echo $reqfull | sed -e 's/^.*\///'`
  echo $reqfull >> /tmp/reqfull

  staterr=/tmp/${reqjob}_staterr

#echo "running: ${slurm_binpath}/scontrol show job $reqjob" >>~/slurm.debug
  #result=`${slurm_binpath}/scontrol show job $reqjob 2>$staterr`
   result=$( ${PANDA_HOME}/bin/panstat -q $reqjob 2>/tmp/panda_stderr | sed  's/\n//' )
   echo $reqjob $result > /tmp/panstat_stdout

    blah_status=

    case "$result" in
        "defined") 
    	  blah_status=1 
    	;;
        "cancelled")
    	  blah_status=3
    	;;
        "finished")
    	  blah_status=4
          exit_code=0
    	;;
        "activated")
    	  blah_status=1
    	;;
        "starting")
    	  blah_status=1
    	;;
        "holding")
    	  blah_status=2
    	;;
        "failed")
    	  blah_status=4
          exit_code=100
    	;;
        "sent")
    	  blah_status=1
    	;;
        "running")
    	  blah_status=2
    	;;
        "transferring")
    	  blah_status=2
    	;;
         "")
    	  #blah_status=5
    	  blah_status=1
          ;;
    esac

    #echo  -n [BatchJobId=\"$reqjob\"\;JobStatus=\"$blah_status\"\;
    #echo  -n "0[ BatchJobId=\"$reqjob\"; JobStatus=\"$blah_status\";"
    echo  -n "0[ BatchJobId=\"$reqjob\"; JobStatus=$blah_status;"
    #echo  -n "0[ BatchJobId=\"pbs/20181213/$reqjob\"; JobStatus=\"$blah_status\";"
    if [[ $blah_status == 2 ]]; then 
    	#echo -n "ExitCode=\" $exit_code \";"
    	echo -n " WorkerNode=\"titan\";"
    fi 
    if [[ $blah_status == 4 ]]; then 
    	#echo -n "ExitCode=\" $exit_code \";"
    	echo -n " ExitCode=$exit_code;"
    fi 
    echo  " ]"

  # here to download tails for job's stdout/stderr
  # port 25080
  json=$(curl -s http://panda2.pandawms.org:25080/joblogs/${reqjob}/)
  if [[ ! -z "$json" ]]; then
     #stdout
     stdout=$(cat /var/run/condor-panda/${reqjob}-stdout)
     echo ${json} | jq ".stdout" | sed  -e 's/\\n/\n/g' -e 's/\\"/"/g' > "${stdout}"
     #stderr
     stderr=$(cat /var/run/condor-panda/${reqjob}-stderr)
     echo ${json} | jq ".stderr" | sed  -e 's/\\n/\n/g' -e 's/\\"/"/g' > "${stderr}"
  fi

  # fetching output files ===================
  if [[ $blah_status == 4 ]]; then
	  JOB_FILE=$(mktemp /tmp/job_${reqjob}.XXXXXX)
	  curl -s http://panda2.pandawms.org:25080/joblogs/${reqjob}/files > ${JOB_FILE}

	  STDOUT=$(cat /var/run/condor-panda/${reqjob}-stdout)
	  STDERR=$(cat /var/run/condor-panda/${reqjob}-stderr)
          
	  WORKDIR=$(jq ".directory" < ${JOB_FILE} |  tr -d '{},"')

          echo -e "$JOB_FILE\n$STDOUT\n$STDERR\n$WORKDIR" >> /tmp/panstat_stdout
          #ls -l ${JOB_FILE} >> /tmp/panstat_stdout

          echo ============ >> /tmp/panstat_stdout

	  jq  ".fout"  < ${JOB_FILE} | tr -d '{},"' | \
	  sed -n '/./s/ //gp' | while read l; do \
	    FILE=$(base64 -d <<< $(cut -d ':' -f 1 <<< $l)); \
            echo File: ${WORKDIR}/${FILE} >> /tmp/panstat_stdout; \
	    cut -d ':' -f 2 <<< $l | base64 -d | xz -dc > ${WORKDIR}/${FILE} ; \
	  done
	  
          # cut -d ':' -f 2 <<< $l | base64 -d > ${WORKDIR}/${FILE} ; \
	  
	  #jq ".stdout" < ${JOB_FILE} |  tr -d '{},"' | base64 -d | sed -n -e '/<?xml/,/<\/invocation/p' > ${STDOUT}
	  jq ".stdout" < ${JOB_FILE} |  tr -d '{},"' | base64 -d > ${STDOUT}
	  #jq ".stdout" < ${JOB_FILE} |  tr -d '{},"' | base64 -d > /tmp/job_stdout
	  
	  jq ".stderr" < ${JOB_FILE} |  tr -d '{},"' | base64 -d > ${STDERR}
          ls -l ${STDOUT} ${STDERR} 2>&1 >> /tmp/panstat_stdout
          echo ============ >> /tmp/panstat_stdout
	  jq ".stdout" < ${JOB_FILE} |  tr -d '{},"' >> /tmp/panstat_stdout
	
	  cp /tmp/panstat_stdout /tmp/panstat_stdout.${reqjob}

	  #rm ${JOB_FILE}
  fi

  continue



  stat_exit_code=$?
##echo "stat_exit_code=$stat_exit_code" >>~/slurm.debug
#  result=`echo "$result" | awk -v job_id=$reqjob -v proxy_dir=$proxy_dir '
#BEGIN {
#    blah_status = 4
#    slurm_status = ""
#    exit_code = "0"
#}
#
#/JobState=/ {
#    slurm_status = substr( $1, index( $1, "=" ) + 1 )
#}
#
#/ExitCode=/ {
#    if ( split( $4, tmp, "[=:]" ) == 3 ) {
#        exit_code = tmp[2]
#    }
#}
#
#END {
#    if ( slurm_status ~ "BOOT_FAIL" ) { blah_status = 4 }
#    if ( slurm_status ~ "CANCELLED" ) { blah_status = 3 }
#    if ( slurm_status ~ "COMPLETED" ) { blah_status = 4 }
#    if ( slurm_status ~ "CONFIGURING" ) { blah_status = 1 }
#    if ( slurm_status ~ "COMPLETING" ) { blah_status = 2 }
#    if ( slurm_status ~ "FAILED" ) { blah_status = 4 }
#    if ( slurm_status ~ "NODE_FAIL" ) { blah_status = 4 }
#    if ( slurm_status ~ "PENDING" ) { blah_status = 1 }
#    if ( slurm_status ~ "PREEMPTED" ) { blah_status = 4 }
#    if ( slurm_status ~ "RUNNING" ) { blah_status = 2 }
#    if ( slurm_status ~ "SPECIAL_EXIT" ) { blah_status = 4 }
#    if ( slurm_status ~ "STOPPED" ) { blah_status = 2 }
#    if ( slurm_status ~ "SUSPENDED" ) { blah_status = 2 }
#
#    print "[BatchJobId=\"" job_id "\";JobStatus=" blah_status ";"
#    if ( blah_status == 4 ) {
#        print "ExitCode=" exit_code ";"
#    }
#    print "]\n"
#    if ( blah_status == 3 || blah_status == 4 ) {
#        #system( "rm " proxy_dir "/" job_id ".proxy 2>/dev/null" )
#    }
#}
#'
#`
#echo result=$result >>~/slurm.debug

  errout=`cat $staterr`
  rm -f $staterr 2>/dev/null

  if echo "$errout" | grep -q "Invalid job id specified" ; then
    stat_exit_code=0
  fi

  if [ $stat_exit_code -eq 0 ] ; then
    echo 0${result}
#echo 0${result} >>~/slurm.debug
  else
    echo 1Error: ${errout}
#echo 1Error: ${errout} >>~/slurm.debug
  fi

done

exit 0
