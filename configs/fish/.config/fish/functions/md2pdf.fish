function md2pdf --description "Render a Markdown file (with local images) to a self-contained PDF"
    if test (count $argv) -eq 0
        echo "usage: md2pdf <input.md> [output.pdf]" >&2
        return 1
    end

    if not test -f ~/.local/share/md2pdf/md2pdf.py
        echo "md2pdf: install ~/.local/share/md2pdf/md2pdf.py first" >&2
        return 1
    end

    set -l app_dir ~/.local/share/md2pdf
    set -l venv $app_dir/venv

    # one-time bootstrap: private venv with the markdown package
    if not test -x $venv/bin/python
        echo "md2pdf: first run — creating venv at $venv" >&2
        python3 -m venv $venv
        or begin
            echo "md2pdf: venv creation failed" >&2
            return 1
        end
        $venv/bin/pip --quiet install markdown
        or begin
            echo "md2pdf: pip install markdown failed" >&2
            return 1
        end
    end

    $venv/bin/python $app_dir/md2pdf.py $argv
end
