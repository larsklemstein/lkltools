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
readonly MY_VERSION=1.3.2

readonly CDP_CACHE=$HOME/.local/share/cdp/cache

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
  /bin/cat <<EOF
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

  update_cache:
        Update the cache file with the current git folders.

Options
  -n         : do not ignore git folders without remote
  -d <depth> : set the max depth of the search for git folders (default: 10)
  -c <sec>   : set the cache age in seconds (default: 0, means no cache)
  -e <file>  : source the environment variables from the given file

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

dmsg() {
  [ $DEBUG = y ] && echo "[$PROG DEBUG] $*" >&2 || true
}

exitmsg() {
  local msg="$1"
  declare -i rc=${2:-0}

  echo "[$PROG] $msg" >&2
  exit $rc
}

abort() {
  exitmsg "$* (=>Abort)" 1
}

shell_init() {
  local cdp_fqf
  cdp_fqf=$(realpath $0 | sed "s%$HOME%\$HOME%")

  local flags=
  [ "$ignore_no_remote" = n ] && flags+=' -n'

  /bin/cat <<EOF

unalias cdp 2>/dev/null

cdp() {
    local choosen="\$($cdp_fqf ${flags} -c900 call)"
    [ -z \$choosen ] && return 0

    if [ ! -d "\$choosen" ]
    then
        echo "Dir \$choosen does not exist!?" >&2
        return 1
    fi

    cd \$choosen
}

EOF

  msg "You can call <$PROG update_cache> by cron to keep the cache fresh."
}

choose_folder() {
  local ignore_no_remote="$1"
  local fd_depth="$2"

  if cache_is_outdated_or_empty $cache_for; then
    dmsg 'outdated cache, reloading...'
    update_cache
  else
    dmsg 'cache is up to date, using it...'
  fi

  local tmpf
  tmpf=$(mktemp)

  for dir in $(<"$CDP_CACHE")
  do
    test -d "$dir" && echo "$dir"
  done >"$tmpf"

  dmsg "Using cache file $CDP_CACHE (for existing dirs), call fzf..."
  choosen=$(fzf <"$tmpf")

  /bin/rm -f "$tmpf"

  dmsg "...back; choosen: $choosen"

  eval echo "$choosen"
}

update_cache() {
  dmsg "Updating cache file ${CDP_CACHE}"
  local tmpf
  tmpf=$(mktemp)

  get_own_repos "$ignore_no_remote" "$fd_depth" >"$tmpf"

  /bin/mv "$tmpf" "$CDP_CACHE"
  dmsg "Cache updated"

  if [ ! -s "$CDP_CACHE" ]; then
    dmsg "WARNING: cache is empty"
  fi
}

cache_is_outdated_or_empty() {
  local cache_for="$1"

  test ! -s "$CDP_CACHE" && return 0

  declare -i cache_age
  cache_age=$(get_file_age_in_sec "$CDP_CACHE")
  if [ $cache_age -lt $((cache_for * 60)) ]; then
    dmsg "Cache is still fresh ($cache_age sec old), not reloading"
    return 1
  fi

  local base
  local found

  for base in $(tr '+' '\n' <<<"$CDP_BASE_FOLDERS"); do
    found=$(find "$base" -type d -name '.git' -newer "$CDP_CACHE" 2>/dev/null)
    test -n "$found" && return 0
  done

  # OK, you won...
  return 1
}

get_own_repos() {
  local ignore_no_remote="$1"
  local fd_depth="$2"

  local root_folder
  local tmpd
  tmpd=$(mktemp -d)

  local tmp_fd=$tmpd/fd
  local tmp_own=$tmpd/own

  touch "$tmp_fd" "$tmp_own"

  for root_folder in $(tr '+' '\n' <<<"$CDP_BASE_FOLDERS"); do
    dmsg "Scan root folder ${root_folder}..."
    fd -d"${fd_depth}" -H '^\.git$' -t directory "$root_folder" |
      sed -e "s%$HOME/%~/%g" -e 's%/\.git/$%%' >>"$tmp_fd"
  done

  if [ $DEBUG = y ]; then
    dmsg "tmd_fd:"
    /bin/cat "$tmp_fd" >&2

    local amount
    amount=$(wc -l "$tmp_fd" | awk '{print($1)}')

    dmsg "->${amount} lines."
  fi

  local folder
  local remote

  for folder in $(<"$tmp_fd"); do
    eval cd "${folder}"
    remote=$(git remote -v | awk '/^origin/ && NR==1 {print($2)}')

    if [ -z "$remote" ] && [ "$ignore_no_remote" = n ] || owned_remote "$remote"; then
      echo "$folder" >>"$tmp_own"
    fi
  done

  if [ $DEBUG = y ]; then
    dmsg "tmd_own:"
    local amount
    amount=$(wc -l "$tmp_own" | awk '{print($1)}')
    dmsg "->own: ${amount} lines."
  fi

  /bin/cat "$tmp_own"
  /bin/rm -rf "$tmpd"
}

owned_remote() {
  local remote="${1:-}"
  local git_url

  local remote_normalized
  remote_normalized=$(sed 's/oauth2:[^@][^@]*@//' <<<"$remote")

  for git_url in $(tr '+' '\n' <<<"$CDP_OWN_REPOS"); do
    if [[ "$remote_normalized" == $git_url* ]]; then
      return 0
    fi
  done

  return 1
}

get_file_age_in_sec() {
  local unixtime_file

  if [ "$(uname -o)" = Darwin ]; then
    unixtime_file=$(stat -f %B "$1")
  else
    unixtime_file=$(stat -t "$1" | awk '{print($13)}')
  fi

  echo $(($(/bin/date +%s) - $unixtime_file))
}

#-----------------------------------------------------------------------------
# main
#-----------------------------------------------------------------------------

DEBUG=n

cdp_share_dir="${CDP_CACHE%/*}"
test -d "$cdp_share_dir" || mkdir -p "$cdp_share_dir"
test -f "$CDP_CACHE" || touch "$CDP_CACHE"

opt_str=hvnDd:c:e:

ignore_no_remote=y
declare -i cache_for=0
fd_depth=10
env_file=

while getopts $opt_str arg; do
  case $arg in
  h) print_long_usage_and_exit ;;
  v) show_version_and_exit ;;
  c) cache_for="$OPTARG" ;;
  e) env_file="$OPTARG" ;;
  D) DEBUG=y ;;
  d) fd_depth="$OPTARG" ;;
  n) ignore_no_remote="n" ;;
  *) abort "unknown param \"$OPTARG\"" ;;
  esac

done

shift $((OPTIND - 1))

if [ $# -ne 1 ]; then
  msg "Missing command! (please see more comprehensive usage with -h)"
  print_short_usage_and_exit
fi

if [ -n "$env_file" ]; then
  if [ ! -f "$env_file" ]; then
    abort "File $env_file does not exist"
  fi

  msg "Sourcing environment file $env_file"
  source "$env_file"
fi

set +u
for env_var in CDP_BASE_FOLDERS CDP_OWN_REPOS; do
  eval env_content=\$$env_var
  if [ -z "$env_content" ]; then
    abort "env var \$$env_var not set"
  fi
done
set -u

readonly command="$1"

case $command in
init)
  shell_init
  ;;
call)
  choose_folder $ignore_no_remote "$fd_depth" "$cache_for"
  ;;
update_cache)
  update_cache
  ;;
*)
  exitmsg "Unknown command \"$command\" specified"
  ;;
esac
