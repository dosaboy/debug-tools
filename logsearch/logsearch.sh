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
verbose=0  # int so that we can eventually have multiple levels like -v -vv -vvv

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
USAGE: $cmd_name OPTIONS PATH

OPTIONS:
    -d|--logdir <name>
        Log directory we want to search. Default is to search everything
        under PATH/var/log but this allows for PATH/var/log/<logdir> where
        name can itself be a path.
    -e|--resultfilter <str>
        This is a bit like grep -v i.e. it will filter any matches from the
        results.
    -f|--lognamefilter <str>
        Filter to only include matching filenames in set of files we will
        search. By default all files found under PATH/var/log/<logdir> will
        be searched.
    -h|--help
        Print this message.
    -k|--searchkey <str>
        Search string/data.
    -l|--max-depth <num>"
        Max search depth.
    -o|--grep-opts <opts>
        Pass these to grep.
    -r|--no-ctrl-chars
        Don't print control characters.
    -v|--verbose
        Add extra info to the output.
    -x|--report-no-match
        Report files that didn't match.

EXAMPLES
    $cmd_name -d apache -k error /path/to/sosreport

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
        -v)
            verbose=1
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

((verbose)) && echo -e "Searching path '${reports[@]}'"

for sos in ${reports[@]}; do
    results=false
    if [ "$sos" = '/' ]; then
        sos=''
    fi


    logpath=$sos/var/log
    [ -n "$logdir" ] && logpath=$logpath/$logdir

    [ -d "$logpath" ] || continue

    readarray files<<<`ls -rt $logpath| egrep "${lognamefilter}"| tail -n $maxdepth`

    ((verbose)) && echo -e "\n## Host=`cat $sos/hostname`\n"
    for file in ${files[@]}; do
        file=$logpath/$file
 
        if [ -n "$resultfilter" ]; then
            zegrep -i "${searchkey}" $grepopts $file| egrep -iv "$resultfilter" > $ftmp
        else
            zegrep -i "${searchkey}" $grepopts $file > $ftmp
        fi

        if [ -s "$ftmp" ] || $include_mismatches; then
            results=true
            echo -ne "Matches found in $file:"
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
