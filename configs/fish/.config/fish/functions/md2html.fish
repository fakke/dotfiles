function md2html --description "Render a Markdown file to standalone HTML (md-renderer look, paste-friendly)"
    if test (count $argv) -eq 0
        echo "usage: md2html <input.md> [output.html]" >&2
        return 1
    end

    if not test -f ~/.local/share/md2html/md2html.py
        echo "md2html: install ~/.local/share/md2html/md2html.py first" >&2
        return 1
    end

    # shares the md2pdf venv (same markdown package); bootstraps it if missing
    set -l venv ~/.local/share/md2pdf/venv

    if not test -x $venv/bin/python
        echo "md2html: first run — creating venv at $venv" >&2
        python3 -m venv $venv
        or begin
            echo "md2html: venv creation failed" >&2
            return 1
        end
        $venv/bin/pip --quiet install markdown
        or begin
            echo "md2html: pip install markdown failed" >&2
            return 1
        end
    end

    $venv/bin/python ~/.local/share/md2html/md2html.py $argv
end
