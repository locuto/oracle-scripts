#!/bin/bash
# Fred Denis -- Jan 2016 -- http://unknowndba.blogspot.com -- fred.denis3@gmail.com
#
# Quickly shows a status of all running instances accross a 12c cluster
# The script just need to have a working oraenv
#
# Please have a look at https://unknowndba.blogspot.com/2018/04/rac-statussh-overview-of-your-rac-gi.html for some details and screenshots
# The script latest version can be downloaded here : https://raw.githubusercontent.com/freddenis/oracle-scripts/master/rac-status.sh
#
# The current script version is 2019012
#
# History :
#
# 20190122 - Fred Denis - Multi OS support for AWK (especially for Solaris)
# 20190115 - Fred Denis - Fixed minor alignement issues
#                         Add grep (-g) and ungrep (-v) feature
# 20181110 - Fred Denis - Show short names in the tables instead of the whole hostnames if possible for better visibility
#                       - Col 1 and col 2 now align dynamically depending on the largest element to keep all the tables well aligned
#                       - Dynamic calculation of an offser for the status column size depending on the number of nodes
#                       - This can also be fixed by setting a non 0 value to COL_NODE_OFFSET on top of the script
#                       - Better alignements, centered databases and service were not nice, they are now left aligned which is more clear
# 20181010 - Fred Denis - Added the services
#                         Added default value and options to show and hide some resources (./rac-status.sh -h for more information)
# 20181009 - Fred Denis - Show the usual blue "-" when a target is offline on purpose instead of a red "Offline" which was confusing
# 20180921 - Fred Denis - Added the listeners
# 20180227 - Fred Denis - Make the the size of the DB column dynamic to handle very long database names (Thanks Michael)
#                       - Added a (P) for Primary databases and a (S) for Stanby for color blind people who
#                         may not see the difference between white and red (Thanks Michael)
# 20180225 - Fred Denis - Make the multi status like "Mounted (Closed),Readonly,Open Initiated" clear in the table by showing only the first one
# 20180205 - Fred Denis - There was a version alignement issue with more than 10 different ORACLE_HOMEs
#                       - Better colors for the label "White for PRIMARY, Red for STANBY"
# 20171218 - Fred Denis - Modify the regexp to better accomodate how the version can be in the path (cannot get it from crsctl)
# 20170620 - Fred Denis - Parameters for the size of the columns and some formatting
# 20170619 - Fred Denis - Add a column type (RAC / RacOneNode / Single Instance) and color it depending on the role of the database
#                         (WHITE for a PRIMARY database and RED for a STANDBY database)
# 20170616 - Fred Denis - Shows an ORACLE_HOME reference in the Version column and an ORACLE_HOME list below the table
# 20170606 - Fred Denis - A new 12cR2 GI feature now shows the ORACLE_HOME in the STATE_DETAILS column from "crsctl -v"
#                       - Example :     STATE_DETAILS=Open,HOME=/u01/app/oracle/product/11.2.0.3/dbdev_1 instead of STATE_DETAILS=Open in 12cR1
# 20170518 - Fred Denis - Add  a readable check on the ${DBMACHINE} file - it happens that it exists but is only root readable
# 20170501 - Fred Denis - First release
#

#
# Variables
#
      TMP=/tmp/status$$.tmp                                             # A tempfile
DBMACHINE=/opt/oracle.SupportTools/onecommand/databasemachine.xml       # File where we should find the Exadata model as oracle user
     GREP="."                                                           # What we grep                  -- default is everything
   UNGREP="nothing_to_ungrep_unless_v_option_is_used$$"                 # What we don't grep (grep -v)  -- default is nothing

# Choose the information what you want to see -- the last uncommented value wins
# ./rac-status.sh -h for more information
  SHOW_DB="YES"                 # Databases
 #SHOW_DB="NO"
SHOW_LSNR="YES"                 # Listeners
#SHOW_LSNR="NO"
 SHOW_SVC="YES"                 # Services
 SHOW_SVC="NO"

