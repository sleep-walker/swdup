#!/bin/bash

hash[0]=md5
sumbin[0]="md5sum"
sumlen[0]=32

hash[1]=sha512
sumbin[1]="sha512sum"
sumlen[1]=128

set_hash() {
    local i
    for i in ${!hash[@]}; do
	if [ "${hash[$i]}" == "$1" ]; then
	    hashbin="${sumbin[$i]}"
	    hashlen="${sumlen[$i]}"
	    hashname="${hash[$i]}"
	    return 0
	fi
    done
    return 1
}
	

inform() {
    echo "${green}$*${nocolor}"
}


motion=( '-' '\' '|' '/')
# global variable with last state of process indicator
last_motion=0

# clear the line back to beginning and move pointer to beggining of the line
clear_back="$(tput el1)"$'\r'

# green color for better visibility
green="$(tput setaf 2)"
nocolor="$(tput sgr0)"

# animated indicator of the process
progress() {
    local all="$1"
    local current="$2"

    # change the indicator
    last_motion=$(((last_motion + 1) % 4))
    # clear
    {
	echo -n "${clear_back}$(($current * 100 / $all)) % ($current/$all) ... ${motion[$last_motion]}"
    } > /dev/tty
}

# sanitize input for sed
safe_for_sed(){
    sed -e 's/[]\/$*.^|[]/\\&/g' <<< "$1"
}

####
#
# Step 0 - init
#
#############################################################

used_hash=md5

if [ "$1" = -H ]; then
    used_hash="$2"
    shift 2
fi

if [ "$1" = -u ]; then
    update_existing=1
    shift
fi


if ! set_hash "$used_hash"; then
    echo "Cannot use hash '$used_hash'"
    exit 1
fi

DIR="${1:-$PWD}"


####
#
# Step 1 - calculate sums for all files, find all directories
#
#############################################################

if [ ! -f swdup.dirs ] || [ "$update_existing" ]; then
    inform "Collecting directories"
    find "$DIR" -type d > swdup.dirs
else
    inform "Found already collected directory structure infromation (swdup.dirs)"
fi

if [ ! -f "swdup.$hashname" ] || [ "$update_existing" ]; then
    inform "Calculating sums for files"
    find "$DIR" -type f -exec "$hashbin" {} + > "swdup.$hashname"
else
    inform "Found already generated hashes for file (swdup.$hashname)"
fi

all="$(wc -l < swdup.dirs)"


####
#
# Step 2 - identify duplicates
#
##############################

# sort alphabetically so the files with same hash will be together
# yield only repeating hashes, sort the files according path

if [ ! -f "swdup.$hashname.dups" ] || [ "$update_existing" ]; then
    inform "Looking for file duplicates"
    sort -s < "swdup.$hashname" | uniq -D -w "$hashlen" | sort -k2 > "swdup.$hashname.dups"
else
    inform "Found already generated file duplicate list (swdup.$hashname.dups)"
fi

if [ ! -f "swdup.$hashname.dirs" ] || [ "$update_existing" ]; then
    inform "Generating directory hashes"
    i=0
    while read dir; do
	# sanitize directory name for sed
	safe_dir="$(safe_for_sed "$dir")"

	# show progress
	progress "$all" "$((++i))"

	# for every directory calculate hash:
	#   remove directory path from every file
	#     - i.e. with directory '/some/long/path'
	#       transform file '/some/long/path/to/file'
	#       to 'to/file'
	#   files hashes are not touched
	#   sort the text alphabetically
	#   count hash from the text
	#     - if directories has same files with same hashes in same
	#       order, it will produce identical text with the same
	#       hash)
	
	sed -n "s<^\(.\{$hashlen\}\)  ${safe_dir}<\1  <p" < "swdup.$hashname" | \
	    sort | \
	    $hashbin - | \
	    sed "s<^\(.\{$hashlen\}\)  -<\1  $dir<"
	if [ $? -ne 0 ]; then
	    {
		# there is no reason for failure so I must be doing something wrong
		echo "dir: '$dir'"
		echo "safe_dir: '$safe_dir'"
		echo "sed -n \"s<^\(.\{$hashlen\}\)  ${safe_dir}<\1  <p\" < \"swdup.$hashname\""
		echo "\"s<^\(.\{$hashlen\}\)  -<\1  $dir<\""
	    } >> /dev/tty
	fi
    done < swdup.dirs > "swdup.$hashname.dirs"
    echo -n "$clear_back"
else
    inform "Found already generated list of directory hashes (swdup.$hashname.dirs)"
fi

if [ ! -f "swdup.$hashname.dirs.dups" ] || [ "$update_existing" ]; then
    inform "Looking for directory duplicates"
    sort < "swdup.$hashname.dirs" | uniq -D -w "$hashlen" > "swdup.$hashname.dirs.dups"
else
    inform "Found list of duplicate directories"
fi


# prune whole subtree of duplicates
#  - sort duplicate dirs by the length of the path from the shortest
#  - for each dir remove it's subdirectories if are present

if [ ! -f "swdup.$hashname.dirs.dups.sorted" ] || [ "$update_existing" ]; then
    inform "Sorting duplicate directories by path length"
    # sort by length of the path
    # (it is counting also separator spaces, but order is right)
    awk '{ print length - length($1), $0 }' < "swdup.$hashname.dirs.dups" | \
	sort -n -s | \
	cut -d ' ' -f2- > "swdup.$hashname.dirs.dups.sorted"

    inform "Pruning subtrees of directories with duplicates"
    # read shortest path from duplicates, wipe subtree
    # already processed lines won't change, 
    line=0
    all="$(wc -l < "swdup.$hashname.dirs.dups.sorted")"

    while [ "$((++line))" -le "$all" ]; do
	progress "$all" "$line"
	
	# read some next directory
	dir="$(sed -n "${line}s<^\(.\{$hashlen\}\)  <<p" "swdup.$hashname.dirs.dups.sorted")"

	# prepare it for sed
	safe_dir="$(safe_for_sed "$dir")"
	
	# delete everything under that dir if there is such line
	sed -i "/^\(.\{$hashlen\}\)  ${safe_dir}\/.\+/d" "swdup.$hashname.dirs.dups.sorted"
	
	# update file length
	all="$(wc -l < "swdup.$hashname.dirs.dups.sorted")"
    done
    echo -n "$clear_back"

else
    inform "Found directory duplicate list sorted by path length (swdup.$hashname.dirs.dups.sorted)"
fi

if [ ! -f "swdup.$hashname.dirs.result" ] || [ "$update_existing" ]; then
    inform "Generating result list of directory duplicates"
    # sort by hash again
    sort < "swdup.$hashname.dirs.dups.sorted" > "swdup.$hashname.dirs.result"
else
    inform "Found directory with result of directory duplicates analysis (swdup.$hashname.dirs.result)"
fi

if [ ! -f "swdup.$hashname.files.result" ] || [ "$update_existing" ]; then
    inform "Removing whole duplicate directories from file list"

    # sort file duplicates list first by hash (for output)
    sort "swdup.$hashname.dups" > "swdup.$hashname.files.result"

    # generate sed script which deletes all the lines inside duplicate path
    sed -e "
	# remove hash
	s<^\(.\{$hashlen\}\)  <<"'

	# prepare directory name for sed
	s/[]\/$*.^|[]/\\&/g

	# generate delete commands
	s@^\(.*\)$@/^\\(.\\{'"$hashlen"'\\}\\)  \1\\/.\\+/d@' \
	\
	< "swdup.$hashname.dirs.result" \
	> "swdup.$hashname.dirs.result.sed"

    # apply the deletion
    sed -i -f "swdup.$hashname.dirs.result.sed" "swdup.$hashname.files.result"
else
    inform "Found file duplicates list pruned by directory duplicates result (swdup.$hashname.files.result)"
fi

####
#
# Step 3 - Show duplicates
#
##############################

{
    inform "Duplicate dirs:"

    old_hash=""
    while read line; do
	hash="${line:1:$hashlen}"
	dir="${line:$((hashlen + 2))}/"
	if [ "$old_hash" != "$hash" ]; then
	    # hash is different, another group of duplicates is starting
	    echo "-------------------------------------------------------------------------------"
	    old_hash="$hash"
	fi
	echo "$dir"
    done < "swdup.$hashname.dirs.result"
    
    inform "Duplicate files:"

    while read line; do
	hash="${line:1:$hashlen}"
	file="${line:$((hashlen + 2))}"
	if [ "$old_hash" != "$hash" ]; then
	    # hash is different, another group of duplicates is starting
	    echo "-------------------------------------------------------------------------------"
	    old_hash="$hash"
	fi
	echo "$file"
    done < "swdup.$hashname.files.result"
} | less
