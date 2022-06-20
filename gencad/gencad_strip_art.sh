#!/bin/bash
# SPDX-License-Identifier BSD-3-Clause
# Copyright (C) 2022 Sebastian "swiftgeek" Grzywna <swiftgeek+gencad@gmail.com>

set -euo pipefail

# Strip ALL the artwork from GenCAD files - traces on all layers and shapes
# Pad shapes are still required to create stencils for rework
# Vias are used as additional testpoints,
# and can be turned into solderpads for modwires
#
# From GenCAD spec 1.4
# Allowed characters:
# Only ASCII <TODO: regex> 0x20..0x7E, \n (0x0A) and \r (0x0D).
# Newlines:
# In GenCAD only \n is mandatory, \r is optional
# Keywords:
# In GenCAD lines cannot start with a space, and keywords starting the line must be followed by a space
# Case sensitivity:
# Keywords *must* be UPPERCASE

# TODO: check that we are indeed dealing with a GenCAD file
# TODO: number to amount of digits, then use it for printf formatting (line_count vs line_no)
# TODO: check bash version, tput and other helpers existence
# TODO: purge empty/unused layers: first stage get list of defined layers + list of (un)used layers; 2nd stage - simple sed should do
# TODO: simulate/verify - don't actually modify anything just generate statistics on how many lines / layers could be removed.


gencad_input=''
gencad_output=''

verbose='0'

# Since stdout is used for GenCAD, use stderr for all messages
msg_err () {
  echo -en "ERROR: $*\n" 1>&2
  exit 1
}

msg_info () {
  echo -en "INFO: $*\n" 1>&2
}

msg_dbg () {
  if [ $verbose == 1 ]; then
    echo -en "DBG: $*\n" 1>&2
  fi
}

usage () {
  echo -e "Usage: `basename $0` [OPTIONS] \n" \
    "\nMandatory arguments:\n" \
    "-i FILE\tPath to input GenCAD file\n" \
    "-o FILE\tPath to save processed GenCAD file\n" \
    "Pass '-' to use stdin/stdout for GenCAD\n" \
    "\nOptional arguments\n" \
    "-v\t\tVerbose output\n" \
    "-h\t\tThis help message\n" 1>&2
}


while getopts "hvi:o:" option; do
  case "$option" in
    i)
      if [ "$OPTARG" = '-' ]; then
        msg_info 'Reading GenCAD from stdin'
        gencad_input='/dev/stdin'
      elif [ ! -f "$OPTARG" ]; then
        msg_err "File $OPTARG not found"
      elif [ ! -r "$OPTARG" ]; then
        msg_err "Denied read access to file $OPTARG"
      else
        gencad_input="$OPTARG"
      fi
      ;;
    o)
      if [ "$OPTARG" = '-' ]; then
        msg_info 'Writing GenCAD to stdout'
        gencad_output='/dev/stdout'
      elif [ -e "$OPTARG" ]; then
        msg_err "File $OPTARG already exists!"
      elif [ ! -w "${OPTARG%/*}" ]; then
        msg_err "Denied write access to directory ${OPTARG%/*}"
      else
        gencad_output="$OPTARG"
      fi
      ;;
    v)
      verbose=1
      msg_dbg "Verbose mode is on"
      ;;
    h)
      usage
      exit 0
      ;;
    *)
      msg_err "Unknown option or missing argument."
      ;;
  esac
done

if [ -z "$gencad_input" ] || [ -z "$gencad_output" ]; then
  usage
  msg_err "It is required to specify -i and -o options (input and output files)"
fi

# terminfo clr_eol
ceol=$(tput el)

line_count=$(cat $gencad_input | wc -l)
line_pos="${#line_count}"
line_removed=0
line_no=0

SECTION=""

# touch/erase file
echo -n > "$gencad_output"

# Check for DOS line endings, and use it for output if detected
CRLF=''
if grep -q $'\r' "$gencad_input"; then
  msg_info 'Using DOS line ending'
  CRLF='\r'
fi


while read -r line; do
  line="${line%$'\r'}"
  line_no=$((line_no+1))
  if [[ "$line" =~ ^\$[A-Z]+([ ]*) ]]; then
    TOKEN=${line#\$} # TODO: strip ALL trailing spaces!
    if [[ "$TOKEN" =~ ^END[A-Z]+ ]]; then
      if [ -z "$SECTION" ] || [ $SECTION != "${TOKEN#END}" ]; then
        msg_err "Currently not in section ${TOKEN#END}"
      fi
      msg_dbg "\nLeaving section:	${TOKEN#END}."
      SECTION=''
    else
      msg_dbg "\nEntering section:	$TOKEN..."
      SECTION="$TOKEN"
    fi
  fi
  if [ "$SECTION" == 'SHAPES' ]; then
    if [[ "$line" =~ ^(LINE|ARC|CIRCLE|RECTANGLE)( ).* ]]; then
      msg_dbg "Stripping line $line_no : $line"
      line_removed=$((line_removed+1))
      continue
    fi
  fi
  if [ "$SECTION" == 'ROUTES' ]; then
    if [[ "$line" =~ ^(TRACK|LAYER|LINE|ARC|CIRCLE|RECTANGLE)( ).* ]]; then
      msg_dbg "Stripping line $line_no : $line"
      line_removed=$((line_removed+1))
      continue
    fi
  fi

  echo "${line}${CRLF}" >> "$gencad_output"
  if [ $verbose -eq 0 ]; then
    printf "\r${ceol}Procesed %${line_pos}d/$line_count (%3d%%) $SECTION" "$line_no" "$((line_no*100/line_count))" 1>&2
  else
    msg_dbg "Line No $line_no/$line_count : $line"
  fi
done < $gencad_input
echo

# Statistics
msg_info "Stripped $line_removed lines. (Reduced overall count by $((line_removed*100/line_count))%)"


