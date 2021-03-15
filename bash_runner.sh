#!/bin/bash

################################# DESCRIPTION #################################
##
## Customized framework to handle a worklow/installation written in Bash script
## Source this file to use the exposed functions.
##
## Author   : Jojo Jose
##
################################# CHANGE LOGS #################################
##
## Version 1.0 - 28-09-2019
##  * First Draft
##
#################################### USAGE ####################################
##
## The framework exposes three function calls:
##  1. start_proc <procedure_name>
##       This is called before every new procedure is initiated. This sets a
##       global flag CAN_PROCEED which holds value
##          - "yes" if it can proceed
##          - "no" if it should not proceed
##      
##      This also accepts input through two environment variables
##          - RESUME_FLAG     : set this to a procedure name if you want to 
##                              resume execution only from this procedure
##          - SINGLE_PROCNAME : set this to a procedure name if you want to
##                              execute only a specific procedure
##
##  2. run <subcmd description> <command>
##      This also accepts input through two environment variables
##          - EXIT_ON_ERROR   : Exit if subcmd fails.
##                              Default - Prompt for user confirmation
##          - INLINE_OUTPUT   : Print output inline
##                              Default - print subcmd output to logfile      
##       
##  3. end_proc
##       To be called after every proecdure ends. This will print a summary
##       of the success/failure of the procedure
##
##  -- SAMPLE --
##     start_proc "set-repo"
##     if [ "$CAN_PROCEED" == "yes" ]
##     then
##         umount /media           # Ignore even if there is error
##         run "Mount DVD"         mount /dev/cdrom /media/ -o loop
##     	   run "Copy repo file"    cp manifests/local.repo /etc/yum.repos.d/
##         run "List repos"        yum repolist
##     	end_proc
##     fi
##     


# Local variables
PROCEDURE_NUMBER=0
PROCEDURE_NAME=""
PROCEDURE_ERRORS=0
CAN_PROCEED=""

# Exposed variables
RESUME_FLAG=${RESUME_FLAG:=""}
SINGLE_PROCNAME=${SINGLE_PROCNAME:=""}
INLINE_OUTPUT=${INLINE_OUTPUT:=""}
EXIT_ON_ERROR=${EXIT_ON_ERROR:=""}
LOGFILE=${LOGFILE:="installation.log"}

# Initialize the logfile
echo "" > $LOGFILE


## This is used to run every subcommand and handle its error
run() {
    cmd_title=$1
    shift

    if [ -z "$INLINE_OUTPUT" ]
    then
        # Print the command with simple prompt into logfile
        echo "[`whoami`@`hostname` `basename $PWD`]# $@" >> $LOGFILE

        # Print a placeholder for current command
        printf "[ ]    $cmd_title\r"

        # Execute the remaining arguments as if they are bash cmds
        $@  >> $LOGFILE 2>&1
    else
        $@
    fi

    status=$?

    if [ "$status" -eq 0 ]
    then
        # Exited with no error. Print "check" mark
        printf "[\u2714]    $cmd_title\n"
        return
    fi

    # Exited with error. Print "cross" mark
    printf "[\u274c]    $cmd_title\n"

    if [ -z "$EXIT_ON_ERROR" ]
    then
        while :
        do
            printf "Command failed. Ignore and continue [yes/no]: "
            read user_input
            if [ "$user_input" == "yes" ]
            then
                return
            elif [ "$user_input" == "no" ]
            then
                break
            else
                printf "Unknown input. Try again\n"
            fi
        done
    fi
    PROCEDURE_ERRORS=$((PROCEDURE_ERRORS + status))
    end_proc
}

## Pre-requisite call before each individual procedure. This will check
## if the passed procedure [name] can be executed or not. The response
## is stored in the global var $CAN_PROCEED=yes|no
start_proc() {
	PROCEDURE_NAME=$1
	PROCEDURE_NUMBER=$(($PROCEDURE_NUMBER+1))
    PROCEDURE_ERRORS=0

	# If SINGLE_PROCNAME is set, execute only that, else continue to execute all
	if [ -n "$SINGLE_PROCNAME" ]
	then
		if [ "$SINGLE_PROCNAME" != "$PROCEDURE_NAME" ]
		then
			CAN_PROCEED="no"
			return
		fi
	fi

	# If RESUME_FLAG is set, skip all procedures until that
	if [ -n "$RESUME_FLAG" ]
	then
		if [ "$RESUME_FLAG" != "$PROCEDURE_NAME" ]
		then
			CAN_PROCEED="no"
			return
        else
            # Can resume from this procedure. Hence unset RESUME_FLAG
			CAN_PROCEED="yes"
            unset RESUME_FLAG
		fi
	fi

	CAN_PROCEED="yes"

	echo "--------------------"
	echo `date` - Starting procedure \#${PROCEDURE_NUMBER} - $PROCEDURE_NAME
}


## The closing call after each procedure
end_proc() {
    #  If the procedure was not executed due the global flag $CAN_PROCEED,
    #   then safely return without any error checks
	if [ "$CAN_PROCEED" == "no" ]
	then
		return
	fi

	if [ "$PROCEDURE_ERRORS" -eq 0 ]
	then
		echo `date` - Procedure ${PROCEDURE_NAME} - SUCCESS
	else
		echo `date` - Procedure ${PROCEDURE_NAME} - FAIL
		exit $PROCEDURE_ERRORS
	fi
	echo "--------------------"

	# If the script was run with single_procedure option,
    # and the current procedure name matches, then exit safely
    if [ "$SINGLE_PROCNAME" == "$PROCEDURE_NAME" ]
	then
		exit 0
	fi
}

default_help_menu() { 
cat<<EOF
Usage: $0 [-h] [-r <procedure_name>] [-s <procedure_name>] [-x]

Options:
    -h  - Print this help menu and exit
    -r  - Resume from the specified procedure
    -s  - Execute only this procedure and exit
    -x  - Exit if any command fails
    -i  - Show command output inline
EOF
}

default_parse_cli_args() {
    while getopts ":hr:s:xi" opt; do
        case $opt in
            h)
                help_menu
                exit 0
                ;;
            r)
                resume_procname=$OPTARG
                export RESUME_FLAG=$resume_procname
                ;;
            s)
                export SINGLE_PROCNAME=$OPTARG
                ;;
            x)
                export EXIT_ON_ERROR=true
                ;;
            i)
                export INLINE_OUTPUT=true
                ;;
            \?)
                echo "Invalid option: -$OPTARG" >&2
                exit 1
                ;;
            :)
                echo "Option -$OPTARG requires an argument" >&2
                exit 1
                ;;
        esac
    done
    shift "$((OPTIND - 1))"
}


get_value_for_variable() {
    varname=$1
    force_input=$2
    null_acceptable=$3

    # default values
    force_input=${force_input:=false}
    null_acceptable=${null_acceptable:=false}

    while true; do
        case $force_input in
            true)
                if [ -n "${!varname}" ]
                then
                    printf "Enter $varname [${!varname}]: "
                    read var_value
                else
                    printf "Enter $varname: "
                    read var_value
                fi
                declare $varname=$var_value
                ;;
            false)
                if [ -n "${!varname}" ]
                then
                    printf "* Using value from ENV for $varname - ${!varname}\n"
                else
                    printf "Enter $varname: "
                    read var_value
                    declare $varname=$var_value
                fi
                ;;
            *)
                echo "Exception: bad argument - $force_input"
                exit 1
                ;;
        esac

        if [ -z "${!varname}" ]; then
            if [ $null_acceptable ]; then
                break
            else
                printf "Missing input. Try again...\n"
            fi
        else
            break
        fi
    done
}
