#!/bin/bash

# 申明全局变量

# 当前行缓存
declare -g BUFFER=""
# 当前用户输入的字符
declare -g ichar
# 历史命令
declare -g HIST=()
export IFS=""
# prompt
declare -g uprompt
# 默认读取字符个数
declare -g default_ccount=1
# 建议
declare -g suggestions=""
# 建议颜色
declare -g scolor
# 是否使用了方向键操作
declare -g rarrow_key=0
# 上一条建议
declare -g pre_suggestion=""
# 光标前的字符个数
declare -ig CURSOR=0
# 当前命令编号
declare -g cur_cmd_index=-1
# 使用到的不可打印编码
declare -gA unprintables
# 用于向后删除或移动一个字匹配的正则表达式
# word <--
declare -g bw_general_pattern='(\S*\s*)$'
# 用于向前移动一个字时使用的正则表达式
# --> word
declare -g mfw_general_pattern='^(\s*)(\S*)(\s*)'
# 命令参数定义
declare -g cmd_pattern='(\S+)(\s*)(\S*)'
# 当前所在目录
declare -g APWD=$PWD
# 目录字符串在prompt中的长度
declare -ig dlen
# cd补全时文件夹的颜色
declare -ig dcolor
# whoamia颜色
declare -ig ucolor
# prompt param 颜色
declare -ig ccolor
# nodename颜色
declare -ig ncolor
# prompt文件夹颜色
declare -ig pdcolor
# prompt右侧提示符号
declare -g picon
export TERM=xterm-256color
declare -ig last_result=0
# 默认prompt
declare -g DEFAULT_PROMPT
# int sig
declare -ig sigint=130
# 程序名称
declare -g PROGRAM_NAME=abws
# .bashrc
declare -g SOURCE_ALIAS="$HOME/.bashrc"

