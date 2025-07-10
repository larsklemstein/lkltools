#!/bin/bash -eu

# ****************************************************************************
# DESCRIPTION
# cdp == cd to (git controlled) project
#
# This program is meant to be evaluated in shell init file to create a shell
# function cdp. Should work with bash and zsh at this point.
#
# Attempted to implement some useful default behaviour.
# To alter it, several environment variables cab be set:
#
# ****************************************************************************

# bugs and hints: lrsklemstein@gmail.com

#-----------------------------------------------------------------------------
# constants
#-----------------------------------------------------------------------------

readonly PROG=${0##*/}
readonly MY_VERSION=1.0.0


#-----------------------------------------------------------------------------
# functions
#-----------------------------------------------------------------------------

print_short_usage_and_exit() {
    {
        echo
        echo "$PROG [options] command"
        echo "$PROG -h"
        echo
    } >&2

    exit 2
}

print_long_usage_and_exit() {
/bin/cat << EOF
cdp means "cd to project directory". "project directory" means a 
git controlled folder with or without a remote that belongs to us.

The tool relies on two environment variables CDP_BASE_FOLDERS and 
CDP_OWN_REPOS to determine, which base folders should be considered
and which are the ones "owned" by us (by comparing the git remote with
a list of "owned" remotes like https://github.com/frankzappa etc.). 

Usage
  $PROG [options] command

Commands
  init: Produce shell function cdp (suitbable for zsh and bash)
        to be imported from a file or to be evaluated in a rc file.

  call:
        The actual exeuction of the git selection (should be executed 
        via cdp function created by the init step).

Options
  -n  : do not ignore git folders without remote

Environment vairables
  CDP_BASE_FODLERS: a list of folders separated by + to act as base folders
                    containing one or more git folders of interest.

  CDP_OWN_REPOS:    a list of remote base addresses separated by +

EOF
exit 2
}

show_version_and_exit() {
    echo "This is $PROG version $MY_VERSION"
    exit 0
}

msg() {
    echo "[$PROG] $*" >&2
}

exitmsg() {
    local msg="$1"
    local rc=${2:-0}
    echo "[$PROG] $*" >&2
    exit $rc
}

abort() {
    exitmsg "$* (=>Abort)" 1
}

shell_init() {
local cdp_fqf=$(realpath $0 |sed "s%$HOME%\$HOME%")

/bin/cat <<EOF

unalias cdp 2>/dev/null

cdp() {
    local choosen="\$($cdp_fqf call \$@)"
    [ -z \$choosen ] && return 0

    if [ ! -d "\$choosen" ]
    then
        echo "Dir \$choosen does not exist!?" >&2
        return 1
    fi

    cd \$choosen
}

EOF
}

choose_folder() {
    local ignore_no_remote="$1"

    local root_folder
    local tmpd=$(mktemp -d)

    local tmp_fd=$tmpd/fd
    local tmp_own=$tmpd/own

    touch $tmp_fd $tmp_own

    local cwd_org="$PWD"

    for root_folder in $(tr '+' '\n' <<< $CDP_BASE_FOLDERS)
    do
        fd -H '^\.git$' -t directory $root_folder \
            | sed -e "s%$HOME/%%" -e 's%/\.git/$%%' >> $tmp_fd
    done

    local folder
    local remote

    for folder in $(< $tmp_fd)
    do
        cd "$HOME/${folder}"
        remote=$(git remote -v | awk '/^origin/ && NR==1 {print($2)}')
        if [ -z "$remote" -a "$ignore_no_remote" = n ] || owned_remote $remote
        then
            echo "$folder" >>$tmp_own
        fi
    done

    choosen=$(fzf < $tmp_own)

    /bin/rm -rf $tmpd

    echo "$HOME/$choosen"
}

owned_remote() {
    local remote="${1:-}"
    local git_url

    for git_url in $(tr '+' '\n' <<< "$CDP_OWN_REPOS")
    do
        if [[ "$remote" == $git_url* ]]
        then
            return 0
        fi
    done

    return 1
}


#-----------------------------------------------------------------------------
# main
#-----------------------------------------------------------------------------

set +u
for env_var in CDP_BASE_FOLDERS CDP_OWN_REPOS
do
    eval env_content=\$$env_var
    if [ -z "$env_content" ]
    then
        abort "env var \$$env_var not set"
    fi
done
set -u

opt_str=hvn

ignore_no_remote=y

while getopts $opt_str opt_arg
do
    case $opt_arg in
        h) print_long_usage_and_exit ;;
        v) show_version_and_exit ;;
        n) ignore_no_remote="n" ;;
        *) abort "unknown param \"$opt_arg\""
    esac

    shift $((OPTIND-1))
done

if [ $# -ne 1 ]
then
    msg "Missing command! (please see more comprehensive usage with -h)"
    print_short_usage_and_exit
fi

readonly command="$1"

case $command in
    init) shell_init ;;
    call) choose_folder $ignore_no_remote ;;
    *)
        exitmsg "Unknown command \"$command\" specified"
esac
