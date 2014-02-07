#!/usr/local/bin/dash

_MON_VERSION="0.0.0";

_MON_ACTION="run";
_MON_DAEMON="no";
_MON_COMMAND="";
_MON_LOG_PREFIX="";
_MON_LOG_FILE="";
_MON_PID_FILE="";
_MON_OWN_PID_FILE="";
_MON_RESTART_DELAY="1";
_MON_RESTART_ATTEMPTS="10";
_MON_RESTART_WINDOW="60";
_MON_ON_RESTART="";
_MON_ON_ERROR="";

# swiped from http://www.etalabs.net/sh_tricks.html
quote () {
  printf %s "$1" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/";
}

###
# extracted from dlist.sh <https://github.com/deoxxa/dlist.sh>
###

dlist_init() {
  local dlist_name=${1}

  eval _DLIST_${dlist_name}_length=0
}

dlist_get() {
  local dlist_name=${1}
  local dlist_offset=${2}

  eval echo \$_DLIST_${dlist_name}_${dlist_offset}
}

dlist_set() {
  local dlist_name=${1}
  local dlist_offset=${2}
  local dlist_value=${3}

  eval _DLIST_${dlist_name}_${dlist_offset}=\${dlist_value}
}

dlist_length() {
  local dlist_name=${1}

  eval echo \$_DLIST_${dlist_name}_length
}

dlist_push() {
  local dlist_name=${1}
  local dlist_value=${2}

  local n=$( dlist_length ${dlist_name} )

  : $(( _DLIST_${dlist_name}_length += 1 ))

  dlist_set ${dlist_name} ${n} ${dlist_value}
}

dlist_shift() {
  local dlist_name=${1}

  local n=$( dlist_length ${dlist_name} )

  for i in $( seq 0 $(( n - 2 )) ); do
    dlist_set ${dlist_name} ${i} $( dlist_get ${dlist_name} $(( i + 1 )) )
  done;

  eval unset _DLIST_${dlist_name}_$(( n - 1 ))

  : $(( _DLIST_${dlist_name}_length -= 1 ))
}

###
# end of dlist implementation
###

dlist_init _MON_RESTARTS

mon_version() {
  echo "${_MON_VERSION}";
}

mon_help() {
  cat <<-EOF

Usage: mon.sh [options] <command>

Options:

  -V, --version                 output program version
  -h, --help                    output help information
  -l, --log <path>              specify logfile [mon.log]
  -s, --sleep <sec>             sleep seconds before re-executing [1]
  -S, --status                  check status of --pidfile
  -p, --pidfile <path>          write pid to <path>
  -m, --mon-pidfile <path>      write mon(1) pid to <path>
  -P, --prefix <str>            add a log prefix
  -d, --daemonize               daemonize the program
  -w, --window <n>              retry attempt tracking window [60]
  -a, --attempts <n>            retry attempts within $WINDOW seconds [10]
  -R, --on-restart <cmd>        execute <cmd> on restarts
  -E, --on-error <cmd>          execute <cmd> on error

EOF
}