# 输出函数
echo-ne() {
  [[ ! "$1" =~ "\e["([0-9]+)([C|D])$ ]] && { printf "%b" "$1"; return; }
  local moves=0
  local astep=1
  local ccur=$CURSOR
  local mn=${BASH_REMATCH[1]}
  local direction=${BASH_REMATCH[2]}
  if [[ -n "$2" ]]; then
    local mvbuff="$2"
  else
    if [[ $direction == 'C' ]]; then
        local mvbuff="${BUFFER:ccur:mn}"
    else
        local mvbuff="${BUFFER:$(( ccur - mn > 0 ? ccur - mn : 0 )):mn}"
    fi
  fi
  # 因为调用echo-ne的命令可能会用i,j,k作为下标
  # 这里挑选一个比较偏僻的字符z
  for ((z = 0; z < ${#mvbuff}; z++))
  do
    if is_unicode_char "${mvbuff:z:1}"; then
      (( moves+=astep ))
    fi
  done
  printf "%b" "\e[$(( moves + mn ))$direction"
}

# 返回第一个参数的ascii值
ascii() {
	printf '%d' "'$1"
}

user() {
  : \\u
  printf "%s" "${_@P}"
}

hostname() {
  : \\h
  printf "%s" "${_@P}"
}

# 回放上一个命令的运行结果
return_last_result() {
  return $last_result
}

# 一种判断字符是否为unicode的办法
# 判断字符是否为unicode字符，是则返回0,不是返回1
is_unicode_char() {
  hex_chars=$(printf '%04x' "'$1")
  hex_chars=${hex_chars:0:4}
  # 只考虑了bmp(Basic Multilingual Plane)内的字符未考虑Astral Plane
  if [[ "$hex_chars" == "00"* ]] || [[ "$hex_chars" == "01"* ]]; then
    return 1
  fi
  return 0
}

# 确认第一个参数是否在定义的不可打印符号列表内
is_in_defined_unprint_key() {
	if [[ ${unprintables[*]##*"$1"} != "${unprintables[*]}" ]]; then
    return 0
  fi;
  return 1
}

# 用于优化光标显示的装饰器(并没有遵循一个装饰器的定义)
invisible_semi_decorator() {
  tput civis
  eval "$1"
  tput cnorm
}

# 处理错误信息
# 参数1为报错的命令,参数2为命令返回结果(不要用err, cmd, errmsg作为参数 !important)
perror() {
  local cmd="$1"
  local -n errmsg="$2"
  local err="$(</tmp/error)"
  [[ -z $err ]] && return 0
  : "${err#*"$cmd"}"
  errmsg="$cmd$_"
}

refresh_prompt() {
  if [[ "$PWD" == "$HOME" ]]; then
    uprompt=$DEFAULT_PROMPT~"\e[0m\e[1;37m${picon}\e[0m\n\e[1;${ccolor}m╰─λ\e[0m "
    return
  fi
  IFS='/' read -ra dirs <<< "$PWD"
  local last_dir 
  # last_dir="${dirs[-1]}"
  # unset "dirs[-1]"
  last_dir="${dirs[$(( ${#dirs[@]} - 1 ))]}"
  unset "dirs[$(( ${#dirs[@]} - 1 ))]"
  [[ "${PWD#$HOME}" != "$PWD" ]] && homef=1
  # Linux下主目录可以设置在别的目录下，不一定要在/home下
  # [[ "home" == "${dirs[1]}" && "$(user)" == "${dirs[2]}" ]] && homef=1
  for i in "${!dirs[@]}"; 
  do
    dirs[i]=${dirs[$i]:0:dlen}
  done
  # 默认最后一个文件夹名称完整输出
  APWD="$(IFS='/'; echo "${dirs[*]}")/$last_dir"
  [[ $homef -eq 1 ]] && APWD="~${APWD:$((dlen * 2 + 2))}"
  uprompt=$DEFAULT_PROMPT$APWD"\e[0m\e[1;37m${picon}\e[0m\n\e[1;${ccolor}m╰─λ\e[0m "
}

init() {
  trap on_sig_int SIGINT
  # 默认提示颜色为亮黑色(灰色)
	scolor=90
  # 目录字符串在prompt中的长度默认为2
  dlen=2
  # cd补全时文件夹的颜色默认为蓝色
  dcolor=34
  # prompt提示符号默认为tux
  picon=" "
  # whoami 颜色默认为亮红色
  ucolor=91
  # prompt param 颜色为亮红色
  ccolor=91
  # nodename 颜色默认为绿色
  ncolor=32
  # prompt文件夹颜色默认为洋红色
  pdcolor=35
  # 默认prompt
  DEFAULT_PROMPT="\e[1;${ccolor}m╭─\e[0m\e[1;${ucolor}m$(user)\e[0m@\e[1;${ncolor}m$(hostname) \e[0m\e[1;${pdcolor}m"
  # 初始化默认不可打印功能性ASCII
  unprintables[$(( unprintables[enter]=0 ))]=enter
  unprintables[$(( unprintables[ctrl+a]=1 ))]=ctrl+a
  unprintables[$(( unprintables[ctrl+b]=2 ))]=ctrl+b
  unprintables[$(( unprintables[ctrl+c]=3 ))]=ctrl+c
  unprintables[$(( unprintables[ctrl+d]=4 ))]=ctrl+d
  unprintables[$(( unprintables[ctrl+e]=5 ))]=ctrl+e
  unprintables[$(( unprintables[ctrl+f]=6 ))]=ctrl+f
  unprintables[$(( unprintables[ctrl+i]=9 ))]=ctrl+i
  unprintables[$(( unprintables[tab]=9 ))]=tab
  unprintables[$(( unprintables[ctrl+k]=11 ))]=ctrl+k
  unprintables[$(( unprintables[ctrl+l]=12 ))]=ctrl+l
  unprintables[$(( unprintables[ctrl+n]=14 ))]=ctrl+n
  unprintables[$(( unprintables[ctrl+p]=16 ))]=ctrl+p
  unprintables[$(( unprintables[ctrl+u]=21 ))]=ctrl+u
  unprintables[$(( unprintables[ctrl+w]=23 ))]=ctrl+w
  unprintables[$(( unprintables[backspace]=127 ))]=backspace
  # SOURCE_ALIAS 用于指定定义alias的文件
  [[ -n $SOURCE_ALIAS ]] && . $SOURCE_ALIAS
  refresh_prompt
}

# 计算除了输入字符以外的建议的长度，并使用引用对$1进行赋值
# !Important: 调用时不要使用le作为参数名
cal_slen() {
	: "${suggestions#"$BUFFER"}"
	local le=${#_}
	local -n l=$1
	l=$le
}

trim_string() {
	: "${1#"${1%%[![:blank:]]*}"}"
	: "${_%"${_##*[![:blank:]]}"}"
	printf '%s' "$_"
}

# TODO: 优化获取建议策略
generate_suggestions() {
  for ((index=$(( ${#HIST[@]} - 1 )); index>=0; index--))
  do
    local cmd=${HIST[index]}
		if [[ ${cmd#"$BUFFER"} != "${cmd}" ]]; then
			# 如果输入的建议和cmd完全相同则不需要建议
			if [[ -z ${cmd#"$BUFFER"} ]]; then
				suggestions=""
				return $?
			fi
			suggestions=$(trim_string "$cmd")
			return $?
		fi
	done
	suggestions=""
}

# 刷新buffer
# TODO: 有buffer区域相关变量刷新后都调用这个函数刷新即可
refresh_buffer() {
  :
}

clear_pre_suggestion() {
  # TODO: 优化删除之前建议逻辑
	if [[ -n $pre_suggestion ]]; then
    tput civis
    local pos=$(( ${#BUFFER} - CURSOR ))
    local -i ic
    ic=$(ascii "$ichar")
    if [[ $ic -eq ${unprintables[backspace]} || $ic -eq ${unprintables[ctrl+d]} ]]; then
      local len=$(( ${#pre_suggestion} + 1 ))
      [[ $pos -gt 0 ]] && echo-ne "\e[$(( pos ))C"
      echo-ne "\e[K"
      if [[ $CURSOR -gt 0 && $pos -gt 0 ]]; then
        echo-ne "\e[${pos}D" "${BUFFER: -pos}"
      fi
    else
      # 回车等空白符需要特殊处理
      is_in_defined_unprint_key "$(ascii "$ichar")"
      local len=$(( !$? ? ${#pre_suggestion} : $(( ${#pre_suggestion} - 1 )) ))
      [[ $pos -gt 0 ]] && echo-ne "\e[${pos}C"
      echo-ne "\e[K"
      if [[ $CURSOR -ge 0 && $pos -gt 0 ]]; then
        echo-ne "\e[${pos}D" "${BUFFER: -pos}"
      fi
    fi
    tput cnorm
    pre_suggestion=""
	fi
}

# Ctrl+c hook
on_sig_int() {
  # 将Ctrl+c视作一个不可打印符号，用于清理之前建议
  ichar=""
  clear_pre_suggestion
	echo-ne "\n""$uprompt"
  tput sc
  BUFFER=""
  (( CURSOR=0 ))
  unset ichar
  rarrow_key=0
  suggestions=""
  pre_suggestion=""
  cur_cmd_index=-1
  tput cnorm
}


# 删除BUFFER中的一个字符
# 当第一个参数为1时，光标位置不变，删除光标所在位置的字符。
# 当第一个参数不为1时，删除光标之前的一个字符。
# TODO: 当前函数实现，运行速度上太慢了，需要优化
deletekey() {
	if [[ -z $1 && $CURSOR -gt 0 ]]; then
		# echo-ne "\b"
    # 注意这里光标位置减1,但是实际光标位置并没有改变
    (( CURSOR-- ))
    local post=${BUFFER:CURSOR+1}
    local cha="${BUFFER:CURSOR:1}"
    # 
    # 更新输出效果
    #
    # 当CURSOR为0时也会移动一个字符距离
    echo-ne "\e[$(( CURSOR + 1 ))D"
    BUFFER=${BUFFER:0: CURSOR}$post
    # TODO: 优化重复代码以及刷新逻辑
    if is_unicode_char "$cha"; then
      echo-ne "$BUFFER""  "
      echo-ne "\e[$(( ${#post} + 2))D" "$post  "
    else
      # 使用空格覆盖一个字符差距
      echo-ne "$BUFFER"" "
      echo-ne "\e[$(( ${#post} + 1))D" "$post "
    fi
  elif [[ $1 -eq 1 && $CURSOR -ge 0 ]]; then
    local pre=${BUFFER:0: CURSOR}
    local post=${BUFFER:CURSOR + 1}
    local cha=${BUFFER:CURSOR:1}
    if [[ $CURSOR -ne 0 ]]; then
      echo-ne "\e[$(( CURSOR ))D"
    fi
    BUFFER=$pre$post
    if is_unicode_char "$cha"; then
      echo-ne "$BUFFER""  "
      echo-ne "\e[$(( ${#post} + 2))D" "$post  "
    else
      echo-ne "$BUFFER"" "
      echo-ne "\e[$(( ${#post} + 1))D" "$post "
    fi
  fi
}

deletekey_s() {
  tput civis
	for ((i = 0; i < $1; i++)); do
		deletekey
	done
  tput cnorm
}

self-insert() {
  local post=${BUFFER:CURSOR}
  is_in_defined_unprint_key "$(ascii "$ichar")"
  if [[ "$ichar" == $'\x1b' || $? -eq 0 ]]; then
    ichar=""
    return
  fi
  echo -n "$ichar$post"
  if [[ ${#post} -gt 0 ]]; then
    invisible_semi_decorator 'echo-ne "\e[${#post}D" "$post"'
  fi
}

handle-insert() {
  self-insert
	# 当之前产生了建议但是当前输入没有相关建议时，
	# 需要将之前的建议清除。
	clear_pre_suggestion
	if [[ -n $suggestions ]]; then
    tput civis
    if [[ $CURSOR -lt ${#BUFFER} ]]; then
      echo-ne "\e[$(( ${#BUFFER} - CURSOR ))C" "${BUFFER: -$(( ${#BUFFER} - CURSOR ))}"
		  echo-ne "\e[1;${scolor}m${suggestions#"$BUFFER"}\e[0m"
      echo-ne "\e[$(( ${#BUFFER} - CURSOR ))D" "${BUFFER: -$(( ${#BUFFER} - CURSOR ))}"
    else
		  echo-ne "\e[1;${scolor}m${suggestions#"$BUFFER"}\e[0m"
    fi
		pre_suggestion="${suggestions#"$BUFFER"}"
    # 回退光标，保留建议
	  cal_slen len
	  echo-ne "\e[${len}D" "$pre_suggestion"
    tput cnorm
  fi
}

accept_suggestion() {
	echo-ne "${suggestions#"$BUFFER"}"
	BUFFER+="${suggestions#"$BUFFER"}"
  CURSOR=${#BUFFER}
  pre_suggestion=""
  suggestions=""
}

handle_delete() {
	deletekey
	# 删除之后重新生成建议
	generate_suggestions
}

clear_buffer() {
  beginning-of-line
  kill-line-to-end
}

lastcmd() {
	if [[ $cur_cmd_index -gt 0 ]]; then
	  clear_buffer
    (( cur_cmd_index-- ))
		echo-ne "${HIST[$cur_cmd_index]}"
		BUFFER=${HIST[$cur_cmd_index]}
    (( CURSOR=${#BUFFER} ))
	fi
}

nextcmd() {
  if [[ $cur_cmd_index -lt $(( ${#HIST[@]} - 1)) ]]; then
	  clear_buffer
    (( cur_cmd_index++ ))
		echo-ne "${HIST[$cur_cmd_index]}"
		BUFFER=${HIST[$cur_cmd_index]}
    (( CURSOR=${#BUFFER} ))
	fi
}

cursor_left() {
  [[ $CURSOR -le 0 ]] && return
  echo-ne "\e[1D"
  (( CURSOR-- ))
}

cursor_right() {
  [[ $CURSOR == "${#BUFFER}" ]] && return
  echo-ne "\e[1C"
  (( CURSOR++ ))
}

# previous-history
# Ctrl+p == 16
previous-history() {
  lastcmd
}

# next-history
# Ctrl+n == 14
next-history() {
  nextcmd
}

# forward-char
# Ctrl+f == 6
forward-char() {
  cursor_right
}

# kill-line-to-start
# Ctrl+u == 21
kill-line-to-start() {
  local -i tcur
  tcur=$CURSOR
  deletekey_s $tcur
}

# kill-line-to-end
# Ctrl+k == 11
kill-line-to-end() {
  pre_suggestion=${suggestions#"$BUFFER"}
  clear_pre_suggestion
  echo-ne "\e[K"
  BUFFER=${BUFFER:0: CURSOR}
}

# end-of-line
# Ctrl+e == 5
end-of-line() {
  local -i lps=$(( ${#BUFFER} - CURSOR ))
  if [[ $lps -le 0 && -n $suggestions ]]; then
    accept_suggestion
  fi
  for ((i = 0; i < lps; i++))
  do
    forward-char
  done
}

# delete-char
# Ctrl+d == 4
delete-char() {
  deletekey 1
}

# backward-char
# Ctrl+b == 2
backward-char() {
  cursor_left
}

# beginning-of-line
# Ctrl+a == 1
beginning-of-line() {
  local -i tcur=$CURSOR
  (( CURSOR-=tcur ))
  tput rc
}

# 一般的补全提示
_comp_general() {
  local IFS=$'\n'
  local completion_reply=()
  local cmd
  local need_to_match
  local expa_alias=$(alias "${BASH_REMATCH[1]}" 2>/dev/null | sed "s/.*='\([^']*\)'/\1/")
  if [[ ${#expa_alias} -gt 0 ]]; then 
    cmd="${expa_alias[0]%%[[:blank:]]*}"
  else
    cmd="${BASH_REMATCH[1]}"
  fi
  cmd=$(which "$cmd" 2>/dev/null)
  [[ -n $cmd ]] && need_to_match="${BASH_REMATCH[3]}"
  [[ -z $cmd && ! -f "${BASH_REMATCH[1]}" && ! -d "${BASH_REMATCH[1]}" ]] && return
  [[ -z $cmd ]] && need_to_match="${BASH_REMATCH[1]}"
  completion_reply=( $(compgen -f -- "$need_to_match") )
  clear_pre_suggestion
  if [[ ${#completion_reply[@]} -eq 1 ]]; then
    # 文件夹补全防止多次补全
    [[ ${BUFFER/%"${completion_reply[0]}/"/} != "$BUFFER" ]] && return
    # 文件补全防止多次补全
    [[ ${BUFFER/%"${completion_reply[0]}"/} != "$BUFFER" ]] && return
    # 如果BUFFER已经被修改，则不需要再次修改
    local dir_sep="/"
    local reply="${completion_reply[0]}"
    local suffix="$need_to_match"
    if [[ -f "$reply" || -d "$reply" ]]; then
      local nshow=${reply#"$suffix"}
      local len=${#nshow}
      BUFFER="${BUFFER%"$suffix"}$reply"
      printf '%s' "$nshow"
      if [[ -d "$reply" ]]; then
        BUFFER="$BUFFER$dir_sep"
        printf '%s' "/"
        (( CURSOR+=len+1 ))
      else
        (( CURSOR+=len ))
      fi
    fi
    return
  fi
  for i in "${!completion_reply[@]}"
  do
    # TODO: 排版输出
    [[ $(( i  % 3 )) -eq 0 ]] && echo
    if [[ -d ${completion_reply[i]} ]]; then
      echo-ne "\e[1;${dcolor}m${completion_reply[i]}\e[0m/\t"
      continue
    fi
    if [[ -f ${completion_reply[i]} ]]; then
      echo-ne "${completion_reply[i]}\t"
    fi
  done
	echo-ne "\n""$uprompt"
  tput sc
  echo -n "$BUFFER"
}

_comp_cd() {
  # local cd_pattern='^\s*cd(\s+)(\S*)'
  # [[ ! $BUFFER =~ $cd_pattern ]] && return
  [[ ${BASH_REMATCH[2]} == '~' ]] && return

  # 更多命令已有补全函数可以查看 https://github.com/scop/bash-completion/
  local IFS=$' \t\n'    # normalize IFS
  local cur _skipdot _cdpath
  local i j k
  local completion_reply=()

  case "${BASH_REMATCH[2]}" in
  \~*)    eval cur="${BASH_REMATCH[2]}" ;;
  *)      cur="${BASH_REMATCH[2]}" ;;
  esac

  if [[ -z "${CDPATH:-}" ]] || [[ "$cur" == @(./*|../*|/*) ]]; then
      # compgen 结果为一个匹配项占据一行
      IFS=$'\n'
      completion_reply=( $(compgen -d -- "$cur") )
      IFS=$' \t\n'
  else
      IFS=$'\n'
      _skipdot=false
      # 将空目录转为.
      _cdpath=${CDPATH/#:/.:}
      _cdpath=${_cdpath//::/:.:}
      _cdpath=${_cdpath/%:/:.}
      for i in ${_cdpath//:/$'\n'}; do
          if [[ $i -ef . ]]; then _skipdot=true; fi
          k="${#completion_reply[@]}"
          for j in $( compgen -d -- "$i/$cur" ); do
              completion_reply[k++]=${j#$i/}        
          done
      done
      $_skipdot || completion_reply+=( $(compgen -d -- "$cur") )
      IFS=$' \t\n'
  fi

  if shopt -q cdable_vars && [[ ${#completion_reply[@]} -eq 0 ]]; then
      completion_reply=( $(compgen -v -- "$cur") )
  fi

  # 将eval之后的家目录转换为~
  read -r -a completion_reply <<< "${completion_reply[*]//$HOME/\~}"

  # 修改BUFFER
  if [[ ${#completion_reply[@]} -eq 1 ]]; then 
    [[ ${BUFFER/%"${completion_reply[0]}/"/} != "$BUFFER" ]] && return
    # 如果BUFFER已经被修改，则不需要再次修改
    BUFFER=${BUFFER%"${BASH_REMATCH[2]}"}"${completion_reply[0]}/"
    local ct="${completion_reply[0]#${BASH_REMATCH[2]}}"
    echo-ne "$ct/"
    (( CURSOR+=${#ct} + 1 ))
    return
  elif [[ ${#completion_reply[@]} -gt 1 ]]; then
    clear_pre_suggestion
    echo
    for ((i = 0; i < ${#completion_reply[@]}; i++)) 
    do
      echo-ne "\e[1;${dcolor}m${completion_reply[i]}\e[0m/\t"
      # TODO: 排版输出
      [[ $(( $((i + 1)) % 3 )) -eq 0 ]] && echo
    done
	  echo-ne "\n""$uprompt"
    tput sc
    echo -n "$BUFFER"
  fi
}

# expand-or-complete
# Ctrl+i == 9
expand-or-complete() {
  local general_file_pattern='^\s*(\S+)(\s+)(\S*)'
  local cd_pattern='^\s*cd(\s+)(\S*)'
  local general_dir_pattern="^\s*(\S+)(\s*)(\S*)"
  [[ $BUFFER =~ $cd_pattern ]] && { invisible_semi_decorator '_comp_cd'; return; }
  [[ $BUFFER =~ $general_file_pattern ]] && { invisible_semi_decorator '_comp_general'; return; }
  [[ $BUFFER =~ $general_dir_pattern ]] && { invisible_semi_decorator '_comp_general'; return; }
}

# clear_screen
# Ctrl+l == 12
clear_screen() {
  tput clear
	echo-ne "$uprompt"
  tput sc
}

# backward-kill-word
# Ctrl+w == 23
backward-kill-word() {
  local prebuf=${BUFFER:0: CURSOR}
  if [[ $prebuf =~ $bw_general_pattern ]]; then
    local mlen=${#BASH_REMATCH[1]}
    deletekey_s "$mlen"
  fi
}

ctrl+abdefwku() {
  case $1 in
    "${unprintables[ctrl+a]}")
    # Ctrl+a == 1
    beginning-of-line
    rarrow_key=1
      ;;
    "${unprintables[ctrl+b]}")
    # Ctrl+b == 2
    backward-char
    rarrow_key=1
      ;;
    "${unprintables[ctrl+d]}")
    # Ctrl+d == 4
    clear_pre_suggestion
    delete-char
    generate_suggestions
      ;;
    "${unprintables[ctrl+e]}")
    # Ctrl+e == 5
    end-of-line
    rarrow_key=1
      ;;
    "${unprintables[ctrl+f]}")
    # Ctrl+f == 6
    forward-char
    rarrow_key=1
      ;;
    "${unprintables[ctrl+k]}")
    # Ctrl+k == 11
    kill-line-to-end
    rarrow_key=1
      ;;
    "${unprintables[ctrl+n]}")
    # Ctrl+n == 14
    next-history
    rarrow_key=1
      ;;
    "${unprintables[ctrl+p]}")
    # Ctrl+p == 16
    previous-history
    rarrow_key=1
      ;;
    "${unprintables[ctrl+u]}")
    # Ctrl+u == 21
    clear_pre_suggestion
    kill-line-to-start
    generate_suggestions
      ;;
    "${unprintables[ctrl+w]}")
    # Ctrl+w == 23
    clear_pre_suggestion
    backward-kill-word
    generate_suggestions
      ;;
    "${unprintables[ctrl+l]}")
    clear_screen
    rarrow_key=1
      ;;
    "${unprintables[ctrl+i]}" | "${unprintables[tab]}")
    expand-or-complete 
    rarrow_key=1
      ;;
  esac
}

forward-word() {
  local postbuf=${BUFFER:CURSOR}
  if [[ $postbuf =~ $mfw_general_pattern ]]; then
    local mlen=${#BASH_REMATCH[1]}
    local mmlen=$(( ${#BASH_REMATCH[2]} + ${#BASH_REMATCH[3]} ))
    if [[ $mlen -ne 0 ]]; then
      invisible_semi_decorator '
      for ((i = 0; i < mlen; i++))
      do
        cursor_right
      done
      '
      return
    fi
    # 如果第一组为匹配则第二组长度不可能为0
    invisible_semi_decorator '
    for ((i = 0; i < mmlen; i++))
    do
      cursor_right
    done
    '
  fi
}

forward-kill-word() {
  local postbuf=${BUFFER:CURSOR}
  if [[ $postbuf =~ $mfw_general_pattern ]]; then
    local mlen=$(( ${#BASH_REMATCH[1]} + ${#BASH_REMATCH[2]} ))
    invisible_semi_decorator '
    for ((i = 0; i < mlen; i++))    
    do
      delete-char
    done
    '
  fi
}

backward-word() {
  local prebuf=${BUFFER:0: CURSOR}
  if [[ $prebuf =~ $bw_general_pattern ]]; then
    local mlen=${#BASH_REMATCH[1]}
    invisible_semi_decorator '
    for ((i = 0; i < mlen; i++))
    do
      cursor_left
    done
    '
  fi
}

read_key() {
  read -rsn1
  case $REPLY in
    'b')
      # Alt+b
      backward-word
	    rarrow_key=1
      return
      ;;
    'f')
      # Alt+f
      forward-word
	    rarrow_key=1
      return
      ;;
    'd')
      # Alt+d
      clear_pre_suggestion
      forward-kill-word
      generate_suggestions
      return
      ;;
  esac
	read -rsn1 input
	case "$REPLY$input" in
	'[A')
		lastcmd
		;;
	'[B')
		nextcmd
		;;
	'[C')
    if [[ $CURSOR -lt ${#BUFFER} ]]; then
      cursor_right
    else
		  accept_suggestion
    fi
		;;
  '[D')
    cursor_left
    ;;
	esac
	rarrow_key=1
}

clearkey() {
	rarrow_key=0
}

getcmdkey() {
	read -rsn $default_ccount ichar
  local -i rn
  rn=$(ascii "$ichar")
	if [[ $rn -eq ${unprintables[enter]} ]]; then
		BUFFER=$(trim_string "$BUFFER")
		HIST+=("$BUFFER")
    clear_pre_suggestion
    (( CURSOR=0 ))
		(( cur_cmd_index=${#HIST[@]} ))
    suggestions=""
    return
  fi
	if [[ $rn -eq ${unprintables[backspace]} ]]; then
		handle_delete
    return
  fi
	if [[ $ichar == $'\x1b' ]]; then
		read_key
    # 注意此处ichar没有被置空，'\x1b'可能转义其他字符
    return
  fi
  if is_in_defined_unprint_key $rn; then
    ctrl+abdefwku $rn
    return
  else
    BUFFER=${BUFFER:0: CURSOR}"$ichar"${BUFFER:CURSOR}
    (( CURSOR++ ))
	  generate_suggestions
  fi
}

# ========================命令实现==========================
# 实际上调用命令可以自己修改

# history
# 这里的history是当前程序的命令，而非原来shell的history命令
cmdhist() {
	echo -e "\n"
	for ((i = 0; i < ${#HIST[@]}; i++)); do
		echo -e "$((i + 1)) ${HIST[$i]}"
	done
  return $?
}

# cd
cmdcd() {
  if [[ -z $1 ]]; then
    cd || return $?
    APWD="~"
  else
    eval dir="$1"
    cd "$dir" 2>/tmp/error
    local lastret=$?
    local emsg
    perror "cd" emsg
    [[ -n $emsg ]] && { echo -e "\n$PROGRAM_NAME: $emsg"; return $lastret; }
    APWD="$dir"
  fi
  refresh_prompt
  printf "\n"
}

# exit
cmdexit() {
  echo -e "\nexit"
  exit 0
}

cmdjustdo() {
  [[ ! $BUFFER =~ $cmd_pattern ]] && return
  local cmd
  [[ ${#BASH_REMATCH[1]} -ne 0 ]] && cmd=${BASH_REMATCH[1]}
  [[ -z $cmd && ${#BASH_REMATCH[3]} -ne 0 ]] && cmd=${BASH_REMATCH[3]}
  # 处理alias
  expa_alias=$(alias "$cmd" 2>/dev/null | sed "s/.*='\([^']*\)'/\1/")
  if [[ ${#expa_alias} -eq 0 ]]; then
    local execbuf='eval "$BUFFER" 2>/tmp/error;'
  else
    local execbuf='eval "${BUFFER/$cmd/${expa_alias[0]}}" 2>/tmp/error'
  fi
  echo; 
  return_last_result; 
  eval "$execbuf"
  local rt=$?; 
  [[ ${#expa_alias} -gt 0 ]] && cmd="${expa_alias[0]%%[[:blank:]]*}" 
  local emsg;
  perror "$cmd" emsg;
  [[ -n $emsg ]] && echo -e "\n$PROGRAM_NAME: $emsg";
  return $rt;
}

# =========================================================

# 执行命令
execute_cmd() {
  local cmd
  local args
  local ret
  if [[ ! $BUFFER =~ $cmd_pattern ]]; then
    suggestions=""
    BUFFER=""
    return
  fi
  if [[ ${#BASH_REMATCH[1]} -ne 0 ]]; then
    cmd=${BASH_REMATCH[1]}
    args=${BASH_REMATCH[3]}
  elif [[ ${#BASH_REMATCH[3]} -ne 0 ]]; then
    cmd=${BASH_REMATCH[3]}
  fi
  case $cmd in
    history)
	  cmdhist 
    ret=$?
      ;;
    cd)
    cmdcd "$args"
    ret=$?
      ;;
    exit)
    cmdexit
      ;;
    *)
    cmdjustdo
    ret=$?
      ;;
  esac
  suggestions=""
  BUFFER=""
  return $ret
}

prompt() {
	if [[ $(ascii "$ichar") -eq ${unprintables[enter]} ]]; then
		execute_cmd
    last_result=$?
    [[ $last_result -ne $sigint ]] && echo-ne "$uprompt"
    tput sc
	else
		handle-insert
	fi
}

main() {
  echo-ne "$uprompt"
  tput sc
  while :; do
  	clearkey
  	getcmdkey
  	if [[ $rarrow_key -eq 1 ]]; then
  		continue
  	fi
  	prompt
  done
}

init
main
