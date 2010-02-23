#!/bin/bash
#
# File:     sge_submit.sh
# Author:   Keith Sephton (kms@doc.ic.ac.uk)
#
# Based on pbs_submit.sh 
# Author:   David Rebatto (david.rebatto@mi.infn.it)
#
# Revision history:
#    xx-Apr-2008: Original release
#    11-Nov-2009: Mario David (david@lip.pt). Removed CELL information from $jobID
#
# Description:
#   Submission script for SGE, to be invoked by blahpd server.
#   Usage:
#     sge_submit.sh -c <command> [-i <stdin>] [-o <stdout>] [-e <stderr>] [-w working dir] [-- command's arguments]
#
#  Copyright (c) 2004 Istituto Nazionale di Fisica Nucleare (INFN).
#  All rights reserved.
#  See http://grid.infn.it/grid/license.html for license details.
#
#

#exec 2>> /tmp/submit.log

. `dirname $0`/blah_common_submit_functions.sh

if [ -z "$sge_root" ]; then sge_root="/usr/local/sge/pro"; fi
if [ -r "$sge_root/${sge_cell:-default}/common/settings.sh" ]
then
  . $sge_root/${sge_cell:-default}/common/settings.sh
fi

bls_job_id_for_renewal=JOB_ID

original_args="$@"
bls_parse_submit_options "$@"

bls_setup_all_files

# Write wrapper preamble
cat > $bls_tmp_file << end_of_preamble
#!/bin/bash
# SGE job wrapper generated by `basename $0`
# on `/bin/date`
#
# stgcmd = $bls_opt_stgcmd
# proxy_string = $bls_opt_proxy_string
# proxy_local_file = $bls_proxy_local_file
#
# SGE directives:
#\$ -S /bin/bash
end_of_preamble

#local batch system-specific file output must be added to the submit file
local_submit_attributes_file=${GLITE_LOCATION:-/opt/glite}/bin/sge_local_submit_attributes.sh
if [ -r $local_submit_attributes_file ] ; then
    echo \#\!/bin/sh > $bls_opt_tmp_req_file
    if [ ! -z $bls_opt_req_file ] ; then
        cat $bls_opt_req_file >> $bls_opt_tmp_req_file
    fi
    echo "source $local_submit_attributes_file" >> $bls_opt_tmp_req_file
    chmod +x $bls_opt_tmp_req_file
    $bls_opt_tmp_req_file >> $bls_tmp_file 2> /dev/null
    rm -f $bls_opt_tmp_req_file
fi

if [ ! -z "$bls_opt_xtra_args" ] ; then
    echo -e $bls_opt_xtra_args >> $bls_tmp_file 2> /dev/null
fi

# Write SGE directives according to command line options
# handle queue overriding
[ -z "$bls_opt_queue" ] || grep -q "^#\$ -q" $bls_tmp_file || echo "#\$ -q $bls_opt_queue" >> $bls_tmp_file
[ -z "$bls_opt_mpinodes" ]             || echo "#\$ -pe * $bls_opt_mpinodes" >> $bls_tmp_file

# Input and output sandbox setup.
bls_fl_subst_and_accumulate inputsand "@@F_REMOTE@`hostname -f`:@@F_LOCAL" "@@@"
[ -z "$bls_fl_subst_and_accumulate_result" ] || echo "#\$ -v SGE_stagein=$bls_fl_subst_and_accumulate_result" >> $bls_tmp_file
bls_fl_subst_and_accumulate outputsand "@@F_REMOTE@`hostname -f`:@@F_LOCAL" "@@@"
[ -z "$bls_fl_subst_and_accumulate_result" ] || echo "#\$ -v SGE_stageout=$bls_fl_subst_and_accumulate_result" >> $bls_tmp_file
echo "#$ -m n"  >> $bls_tmp_file

bls_add_job_wrapper

###############################################################
# Submit the script
###############################################################
#Your job 3236842 ("run") has been submitted
jobID=`qsub $bls_tmp_file 2> /dev/null | perl -ne 'print $1 if /^Your job (\d+) /;'` # actual submission
retcode=$?
if [ "$retcode" != "0" -o -z "$jobID" ] ; then
	rm -f $bls_tmp_file
	exit 1
fi
# 11/11/09 Mario David fix (remove CELL)
#jobID=$jobID.${SGE_CELL:-default}

# Compose the blahp jobID ("sge/" + datenow + sge jobid)
# 11/11/09 Mario David fix 
blahp_jobID=sge/`date +%Y%m%d%H%M%S`/$jobID

if [ "x$job_registry" != "x" ]; then
  now=`date +%s`
  let now=$now-1
  `dirname $0`/blah_job_registry_add "$blahp_jobID" "$jobID" 1 $now "$bls_opt_creamjobid" "$bls_proxy_local_file" "$bls_opt_proxyrenew_numeric" "$bls_opt_proxy_subject"
fi

echo "BLAHP_JOBID_PREFIX$blahp_jobID"
bls_wrap_up_submit

exit $retcode