mon_run() {
  if [ "${_MON_DAEMON}" = "yes" ]; then
    local _MON_CMDLINE=$( quote "${0}" );

    if [ "${_MON_LOG_FILE}" = "" ]; then
      _MON_LOG_FILE="mon.$$.log";
    fi;

    if [ ! "${_MON_LOG_FILE}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --log $( quote "${_MON_LOG_FILE}" )";
    fi;

    if [ ! "${_MON_LOG_PREFIX}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --prefix $( quote "${_MON_LOG_PREFIX}" )";
    fi;

    if [ ! "${_MON_PID_FILE}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --pidfile $( quote "${_MON_PID_FILE}" )";
    fi;

    if [ ! "${_MON_OWN_PID_FILE}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --mon-pidfile $( quote "${_MON_OWN_PID_FILE}" )";
    fi;

    if [ ! "${_MON_RESTART_WINDOW}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --window $( quote "${_MON_RESTART_WINDOW}" )";
    fi;

    if [ ! "${_MON_RESTART_ATTEMPTS}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --attempts $( quote "${_MON_RESTART_ATTEMPTS}" )";
    fi;

    if [ ! "${_MON_ON_RESTART}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --on-restart $( quote "${_MON_ON_RESTART}" )";
    fi;

    if [ ! "${_MON_ON_ERROR}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} --on-error $( quote "${_MON_ON_ERROR}" )";
    fi;

    _MON_CMDLINE="${_MON_CMDLINE} $( quote "${*}" )";

    eval "nohup ${_MON_CMDLINE} 1>/dev/null 2>/dev/null &"

    return $?;
  fi;

  if [ ! "${_MON_OWN_PID_FILE}" = "" ]; then
    echo $$ > "${_MON_OWN_PID_FILE}";
  fi;

  while true; do
    if [ ! $( dlist_length _MON_RESTARTS ) -lt ${_MON_RESTART_ATTEMPTS} ]; then
      if [ ! "${_MON_ON_ERROR}" = "" ]; then
        eval sh -c "\"${_MON_ON_ERROR}\"";
      fi;

      return 1;
    fi;

    mon_run_once $@;

    local _MON_RC=$?;

    if [ ! "${_MON_ON_RESTART}" = "" ]; then
      eval sh -c "\"${_MON_ON_RESTART}\"";
    fi;

    dlist_push _MON_RESTARTS $(date +%s);

    while true; do
      if [ $( dlist_length _MON_RESTARTS ) -eq 0 ]; then
        break;
      fi;

      if [ $( dlist_get _MON_RESTARTS 0 ) -gt $(( $( date +%s ) - ${_MON_RESTART_WINDOW} )) ]; then
        break;
      fi;

      dlist_shift _MON_RESTARTS;
    done;

    sleep ${_MON_RESTART_DELAY};
  done;
}

mon_run_once() {
  local _MON_CMDLINE="sh -c \"\${*}\"";

  if [ ! "${_MON_LOG_FILE}" = "" ]; then
    if [ ! "${_MON_LOG_PREFIX}" = "" ]; then
      _MON_CMDLINE="${_MON_CMDLINE} | sed -e 's/^/${_MON_LOG_PREFIX}/'";
    fi;

    _MON_CMDLINE="${_MON_CMDLINE} >> ${_MON_LOG_FILE}";
  fi;

  eval ${_MON_CMDLINE} &

  if [ ! "${_MON_PID_FILE}" = "" ]; then
    echo $! > "${_MON_PID_FILE}";
  fi;

  wait $!;

  if [ ! "${_MON_PID_FILE}" = "" ]; then
    rm -f "${_MON_PID_FILE}";
  fi;

  return $?;
}

mon_status() {
  stat "${_MON_PID_FILE}" > /dev/null 2> /dev/null;

  if [ ! $? = 0 ]; then
    echo "Couldn't find pid file \`${_MON_PID_FILE}'";

    return 1;
  fi;

  local _MON_PID=$(cat "${_MON_PID_FILE}");

  ps -p "${_MON_PID}" > /dev/null;

  local _MON_RC=$?;

  if [ $_MON_RC = 0 ]; then
    echo "${_MON_PID} : alive";
  else
    echo "${_MON_PID} : dead";
  fi;

  return ${_MON_RC};
}

while [ $# -ne 0 ]; do
  _MON_ARG="${1}";

  case "${_MON_ARG}" in
    -h|--help)
      _MON_ACTION="help";
      ;;
    -V|--version)
      _MON_ACTION="version";
      ;;
    -l|--log)
      _MON_LOG_FILE="${2}";
      shift;
      ;;
    -s|--sleep)
      _MON_RESTART_DELAY="${2}";
      shift;
      ;;
    -S|--status)
      _MON_ACTION="status";
      ;;
    -p|--pidfile)
      _MON_PID_FILE="${2}";
      shift;
      ;;
    -m|--mon-pidfile)
      _MON_OWN_PID_FILE="${2}";
      shift;
      ;;
    -P|--prefix)
      _MON_LOG_PREFIX="${2}";
      shift;
      ;;
    -d|--daemonize)
      _MON_DAEMON="yes";
      ;;
    -w|--window)
      _MON_RESTART_WINDOW="${2}";
      shift;
      ;;
    -a|--attempts)
      _MON_RESTART_ATTEMPTS="${2}";
      shift;
      ;;
    -R|--on-restart)
      _MON_ON_RESTART="${2}";
      shift;
      ;;
    -E|--on-error)
      _MON_ON_ERROR="${2}";
      shift;
      ;;
    --)
      shift;
      break;
      ;;
    *)
      break;
      ;;
  esac;

  shift;
done;

case "${_MON_ACTION}" in
  help)
    mon_help;
    exit;
    ;;
  version)
    mon_version;
    exit;
    ;;
  status)
    mon_status;
    exit $?;
    ;;
  run)
    if [ $# -gt 0 ]; then
      mon_run $@;
      exit $?;
    else
      mon_help;
      exit;
    fi;
    ;;
esac;