# Number of spaces between the status and the "|" of the column - this applies before and after the status
# A value of 2 would print 2 spaces before and after the status and like |  Open  |
# A value of 8 would print |        Open         |
# A value of 99 means that this parameter is dynamically calculated depending on the number of nodes
# A non 99 value is applied regardless of the number of nodes
COL_NODE_OFFSET=99

#
# Different OS support
#
OS=`uname`
case ${OS} in
        SunOS)
                       AWK=`which gawk`
                        if [ ! -f ${AWK} ]
                        then
                                printf "\t%s\n" "Cannot find ${AWK}, cannot continue".
                                exit 678
                        fi                                      ;;
        Linux)
                       AWK=`which awk`                          ;;
        HP-UX)
                       AWK=`which awk`                          ;;
        AIX)
                       AWK=`which awk`                          ;;
        *)          echo "Unsupported OS, cannot continue."
                    exit 666                                    ;;
esac

#
# An usage function
#
usage()
{
printf "\n\033[1;37m%-8s\033[m\n" "NAME"                ;
cat << END
        `basename $0` - A nice overview of databases, listeners and services running across a GI 12c
END

printf "\n\033[1;37m%-8s\033[m\n" "SYNOPSIS"            ;
cat << END
        $0 [-a] [-n] [-d] [-l] [-s] [-h]
END

printf "\n\033[1;37m%-8s\033[m\n" "DESCRIPTION"         ;
cat << END
        `basename $0` needs to be executed with a user allowed to query GI using crsctl; oraenv also has to be working
        `basename $0` will show what is running or not running accross all the nodes of a GI 12c :
                - The databases instances (and the ORACLE_HOME they are running against)
                - The type of database : Primary, Standby, RAC One node, Single
                - The listeners (SCAN Listener and regular listeners)
                - The services
        With no option, `basename $0` will show what is defined by the variables :
                - SHOW_DB       # To show the databases instances
                - SHOW_LSNR     # To show the listeners
                - SHOW_SVC      # To show the services
                These variables can be modified in the script itself or you can use command line option to revert their value (see below)

END

printf "\n\033[1;37m%-8s\033[m\n" "OPTIONS"             ;
cat << END
        -a        Show everything regardless of the default behavior defined with SHOW_DB, SHOW_LSNR and SHOW_SVC
        -n        Show nothing  regardless of the default behavior defined with SHOW_DB, SHOW_LSNR and SHOW_SVC
        -a and -n are handy to erase the defaults values:
                        $ ./rac-status.sh -n -d                         # Show the databases output only
                        $ ./rac-status.sh -a -s                         # Show everything but the services (then the listeners and the databases)

        -d        Revert the behavior defined by SHOW_DB  ; if SHOW_DB   is set to YES to show the databases by default, then the -d option will hide the databases
        -l        Revert the behavior defined by SHOW_LSNR; if SHOW_LSNR is set to YES to show the listeners by default, then the -l option will hide the listeners
        -s        Revert the behavior defined by SHOW_SVC ; if SHOW_SVC  is set to YES to show the services  by default, then the -s option will hide the services

        -g        Act as a grep command to grep a pattern from the output (key sensitive)
        -v        Act as "grep -v" to ungrep from the output
        -g and -v examples :
                        $ ./rac-status.sh -g Open                       # Show only the lines with "Open" on it
                        $ ./rac-status.sh -g Open                       # Show only the lines with "Open" on it
                        $ ./rac-status.sh -g "Open|Online"              # Show only the lines with "Open" or "Online" on it
                        $ ./rac-status.sh -g "Open|Online" -v 12        # Show only the lines with "Open" or "Online" on it but no those containing 12


        -h        Shows this help

        Note : the options are cumulative and can be combined with a "the last one wins" behavior :
                $ $0 -a -l              # Show everything but the listeners (-a will force show everything then -l will hide the listeners)
                $ $0 -n -d              # Show only the databases           (-n will force hide everything then -d with show the databases)

                Experiment and enjoy  !

END
exit 123
}

