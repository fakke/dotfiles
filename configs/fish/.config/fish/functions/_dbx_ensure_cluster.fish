function _dbx_ensure_cluster --description 'Ensure Databricks cluster is RUNNING; prompt before starting'
    set -l info_cmd 'databricks clusters get $DATABRICKS_CLUSTER_ID -o json | jq -r "[.cluster_name, .state] | @tsv"'
    set -l info (string split \t -- (eval $info_cmd))
    set -l name $info[1]
    set -l state $info[2]
    test "$state" = RUNNING; and return 0

    if test "$state" = TERMINATED
        read -l -P "$name cluster is not running; start? [Y/n] " answer
        if string match -qir '^n' -- $answer
            return 1
        end
        databricks clusters start $DATABRICKS_CLUSTER_ID --no-wait >/dev/null; or return 1
        set state PENDING
    end

    echo "Starting $name cluster, waiting until it's ready..." >&2

    set -l t0 (date +%s)
    while test "$state" != RUNNING
        switch $state
            case ERROR UNKNOWN ''
                printf '\n%s cluster state: %s\n' $name "$state" >&2
                return 1
            case TERMINATED
                # settled to TERMINATED while we waited (e.g. after TERMINATING): ask again
                printf '\r\033[K' >&2
                _dbx_ensure_cluster
                return $status
        end
        printf '\r\033[K%s: %s... %ds' $name (string lower $state) (math (date +%s) - $t0) >&2
        sleep 5
        set info (string split \t -- (eval $info_cmd))
        set state $info[2]
    end
    printf '\r\033[K%s cluster is running (%ds). Executing...\n' $name (math (date +%s) - $t0) >&2
end

