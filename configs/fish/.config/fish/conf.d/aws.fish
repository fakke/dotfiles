# expected env:
# EC2_REGION
# EC2_DEV     - instance id
# EC2_VOL_DEV - volume id

function ec2_dns
    set -x EC2_DEV_DNS (aws ec2 describe-instances \
        --instance-ids "$EC2_DEV" \
        --query "Reservations[0].Instances[0].PublicDnsName" \
        --output text)

    if test -z "$EC2_DEV_DNS" || test "$EC2_DEV_DNS" = "None"
        echo "Could not fetch DNS. Is the instance running?"
        return 1
    end

    echo "EC2_DEV_DNS set to: $EC2_DEV_DNS"
end

function ec2_ls
    aws ec2 describe-instances \
        --region $EC2_REGION \
        --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,State.Name,PublicIpAddress]' \
        --output table
end

function ec2_types
    set -l filter $argv[1]
    if test -z "$filter"
        set filter "t3* t4g*"
    end

    set -l long_region $EC2_REGION_LONG

    if test -z "$long_region"
        switch $EC2_REGION
            case "us-east-1";      set long_region "US East (N. Virginia)"
            case "us-east-2";      set long_region "US East (Ohio)"
            case "us-west-1";      set long_region "US West (N. California)"
            case "us-west-2";      set long_region "US West (Oregon)"
            case "eu-west-1";      set long_region "Europe (Ireland)"
            case "eu-west-2";      set long_region "Europe (London)"
            case "eu-west-3";      set long_region "Europe (Paris)"
            case "eu-central-1";   set long_region "Europe (Frankfurt)"
            case "eu-north-1";     set long_region "Europe (Stockholm)"
            case "ap-southeast-1"; set long_region "Asia Pacific (Singapore)"
            case "ap-southeast-2"; set long_region "Asia Pacific (Sydney)"
            case "ap-northeast-1"; set long_region "Asia Pacific (Tokyo)"
            case "ap-northeast-2"; set long_region "Asia Pacific (Seoul)"
            case "ap-south-1";     set long_region "Asia Pacific (Mumbai)"
            case "sa-east-1";      set long_region "South America (Sao Paulo)"
            case "ca-central-1";   set long_region "Canada (Central)"
            case '*'
                echo "Unknown region: $EC2_REGION. Set EC2_REGION_LONG manually." >&2
                return 1
        end
    end

    printf "%-20s %6s %12s %10s %10s %14s\n" \
        "INSTANCE TYPE" "vCPUs" "MEMORY (MiB)" "ARCH" "FREE TIER" '$/HR (ON-DEMAND)'
    printf "%-20s %6s %12s %10s %10s %14s\n" \
        "--------------------" "------" "------------" "----------" "----------" "--------------"

    set -l filter_csv (string replace -a ' ' ',' $filter)

    aws ec2 describe-instance-types \
        --region "$EC2_REGION" \
        --filters "Name=instance-type,Values=$filter_csv" \
        --query 'InstanceTypes[*].[InstanceType, VCpuInfo.DefaultVCpus, MemoryInfo.SizeInMiB, ProcessorInfo.SupportedArchitectures[0], FreeTierEligible]' \
        --output json \
    | jq -c '.[]' | while read -l row
        set -l itype (echo $row | jq -r '.[0]')
        set -l vcpus (echo $row | jq -r '.[1]')
        set -l mem   (echo $row | jq -r '.[2]')
        set -l arch  (echo $row | jq -r '.[3]')
        set -l free  (echo $row | jq -r '.[4]')

        set -l price (aws pricing get-products \
            --service-code AmazonEC2 \
            --region us-east-1 \
            --filters \
                "Type=TERM_MATCH,Field=instanceType,Value=$itype" \
                "Type=TERM_MATCH,Field=location,Value=$long_region" \
                "Type=TERM_MATCH,Field=operatingSystem,Value=Linux" \
                "Type=TERM_MATCH,Field=tenancy,Value=Shared" \
                "Type=TERM_MATCH,Field=capacitystatus,Value=Used" \
                "Type=TERM_MATCH,Field=preInstalledSw,Value=NA" \
            --query 'PriceList[0]' \
            --output text 2>/dev/null \
            | jq -r '.terms.OnDemand | to_entries[0].value.priceDimensions | to_entries[0].value.pricePerUnit.USD' 2>/dev/null)

        if test -z "$price"
            set price "N/A"
        end

        printf "%-20s %6s %12s %10s %10s %14s\n" \
            "$itype" "$vcpus" "$mem" "$arch" "$free" "$price"
    end | sort
