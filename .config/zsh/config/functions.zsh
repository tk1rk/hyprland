# commnad not found
# In case a command is not found, try to find the package that has it
function command_not_found_handler {
    local purple='\e[1;35m' bright='\e[0;1m' green='\e[1;32m' reset='\e[0m'
    printf 'zsh: command not found: %s\n' "$1"
    local entries=( ${(f)"$(/usr/bin/pacman -F --machinereadable -- "/usr/bin/$1")"} )
    if (( ${#entries[@]} )) ; then
        printf "${bright}$1${reset} may be found in the following packages:\n"
        local pkg
        for entry in "${entries[@]}" ; do
            local fields=( ${(0)entry} )
            if [[ "$pkg" != "${fields[2]}" ]]; then
                printf "${purple}%s/${bright}%s ${green}%s${reset}\n" "${fields[1]}" "${fields[2]}" "${fields[3]}"
            fi
            printf '    /%s\n' "${fields[4]}"
            pkg="${fields[2]}"
        done
    fi
    return 127
}

# auto-ls
function cd() {
    if [ -n "$1" ]; then
        builtin cd "$@" && command eza -lhA --no-time --icons=always --color=always --group-directories-first
    else
        builtin cd ~ && command eza -lhA --no-time --icons=always --color=always --group-directories-first    
    fi
}

# Extracts any archive(s) (if unp isn't installed) 
x() { 
    for archive in "$@"; do 
        if [ -f "$archive" ] ; then 
            case $archive in 
                    *.tar.bz2)   tar xvjf $archive    ;; 
                    *.tar.gz)    tar xvzf $archive    ;; 
                    *.bz2)       bunzip2 $archive     ;; 
                    *.rar)       rar x $archive       ;; 
                    *.gz)        gunzip $archive      ;; 
                    *.tar)       tar xvf $archive     ;; 
                    *.tbz2)      tar xvjf $archive    ;; 
                    *.tgz)       tar xvzf $archive    ;; 
                    *.zip)       unzip $archive       ;; 
                    *.Z)         uncompress $archive  ;; 
                    *.7z)        7z x $archive        ;; 
                    *)           echo "don't know how to extract '$archive'..." ;; 
            esac 
        else 
            echo "'$archive' is not a valid file!" 
        fi 
    done 
} 
  
# Searches for text in all files in the current folder 
ftext () { 
         # -i case-insensitive 
         # -I ignore binary files 
         # -H causes filename to be printed 
         # -r recursive search 
         # -n causes line number to be printed 
         # optional: -F treat search term as a literal, not a regular expression 
         # optional: -l only print filenames and not the matching lines ex. grep -irl "$1" * 
         grep -iIHrn --color=always "$1" . | less -r 
 } 
  
 # Copy file with a progress bar 
 cpp() 
 { 
         set -e 
         strace -q -ewrite cp -- "${1}" "${2}" 2>&1 \ 
         | awk '{ 
         count += $NF 
         if (count % 10 == 0) { 
                 percent = count / total_size * 100 
                 printf "%3d%% [", percent 
                 for (i=0;i<=percent;i++) 
                         printf "=" 
                         printf ">" 
                         for (i=percent;i<100;i++) 
                                 printf " " 
                                 printf "]\r" 
                         } 
                 } 
         END { print "" }' total_size="$(stat -c '%s' "${1}")" count=0 
 } 
  
 # Copy and go to the directory 
 cpg () 
 { 
         if [ -d "$2" ];then 
                 cp "$1" "$2" && cd "$2" 
         else 
                 cp "$1" "$2" 
         fi 
 } 
  
 # Move and go to the directory 
 mvg () 
 { 
         if [ -d "$2" ];then 
                 mv "$1" "$2" && cd "$2" 
         else 
                 mv "$1" "$2" 
         fi 
 } 
  
 # Create and go to the directory 
 mkdirg () 
 { 
         mkdir -p "$1" 
         cd "$1" 
 } 
  
 # Goes up a specified number of directories  (i.e. up 4) 
 up () 
 { 
         local d="" 
         limit=$1 
         for ((i=1 ; i <= limit ; i++)) 
                 do 
                         d=$d/.. 
                 done 
         d=$(echo $d | sed 's/^\///') 
         if [ -z "$d" ]; then 
                 d=.. 
         fi 
         cd $d 
 }