# Options
while getopts "andslhg:v:" OPT; do
        case ${OPT} in
        a)         SHOW_DB="YES"        ; SHOW_LSNR="YES"       ; SHOW_SVC="YES"                ;;
        n)         SHOW_DB="NO"         ; SHOW_LSNR="NO"        ; SHOW_SVC="NO"                 ;;
        d)         if [ "$SHOW_DB"   = "YES" ]; then   SHOW_DB="NO"; else   SHOW_DB="YES"; fi   ;;
        s)         if [ "$SHOW_SVC"  = "YES" ]; then  SHOW_SVC="NO"; else  SHOW_SVC="YES"; fi   ;;
        l)         if [ "$SHOW_LSNR" = "YES" ]; then SHOW_LSNR="NO"; else SHOW_LSNR="YES"; fi   ;;
        g)           GREP=${OPTARG}                                                             ;;
        v)         UNGREP=${OPTARG}                                                             ;;
        h)         usage                                                                        ;;
        \?)        echo "Invalid option: -$OPTARG" >&2; usage                                   ;;
        esac
done
#
# Set the ASM env to be able to use crsctl commands
#
ORACLE_SID=`ps -ef | grep pmon | grep asm | ${AWK} '{print $NF}' | sed s'/asm_pmon_//' | egrep "^[+]"`

export ORAENV_ASK=NO
. oraenv > /dev/null 2>&1

#
# List of the nodes of the cluster
#
# Try to find if there is "db" in the hostname, if yes we can delete the common "<clustername>" pattern from the hosts for visibility
SHORT_NAMES="NO"
if [[ `olsnodes | head -1 | sed s'/,.*$//g' | tr '[:upper:]' '[:lower:]'` == *"db"* ]]
then
               NODES=`olsnodes | sed s'/^.*db/db/g' | ${AWK} '{if (NR<2){txt=$0} else{txt=txt","$0}} END {print txt}'`
        CLUSTER_NAME=`olsnodes | head -1 | sed s'/db.*$//g'`
        SHORT_NAMES="YES"
else
               NODES=`olsnodes | ${AWK} '{if (NR<2){txt=$0} else{txt=txt","$0}} END {print txt}'`
        CLUSTER_NAME=`olsnodes -c`
fi

printf "\n\t\t%s \033[1;37m%-s\033[m" "Cluster" "$CLUSTER_NAME"

#
# Show the Exadata model if possible (if this cluster is an Exadata)
#
if [ -f ${DBMACHINE} ] && [ -r ${DBMACHINE} ]
then
        MODEL=`grep -i MACHINETYPES ${DBMACHINE} | sed -e s':</*MACHINETYPES>::g' -e s'/^ *//' -e s'/ *$//'`
        printf "%s \033[1;37m%s\033[m\n" " is a " "$MODEL"
else
        printf "\n"
fi
printf "\n"

#
# Define the offset to apply to the status column depending on the number of nodes to make the tables visible for big implementations
#
if [ "$COL_NODE_OFFSET" = "99" ]
then
        NB_NODES=`olsnodes | wc -l`
        if [ "$NB_NODES" -eq "2" ]; then COL_NODE_OFFSET=6      ;       fi      ;
        if [ "$NB_NODES" -eq "4" ]; then COL_NODE_OFFSET=5      ;       fi      ;
        if [ "$NB_NODES" -gt "4" ]; then COL_NODE_OFFSET=3      ;       fi      ;
fi

# Get the info we want
cat /dev/null                                                   >  $TMP
if [ "$SHOW_DB" = "YES" ]
then
        crsctl stat res -p -w "TYPE = ora.database.type"        >> $TMP
        crsctl stat res -v -w "TYPE = ora.database.type"        >> $TMP
fi
if [ "$SHOW_LSNR" = "YES" ]
then
        crsctl stat res -v -w "TYPE = ora.listener.type"        >> $TMP
        crsctl stat res -p -w "TYPE = ora.listener.type"        >> $TMP
        crsctl stat res -v -w "TYPE = ora.scan_listener.type"   >> $TMP
        crsctl stat res -p -w "TYPE = ora.scan_listener.type"   >> $TMP
fi
if [ "$SHOW_SVC" = "YES" ]
then
        crsctl stat res -v -w "TYPE = ora.service.type"         >> $TMP
        #crsctl stat res -p -w "TYPE = ora.service.type"        >> $TMP         # not used, in case we need it one day