end

function ec2_set_type
    set -l new_type $argv[1]
    set -l instance_id $argv[2]
    if test -z "$instance_id"
        set instance_id $EC2_DEV
    end

    if test -z "$new_type"
        echo "Usage: ec2_set_type <instance-type> [instance-id]"
        return 1
    end
    if test -z "$instance_id"
        echo "EC2_DEV not set and no instance-id provided"
        return 1
    end

    set -l state (aws ec2 describe-instances \
        --region $EC2_REGION \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)

    if test "$state" != "stopped"
        echo "Instance must be stopped first (current state: $state)"
        return 1
    end

    aws ec2 modify-instance-attribute \
        --region $EC2_REGION \
        --instance-id "$instance_id" \
        --instance-type Value="$new_type" \
        --output text > /dev/null

    echo "Instance $instance_id type changed to $new_type"
end

function ec2_start
    set -l instance_id $argv[1]
    if test -z "$instance_id"
        set instance_id $EC2_DEV
    end
    if test -z "$instance_id"
        echo "Usage: ec2_start <instance-id> or set EC2_DEV"
        return 1
    end

    aws ec2 start-instances --region $EC2_REGION --instance-ids "$instance_id" --output text > /dev/null
    echo -n "Starting $instance_id"

    while test (aws ec2 describe-instances --region $EC2_REGION --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' --output text) != "running"
        echo -n "."
        sleep 1
    end

    set -l ip ""
    while test -z "$ip" || test "$ip" = "None"
        set ip (aws ec2 describe-instances --region $EC2_REGION --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
        sleep 1
    end

    awk -v ip="$ip" '
        /^Host ec2-dev/{found=1} found && /HostName/{sub(/[^ \t]+$/, ip); found=0} {print}
    ' ~/.ssh/config > ~/.ssh/config.tmp && mv ~/.ssh/config.tmp ~/.ssh/config

    echo " ready at $ip"
end

function ec2_stop
    set -l instance_id $argv[1]
    if test -z "$instance_id"
        set instance_id $EC2_DEV
    end
    if test -z "$instance_id"
        echo "Usage: ec2_stop <instance-id> or set EC2_DEV"
        return 1
    end

    aws ec2 stop-instances --region $EC2_REGION --instance-ids "$instance_id" --output text > /dev/null
    echo -n "Stopping $instance_id"

    while test (aws ec2 describe-instances --region $EC2_REGION --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' --output text) != "stopped"
        echo -n "."
        sleep 1
    end

    ec2_ls
end

function ec2_resize
    set -l instance_id $argv[1]
    set -l new_type $argv[2]
    if test -z "$instance_id" || test -z "$new_type"
        echo "Usage: ec2_resize <instance-id> <new-instance-type>"
        return 1
    end
    echo "Stopping instance $instance_id..."
    aws ec2 stop-instances --instance-ids "$instance_id"
    aws ec2 wait instance-stopped --instance-ids "$instance_id"
    echo "Modifying instance type to $new_type..."
    aws ec2 modify-instance-attribute --instance-id "$instance_id" --instance-type "{\"Value\": \"$new_type\"}"
    aws ec2 start-instances --instance-ids "$instance_id"
    echo "Instance $instance_id resized to $new_type and started."
end

function ec2_snap_ls
    aws ec2 describe-snapshots \
        --owner-ids self \
        --query "Snapshots[*].[SnapshotId,VolumeId,VolumeSize,State,StartTime,Description]" \
        --output table
end

function ec2_snap_create
    set -l vol $argv[1]
    if test -z "$vol"
        echo "Usage: ec2_snapshot <volume-id>"
        return 1
    end
    aws ec2 create-snapshot \
        --volume-id "$vol" \
        --description "Snapshot "(date +'%Y-%m-%d %H:%M:%S')
end

function ec2_snap_restore
    set -l snap $argv[1]
    set -l az $argv[2]
    if test -z "$snap" || test -z "$az"
        echo "Usage: ec2_snap_restore <snapshot-id> <availability-zone>"
        return 1
    end
    aws ec2 create-volume \
        --snapshot-id "$snap" \
        --availability-zone "$az" \
        --volume-type gp3
end

function ec2_vol_ls
    aws ec2 describe-volumes \
        --query "Volumes[*].[VolumeId,Size,State,AvailabilityZone,Attachments[0].InstanceId,Attachments[0].Device]" \
        --output table
end

function ec2_vol_ls_i
    aws ec2 describe-volumes \
        --filters Name=attachment.instance-id,Values="$argv[1]" \
        --query "Volumes[*].[VolumeId,Size,State,Attachments[0].Device]" \
        --output table
end

function ec2_session
    ssh ec2-dev -t 'tmux new-session -d -s dev -x "$(tput cols)" -y "$(tput lines)" 2>/dev/null; \
        tmux new-window -t dev:0 -n home 2>/dev/null; \
        tmux send-keys -t dev:0 "nvim ~" Enter; \
        tmux split-window -t dev:0 -v; \
        tmux new-window -t dev:1 -n project 2>/dev/null; \
        tmux send-keys -t dev:1 "cd ~/project && nvim ." Enter; \
        tmux split-window -t dev:1 -v; \
        tmux new-window -t dev:2 -n claude 2>/dev/null; \
        tmux send-keys -t dev:2 "cd ~/project && claude" Enter; \
        tmux attach-session -t dev'
end

function aws_bill_last
    set -l start
    if test (uname) = Darwin
        set start (date -v1d -v-1m +%Y-%m-01)
    else
        set start (date -d "$(date +%Y-%m-01) -1 month" +%Y-%m-01)
    end
    set -l end (date +%Y-%m-01)
    aws ce get-cost-and-usage \
        --time-period Start=$start,End=$end \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.UnblendedCost.Amount]' \
        --output table
end

function aws_bill
    set -l start (date +%Y-%m-01)
    set -l end
    if test (uname) = Darwin
        set end (date -v+1d +%Y-%m-%d)
    else
        set end (date -d tomorrow +%Y-%m-%d)
    end
    aws ce get-cost-and-usage \
        --time-period Start=$start,End=$end \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --group-by Type=DIMENSION,Key=SERVICE \
        --query 'ResultsByTime[0].Groups[*].[Keys[0],Metrics.UnblendedCost.Amount]' \
        --output table
end

function aws_bill_total
    set -l start (date +%Y-%m-01)
    set -l end (date +%Y-%m-%d)
    aws ce get-cost-and-usage \
        --time-period Start=$start,End=$end \
        --granularity MONTHLY \
        --metrics "UnblendedCost" \
        --query 'ResultsByTime[0].Total.UnblendedCost.[Amount,Unit]' \
        --output text | awk '{ printf "%.4f %s\n", $1, $2 }'
end

function aws_bill_forecast
    set -l start (date +%Y-%m-%d)
    set -l end
    if test (uname) = Darwin
        set end (date -v1d -v+1m +%Y-%m-01)
    else
        set end (date -d "$(date +%Y-%m-01) +1 month" +%Y-%m-01)
    end
    aws ce get-cost-forecast \
        --time-period Start=$start,End=$end \
        --metric UNBLENDED_COST \
        --granularity MONTHLY \
        --query '[Total.Amount, Total.Unit]' \
        --output table
end
