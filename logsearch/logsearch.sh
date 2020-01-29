#!/bin/bash
cmd_name=logsearch
sospath=.
searchkey=
logdir=
lognamefilter=
resultfilter=
include_mismatches=false
no_ctrl=false
grepopts=
maxdepth=1000

# Text Format
CSI='\033['
RES="${CSI}0m"
BLD="${CSI}1m"
F_RED="${CSI}31m"
F_GRN="${CSI}32m"
F_YLW="${CSI}33m"
F_GRY="${CSI}37m"
B_RED="${CSI}41m"

ftmp=`mktemp`
cleanup () { rm -f $ftmp; exit 0; }
trap cleanup EXIT SIGINT

usage ()
{
(($#>0)) && [ -n "$1" ] && echo "ERROR: $1" 

cat << EOF
USAGE: $cmd_name OPTIONS <path>

OPTIONS:
    -d|--logdir <name>
    -e|--resultfilter <str>
    -f|--lognamefilter <str>
    -h|--help
    -k|--searchkey <str>
    -l|--max-depth <num>"
    -o|--grep-opts <opts>
    -r|--no-ctrl-chars
    -x|--report-no-match

EXAMPLES
    $cmd_name /path/to/sosreport -f syslog -k error

EOF

(($#>1)) && exit $2
}

while (($#)); do
    case $1 in
        -d|--logdir)
        logdir=$2
        shift
        ;;
        -e|--resultfilter)
        resultfilter="$2"
        shift
        ;;
        -f|--lognamefilter)
        lognamefilter="$2"
        shift
        ;;
        -h)
        usage "" 0
        ;;
        -k|--searchkey)
        searchkey="$2"
        shift
        ;;
        -l|--max-depth)
        maxdepth="$2"
        shift
        ;;
        -o|--grep-opts)
        grepopts="$2"
        shift
        ;;
        -r|--no-ctrl-chars)
        no_ctrl=true
        ;;
        -x|--report-no-match)
        # i.e. show all files searched
        include_mismatches=true
        ;;
        *)
        sospath=$1
        while [ "${sospath:(-1)}" = "/" ]; do sospath=${sospath%*/}; done
        ;;
    esac
    shift
done

yellow ()
{
    $no_ctrl && { echo ""; cat $1; echo ""; } && return
    echo -e ${F_YLW}
    cat $1
    echo -e ${RES}
}

green ()
{
    $no_ctrl && { echo -e "$1"; } && return
    echo -e "${F_GRN}$1${RES}"
}

red ()
{
    $no_ctrl && { echo -e "$1"; } && return
    echo -e "${F_RED}$1${RES}"
}

[ -n "$searchkey" ] || usage "search key must be provided" 1

if [ -z "$sospath" ] || ! [ -d "$sospath" ]; then
    usage "ERROR: valid path required" 1
fi

if ! [ -w "$sospath" ] || ! `ls $sospath &>/dev/null`; then
    echo "ERROR: unable to access $sospath (perhaps you need to do 'snap connect ${cmd_name}:removable-media')"
    exit 1
fi

readarray -t reports<<<"`find $sospath -maxdepth 2 -type d -name sosreport-\*`"
if ((${#reports[@]}==0)) || ! [ -d "${reports[0]}" ]; then
    reports=( . )
fi

if ((${#reports[@]}==0)) || ! [ -d "${reports[0]}" ]; then
    reports=('/')
fi

echo "Searching path '${reports[@]}'"

for sos in ${reports[@]}; do
    results=false
    if [ "$sos" = '/' ]; then
        sos=''
    fi


    logpath=$sos/var/log
    [ -n "$logdir" ] && logpath=$logpath/$logdir

    [ -d "$logpath" ] || continue

    readarray files<<<`ls -rt $logpath| egrep "${lognamefilter}"| tail -n $maxdepth`

    echo -e "\n## Host=`cat $sos/hostname`"
    for file in ${files[@]}; do
        file=$logpath/$file
 
        if [ -n "$resultfilter" ]; then
            zegrep -i "${searchkey}" $grepopts $file| egrep -iv "$resultfilter" > $ftmp
        else
            zegrep -i "${searchkey}" $grepopts $file > $ftmp
        fi

        if [ -s "$ftmp" ] || $include_mismatches; then
            results=true
            echo -ne "\nMatches found in $file:"
        fi

        if [ -s "$ftmp" ]; then
            yellow $ftmp
        fi
    done

    if ! $results; then
        echo "no matches found"
    fi
done

echo "Done."
exit
