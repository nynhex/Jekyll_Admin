#!/usr/bin/env bash


## Exit if not running with root/level permissions
if [[ "${EUID}" != '0' ]]; then echo "Try: sudo source ${0##*/}"; exit 1; fi


maybe_install_ruby_to_home(){
    _user="${1:?No user name provided}"
    _home="$(awk -F':' -v _user="${_user}" '$0 ~ "^" _user ":" {print $6}' /etc/passwd)"

    local _ruby_version="$(su --shell "$(which bash)" --command "ruby --version | awk '{print $2}'" --login ${_user})"
    local _ruby_version="${_ruby_version%.*}"

    local _ruby_version_main="${_ruby_version%.*}"
    local _ruby_version_sub="${_ruby_version#*.}"

    if [[ "${_ruby_version_main}" -ge '2' ]] && [[ "${_ruby_version_sub}" -ge '3' ]]; then
        printf 'Nothing for %s to do\n' "${FUNCNAME[0]}"
        return 0
    fi

    printf '%s installing Ruby to %s home\n' "${FUNCNAME[0]}" "${_user}"

    su --shell $(which bash) --login ${_user} <<'EOF'
gpg2 --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
curl -sSL https://get.rvm.io | bash -s stable --rails
source ${HOME}/.bash_profile
EOF
    printf '## %s finished\n' "${FUNCNAME[0]}"
}


jekyll_modify_user_path(){
    _user="${1:?No user name provided}"
    _home="$(awk -F':' -v _user="${_user}" '$0 ~ "^" _user ":" {print $6}' /etc/passwd)"
    if [ -f "${_home}/.bash_aliases" ]; then
        printf '%s/.bash_aliases already exists\n' "${_home}" >&2
        return 1
    fi
    ## Save new user path variable for Ruby executables
    su --shell $(which bash) --command 'touch ${HOME}/.bash_aliases' --login ${_user}
    tee -a "${_home}/.bash_aliases" 1>/dev/null <<'EOF'
## Ruby exports for user level gem & bundle installs
export GEM_HOME="${HOME}/.gem"
export PATH="${GEM_HOME}/bin:${PATH}"
EOF

    printf '## %s finished\n' "${FUNCNAME[0]}"
}


jekyll_user_install(){
    _user="${1:?No user name provided}"
    ## Install bundler & jekyll under new user home directory
    ##  Note one must source .bash_aliases upon every gem interactive login because '--system'
    ##  option was used during adduser command, so there be no fancy .bashrc file by default
    ##  to source files for users... but this account is not destined for regular interactions
    su --shell $(which bash) --login ${_user} <<'EOF'
source "${HOME}/.bash_aliases"
gem install bundler:'< 2' jekyll:'3.8.5' || exit 1
# rbenv rehash
mkdir -p ${HOME}/{git,www}

## Initialize Jekyll repo for user account
_old_PWD="${PWD}"
mkdir -vp "${HOME}/git/${USER}"
cd "${HOME}/git/${USER}"
git init .
git checkout -b gh-pages
bundle init
bundle install --path "${HOME}/.bundle/install"
bundle add jekyll-github-metadata github-pages
# bundle add jekyll
bundle exec jekyll new --force --skip-bundle "${HOME}/git/${USER}"
bundle install
git config receive.denyCurrentBranch updateInstead

cat >> "${HOME}/git/${USER}/.gitignore" <<EOL
# Ignore files and folders generated by Bundler
Bundler
vendor
.bundle
Gemfile.lock
EOL

echo -e '# Ignore folders generated by Bundler\nvendor\n.bundle' >> "${HOME}/git/${USER}/.gitignore"
git add --all
git -c user.name="${USER}" -c user.email="${USER}@${HOSTNAME}" commit -m "Added files from Bundler & Jekyll to git tracking"
cd "${_old_PWD}"
EOF

    printf '## %s finished\n' "${FUNCNAME[0]}"
}
