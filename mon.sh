#!/usr/local/bin/dash

_MON_VERSION="0.0.0";

_MON_ACTION="run";
_MON_DAEMON="no";
_MON_COMMAND="";
_MON_LOG_PREFIX="";
_MON_LOG_FILE="mon.log";
_MON_PID_FILE="";
_MON_OWN_PID_FILE="";
_MON_RESTART_DELAY="1";
_MON_RESTART_TRIES="10";
_MON_ON_RESTART="echo restarting";
_MON_ON_ERROR="echo there was an error";

_MON_RESTART_COUNT=0

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
  -a, --attempts <n>            retry attempts within 60 seconds [10]
  -R, --on-restart <cmd>        execute <cmd> on restarts
  -E, --on-error <cmd>          execute <cmd> on error

EOF
}

mon_run() {
  if [ ! "${_MON_OWN_PID_FILE}" = "" ]; then
    echo $$ > "${_MON_OWN_PID_FILE}";
  fi;

  while true; do
    : $(( _MON_RESTART_COUNT += 1 ));

    if [ ${_MON_RESTART_TRIES} -gt 0 -a ${_MON_RESTART_COUNT} -gt ${_MON_RESTART_TRIES} ]; then
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

  echo $! from $$;

  wait $!;

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
    echo "${_MON_PID} : alive"
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
