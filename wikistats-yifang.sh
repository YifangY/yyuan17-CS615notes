#/bin/sh
#Part1 is analysis function which depends on arguments(blr...)
#Part2 is the output of the result
#key is define by -d domain and default is 'en'
Part1='{';
Part2=' END {';
key='chicken';

argu=0;
#Read arguments
while getopts "bd:fhlru" arg 
do
    case $arg in
	b)	Part1=$Part1'q3+=$NF;'
		Part2=$Part2'print q3;'
		argu=1
		;;
	d)	key=$OPTARG
		;;
	f)	Part1=$Part1'if($(NF-1)>temp1) {temp1 = $(NF-1);q2=$(NF-2)};'
		Part2=$Part2'print q2;'
		argu=1
		;;
	h)	echo " -b           only print 'total bytes' stats"
		echo " -d <domain>  if not specified, default to 'en'"
		echo "              note: the special domain 'all' is also valid"
		echo " -f           only print 'most frequent' stats"
		echo " -h           print this help and exit"
		echo " -l           only print 'largest object' stats"
		echo " -r           only print 'requests per second' stats"
		echo " -u           only print 'unique objects' stats"
		exit 0
		;;
	l)	Part1=$Part1'if($(NF-1)>0&&$NF/$(NF-1)>temp2) {temp2 = $NF/$(NF-1); q5=$(NF-2) };'
		Part2=$Part2'print q5;'
		argu=1
		;;
	r)	Part1=$Part1'q4+=$(NF-1);'
		Part2=$Part2'printf ("%.2f\n",q4/3600);'
		argu=1
		;;
	u)      Part1=$Part1'q1++;'
		Part2=$Part2'print q1;'
		argu=1
		;;
	?)	exit 1;;
    esac
done

shift $((OPTIND-1))
#handle -d all, if it is all clear the key(no limitation)
if [ $key = "all" ]
then
key=" "
else
key=" /^${key}[\. ]/ "
fi
#if no argu, output all result
if [ $argu = 0 ]
then
zcat $1|awk "$key"' {q1++;if($(NF-1)>temp1) {temp1 = $(NF-1);q2=$(NF-2)};q3+=$NF;q4+=$(NF-1);if($(NF-1)>0&&$NF/$(NF-1)>temp2) {temp2 = $NF/$(NF-1); q5=$(NF-2) }} END {print "Unique objects:",q1,"\nMost frequent object:",q2,"\nTotal bytes transferred:",q3, "\nRequests per second:",q4/3600,"\nLargest object:",q5}';
exit 0;
fi
#build final command
Part1=$key$Part1'}'
Part2=$Part2'}'
awkscript=$Part1$Part2
zcat $1|awk "$awkscript"