fi

if [ "$SHORT_NAMES" = "YES" ]
then
        sed -i "s/$CLUSTER_NAME//g" $TMP
fi

        ${AWK} -v NODES="$NODES" -v col_node_offset="$COL_NODE_OFFSET" 'BEGIN\
        {             FS = "="                          ;
                      split(NODES, nodes, ",")          ;       # Make a table with the nodes of the cluster
                # some colors
             COLOR_BEGIN =       "\033[1;"              ;
               COLOR_END =       "\033[m"               ;
                     RED =       "31m"                  ;
                   GREEN =       "32m"                  ;
                  YELLOW =       "33m"                  ;
                    BLUE =       "34m"                  ;
                    TEAL =       "36m"                  ;
                   WHITE =       "37m"                  ;

                 UNKNOWN = "-"                          ;       # Something to print when the status is unknown

                # Default columns size
                COL_NODE =  0                           ;
         COL_NODE_OFFSET = col_node_offset * 2          ;       # Defined on top the script, have a look for explanations on this
                  COL_DB = 12                           ;
                 COL_VER = 15                           ;
                COL_TYPE = 14                           ;
        }

        #
        # A function to center the outputs with colors
        #
        function center( str, n, color)
        {       right = int((n - length(str)) / 2)                                                              ;
                left  = n - length(str) - right                                                                 ;
                return sprintf(COLOR_BEGIN color "%" left "s%s%" right "s" COLOR_END "|", "", str, "" )         ;
        }

        #
        # A function that just print a "---" white line
        #
        function print_a_line(size)
        {
                if ( ! size)
                {       size = COL_DB+COL_VER+(COL_NODE*n)+COL_TYPE+n+3                                         ;
                }
                printf("%s", COLOR_BEGIN WHITE)                                                                 ;
                for (k=1; k<=size; k++) {printf("%s", "-");}                                                    ;       # n = number of nodes
                printf("%s", COLOR_END"\n")                                                                     ;
        }
        {
               # Fill 2 tables with the OH and the version from "crsctl stat res -p -w "TYPE = ora.database.type""
               if ($1 ~ /^NAME/)
               {
                        sub("^ora.", "", $2)                                                                    ;
                        sub(".db$",  "", $2)                                                                    ;
                        if ($2 ~ ".lsnr"){sub(".lsnr$", "", $2); tab_lsnr[$2] = $2;}                            ;       # Listeners
                        if ($2 ~ ".svc") {sub(".svc$", "", $2) ; tab_svc[$2] = $2;
                                          split($2, temp, ".");
                                          if (length(temp[2]) > COL_VER-1)                                               # To adapt the column size
                                          {     COL_VER = length(temp[2]) +1                                    ;
                                          }
                                         }                                                                              # Services
                        DB=$2                                                                                   ;
                        split($2, temp, ".")                                                                    ;
                        if (length(temp[1]) > COL_DB-1)                                                                   # To adapt the 1st column size
                        {     COL_DB = length(temp[1]) +1                                                       ;
                        }

                        getline; getline                                                                        ;
                        if ($1 == "ACL")                        # crsctl stat res -p output
                        {
                                if ((DB in version == 0) && (DB in tab_lsnr == 0) && (DB in tab_svc == 0))
                                {
                                        while (getline)
                                        {
                                                if ($1 == "ORACLE_HOME")
                                                {                    OH = $2                                    ;
                                                        match($2, /1[0-9]\.[0-9]\.?[0-9]?\.?[0-9]?/)            ;       # Grab the version from the OH path)
                                                                VERSION = substr($2,RSTART,RLENGTH)             ;
                                                }
                                                if ($1 == "DATABASE_TYPE")                                              # RAC / RACOneNode / Single Instance are expected here
                                                {
                                                             dbtype[DB] = $2                                    ;
                                                }
                                                if ($1 == "ROLE")                                                       # Primary / Standby expected here
                                                {              role[DB] = $2                                    ;
                                                }
                                                if ($0 ~ /^$/)
                                                {           version[DB] = VERSION                               ;
                                                                 oh[DB] = OH                                    ;

                                                        if (!(OH in oh_list))
                                                        {
                                                                oh_ref++                                        ;
                                                            oh_list[OH] = oh_ref                                ;
                                                        }
                                                        break                                                   ;
                                                }
                                        }
                                }
                                if (DB in tab_lsnr == 1)
                                {
                                        while(getline)
                                        {
                                                if ($1 == "ENDPOINTS")
                                                {
                                                        port[DB] = $2                                           ;
                                                        break                                                   ;
                                                }
                                        }
                                }
                        }
                        if ($1 == "LAST_SERVER")        # crsctl stat res -v output
                        {           NB = 0      ;       # Number of instance as CARDINALITY_ID is sometimes irrelevant
                                SERVER = $2     ;
                                while (getline)
                                {
                                        if ($1 == "LAST_SERVER")        {       SERVER = $2                             ;}
                                        if ($1 == "STATE")              {       gsub(" on .*$", "", $2)                 ;
                                                                                if ($2 ~ /ONLINE/ ) {STATE="Online"     ;
                                                                                                     if (length(STATE) > COL_NODE) { COL_NODE = length(STATE) + COL_NODE_OFFSET;}
                                                                                                    }
                                                                                if ($2 ~ /OFFLINE/) {STATE=""           ;}
                                                                        }
                                        if ($1 == "TARGET")             {       TARGET = $2                             ;}
                                        if ($1 == "STATE_DETAILS")      {       NB++                                    ;       # Number of instances we came through
                                                                                sub("STATE_DETAILS=", "", $0)           ;
                                                                                sub(",HOME=.*$", "", $0)                ;       # Manage the 12cR2 new feature, check 20170606 for more details
                                                                                sub("),.*$", ")", $0)                   ;       # To make clear multi status like "Mounted (Closed),Readonly,Open Initiated"
                                                                                if ($0 == "")
                                                                                {       status[DB,SERVER] = STATE       ;}
                                                                                else {
                                                                                        if ($0 == "Instance Shutdown")  {  status[DB,SERVER] = "Shutdown"       ;       } else
                                                                                        if ($0 ~  "Readonly")           {  status[DB,SERVER] = "Readonly"       ;       } else
                                                                                        if ($0 ~  /Mount/)              {  status[DB,SERVER] = "Mounted"        ;       } else
                                                                                                                        {  status[DB,SERVER] = $0               ;       }
                                                                                        if (length(status[DB,SERVER]) > COL_NODE)
                                                                                        {       COL_NODE = length(status[DB,SERVER]) + COL_NODE_OFFSET  ;
                                                                                        }
                                                                                }
                                                                        }
                                        if ($1 == "INSTANCE_COUNT")     {       if (NB == $2) { break                   ;}}
                                }
                        }
                }       # End of if ($1 ~ /^NAME/)
            }
            END {       if (length(tab_lsnr) > 0)                # We print only if we have something to show
                        {
                                # A header for the listeners
                                printf("%s", center("Listener" ,  COL_DB, WHITE))                               ;
                                printf("%s", center("Port"     , COL_VER, WHITE))                               ;
                                n=asort(nodes)                                                                  ;       # sort array nodes
                                for (i = 1; i <= n; i++) {
                                        printf("%s", center(nodes[i], COL_NODE, WHITE))                         ;
                                }
                                printf("%s", center("Type"    , COL_TYPE, WHITE))                               ;
                                printf("\n")                                                                    ;

                                # a "---" line under the header
                                print_a_line()                                                                  ;

                                # print the listeners
                                x=asorti(tab_lsnr, lsnr_sorted)                                                 ;
                                for (j = 1; j <= x; j++)
                                {
                                        printf(COLOR_BEGIN WHITE " %-"COL_DB-1"s|" COLOR_END, lsnr_sorted[j], WHITE);     # Listener name
                                        # It may happen that listeners listen on many ports then it wont fit this column
                                        # We then print it outside of the table after the last column
                                        if (length(port[lsnr_sorted[j]]) > COL_VER)
                                        {
                                                printf(COLOR_BEGIN WHITE " %-"COL_VER-1"s|" COLOR_END, "See -->", WHITE);       # "See -->"
                                                print_port_later = 1                                            ;
                                        } else {
                                                printf(COLOR_BEGIN WHITE " %-"COL_VER-1"s|" COLOR_END, port[lsnr_sorted[j]], WHITE);      # Port
                                        }

                                        for (i = 1; i <= n; i++)
                                        {
                                                dbstatus = status[lsnr_sorted[j],nodes[i]]                      ;

                                                if (dbstatus == "")             {printf("%s", center(UNKNOWN , COL_NODE, BLUE         ))      ;}      else
                                                if (dbstatus == "Online")       {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}
                                                else                            {printf("%s", center(dbstatus, COL_NODE, RED          ))      ;}
                                        }
                                        if (toupper(lsnr_sorted[j]) ~ /SCAN/)
                                        {       LSNR_TYPE = "SCAN"                                              ;
                                        } else {
                                                LSNR_TYPE = "Listener"                                          ;
                                        }
                                        printf("%s", center(LSNR_TYPE, COL_TYPE, WHITE))                        ;
                                        if (print_port_later)
                                        {       print_port_later = 0                                            ;
                                                printf(COLOR_BEGIN WHITE " %-"COL_VER-1"s" COLOR_END, port[lsnr_sorted[j]], WHITE);      # Port
                                        }
                                        printf("\n")                                                            ;
                                }
                                # a "---" line under the header
                                print_a_line()                                                                  ;
                                printf("\n")                                                                    ;
                        }

                        if (length(tab_svc) > 0)                # We print only if we have something to show
                        {
                                # A header for the services
                                printf("%s", center("DB"      ,  COL_DB, WHITE))                                ;
                                printf("%s", center("Service" ,  COL_VER, WHITE))                               ;
                                n=asort(nodes)                                                                  ;       # sort array nodes
                                for (i = 1; i <= n; i++) {
                                        printf("%s", center(nodes[i], COL_NODE, WHITE))                         ;
                                }
                                printf("\n")

                                # a "---" line under the header
                                print_a_line(COL_DB+COL_NODE*n+COL_VER+n+2)                                    ;


                                # Print the Services
                                x=asorti(tab_svc, svc_sorted)                                                   ;
                                for (j = 1; j <= x; j++)
                                {
                                        split(svc_sorted[j], to_print, ".")                                     ;       # The service we have is <db_name>.<service_name>
                                        if (previous_db != to_print[1])                                                 # Do not duplicate the DB names on the output
                                        {
                                                printf(COLOR_BEGIN WHITE " %-"COL_DB-1"s|" COLOR_END, to_print[1], WHITE);     # Database
                                                previous_db = to_print[1]                                       ;
                                        }else {
                                                printf("%s", center("",  COL_DB, WHITE))                        ;
                                        }
                                        printf(COLOR_BEGIN WHITE " %-"COL_VER-1"s|" COLOR_END, to_print[2], WHITE);     # Service



                                        for (i = 1; i <= n; i++)
                                        {
                                                dbstatus = status[svc_sorted[j],nodes[i]]                       ;

                                                if (dbstatus == "")             {printf("%s", center(UNKNOWN , COL_NODE, BLUE         ))      ;}      else
                                                if (dbstatus == "Online")       {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}
                                                else                            {printf("%s", center(dbstatus, COL_NODE, RED          ))      ;}
                                        }
                                        printf("\n")                                                             ;
                                }
                                # a "---" line under the header
                                print_a_line(COL_DB+COL_NODE*n+COL_VER+n+2)                                      ;
                                printf("\n")                                                                     ;
                        }

                        if (length(version) > 0)                # We print only if we have something to show
                        {
                                # A header for the databases
                                printf("%s", center("DB"        , COL_DB, WHITE))                                ;
                                printf("%s", center("Version"   , COL_VER, WHITE))                               ;
                                n=asort(nodes)                                                                   ;       # sort array nodes
                                for (i = 1; i <= n; i++) {
                                        printf("%s", center(nodes[i], COL_NODE, WHITE))                          ;
                                }
                                printf("%s", center("DB Type"    , COL_TYPE, WHITE))                             ;
                                printf("\n")                                                                     ;

                                # a "---" line under the header
                                print_a_line()                                                                   ;

                                # Print the databases
                                m=asorti(version, version_sorted)                                                ;
                                for (j = 1; j <= m; j++)
                                {
                                        printf(COLOR_BEGIN WHITE " %-"COL_DB-1"s|" COLOR_END, version_sorted[j], WHITE);     # Database
                                        printf(COLOR_BEGIN WHITE " %-"COL_VER-7"s" COLOR_END, version[version_sorted[j]], COL_VER, WHITE)         ;       # Version
                                        printf(COLOR_BEGIN WHITE "%6s" COLOR_END"|"," ("oh_list[oh[version_sorted[j]]] ") ")            ;       # OH id

                                        for (i = 1; i <= n; i++) {
                                                dbstatus = status[version_sorted[j],nodes[i]]                    ;

                                                #
                                                # Print the status here, all that are not listed in that if ladder will appear in RED
                                                #
                                                if (dbstatus == "")                     {printf("%s", center(UNKNOWN , COL_NODE, BLUE         ))      ;}      else
                                                if (dbstatus == "Open")                 {printf("%s", center(dbstatus, COL_NODE, GREEN        ))      ;}      else
                                                if (dbstatus ~  /Readonly/)             {printf("%s", center(dbstatus, COL_NODE, WHITE        ))      ;}      else
                                                if (dbstatus ~  /Shut/)                 {printf("%s", center(dbstatus, COL_NODE, YELLOW       ))      ;}      else
                                                                                        {printf("%s", center(dbstatus, COL_NODE, RED          ))      ;}
                                        }
                                        #
                                        # Color the DB Type column depending on the ROLE of the database (20170619)
                                        #
                                        if (role[version_sorted[j]] == "PRIMARY") { ROLE_COLOR=WHITE ; ROLE_SHORT=" (P)"; } else { ROLE_COLOR=RED ; ROLE_SHORT=" (S)" }
                                        printf("%s", center(dbtype[version_sorted[j]] ROLE_SHORT, COL_TYPE, ROLE_COLOR))           ;

                                        printf("\n")                                                              ;
                                }

                                # a "---" line as a footer
                                print_a_line()                                                                    ;

                                #
                                # Print the OH list and a legend for the DB Type colors underneath the table
                                #
                                printf ("\n\t%s", "ORACLE_HOME references listed in the Version column :")        ;

                                # Print the output in many lines for code visibility
                                #printf ("\t\t%s\t", "DB Type column =>")                                         ;       # Most likely useless
                                printf ("\t\t\t\t\t")                                                             ;
                                printf("%s" COLOR_BEGIN WHITE "%-6s" COLOR_END    , "Primary : ", "White")        ;
                                printf("%s" COLOR_BEGIN WHITE "%s"   COLOR_END"\n", "and "      , "(P)"  )        ;
                                printf ("\t\t\t\t\t\t\t\t\t\t\t\t")                                               ;
                                printf("%s" COLOR_BEGIN RED "%-6s"   COLOR_END    , "Standby : ", "Red"  )        ;
                                printf("%s" COLOR_BEGIN RED "%s"     COLOR_END"\n", "and "      , "(S)" )         ;


                                for (x in oh_list)
                                {
                                        printf("\t\t%s\n", oh_list[x] " : " x) | "sort"                           ;
                                }
                        }
        }' $TMP | ${AWK} -v GREP="$GREP" -v UNGREP="$UNGREP" ' BEGIN {FS="|"}                                              # AWK used to grep and ungrep
                      {         if ((NF >= 3) && ($(NF-1) !~ /Type/) && ($2 !~ /Service/))
                                {       if (($0 ~ GREP) && ($0 !~ UNGREP))
                                        {
                                                print $0                                                          ;
                                        }
                                } else {
                                        print  $0                                                                 ;
                                }
                        }'

        printf "\n"

if [ -f ${TMP} ]
then
        rm -f ${TMP}
fi

#*********************************************************************************************************
#                               E N D     O F      S O U R C E
#*********************************************************************************************************
