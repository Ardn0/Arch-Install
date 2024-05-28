#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

export EDITOR='nvim'

alias ls='ls --color=auto'
alias grep='grep --color=auto'
#PS1='[\u@\h \W]\$ '

# Customized prompt
#PS1="[\u]-> \n "

get_git() {
	branch=$(git branch 2>/dev/null | grep '*' | cut -d '*' -f2)

	if [ -n "$branch" ]; then
		echo "($(echo $branch | xargs))"
	fi
}

PS1="[\w] \$(get_git) \nEnter command-> "

export PS1="\n${PS1}"


