function gh-upload-config
    set -l org $GH_ORG_CONFIG
    set -l host $GH_ORG_HOST
    set -l repo (basename $PWD)

    set -l name (git config user.name)

    if test -z "$name"
        set name (gh api user --jq .login 2>/dev/null)
    end

    if test -z "$name"
        echo "missing git user.name"
        return 1
    end

    git init -b main 2>/dev/null

    git config user.name "$name"
    git config user.email ""

    git add .

    if not git diff --cached --quiet
        git commit -m "init"
    end

    gh repo create "$org/$repo" --private --source=. --remote=origin

    git remote set-url origin "git@$host:$org/$repo.git"

    git push -u origin main

    echo "done: git@$host:$org/$repo.git"
end

function sh_add_var --description 'Persist/replace an env var in bash, zsh, and fish'
    if test (count $argv) -ne 2
        echo "usage: sh_add_var NAME VALUE" >&2
        return 1
    end
    set -l name $argv[1]
    set -l value $argv[2]

    # fish: -Ux overwrites any existing universal var automatically
    set -Ux $name $value

    set -l line "export $name=\"$value\""
    for f in ~/.bash_profile ~/.zprofile
        touch $f
        set -l tmp (mktemp)
        # drop any existing export of this var, keep everything else, add fresh line
        grep -vE "^[[:space:]]*export $name=" $f > $tmp
        echo $line >> $tmp
        mv $tmp $f
    end
    echo "updated $name in fish + bash/zsh profiles"
end

