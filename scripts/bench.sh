#!/usr/bin/env bash
# shellcheck disable=2207,2155,1007,1090
set -euo pipefail

clusterfile=
. "$(dirname "$0")"/lib.sh
. "$(dirname "$0")"/lib-nixops.sh
. "$(dirname "$0")"/lib-cluster.sh
. "$(dirname "$0")"/lib-benchrun.sh
. "$(dirname "$0")"/lib-analysis.sh
###
### TODO
###
##  1. Automate genesis using cardano-node's Nix code. Param details are key.
##  2. Debug why kill -9 on the tx-generator removes _node's_ socket.
##  3. Make tx-generator exit on completion (DONE in WIP generator).
##  4. Maintain a local representation of deployed cluster state.
##  5. Sanity checks:
##     - genesis on explorer matches that of the producers

usage() {
        cat >&2 <<EOF
USAGE:  $(basename "$0") OPTIONS.. [OP=bench-profile] OP-ARGS..

  Options:

    --verbose             Print slightly more diagnostics.
    --trace               set -x
    --help                This short help.
    --help-full           Extended help.

  Main OPs:

    init-params N         Make a default ${clusterfile}
                            for a cluster with N nodes.
    reinit-params         Update ${clusterfile} for current 'cardano-ops'.

    genesis [PROF=default]
                          Generate new genesis, according to ${clusterfile},
                            for a specific profile.

    bench-all             Run benchmark across all profiles in ${clusterfile}.
    bench-profile [PROF=default]
                          Run benchmark for a single profile.

    list-profiles | ps    List available benchmark profiles.
    list-runs | ls        List accumulated benchmark runs.

EOF
}

usage_extra() {
        cat >&2 <<EOF
  Extra options:

    --fast-unsafe         Ignore safety, go fast.  Deploys won't be made,
                            unprocessed logs will be lost.
    --deploy              Force redeployment, event if benchmarking
                            a single profile.
    --cls                 Clear screen.

  Other OPs:

    check-genesis-age [NODE=node-0] [SLOTLEN=20] [K=2160]
                          Test genesis of a deployed NODE, given SLOTLEN and K.
                            WARNING:  won't work with stopped nodes!
    deploy-cluster        Deploy the full cluster.


    bench-start           Cycle explorer & all nodes, and start the generator.
    bench-fetch           Fetch cluster logs.

    stop                  Stop the cluster, including all journald instances.

    archive-runs          Archive accumulated benchmark runs into ./runs-archive

    split-bench-log FILE  Decompose a combined generator + explorer node logfile
                            into message-classified streams, putting the result
                            into a directory named FILE.trace

    nodes CMD..           Run CMD either on forging nodes or the explorer.
    explorer CMD..

    jq-explorer [JQEXPR=.]
    jq-generator [JQEXPR=.]
    jq-nodes [JQEXPR=.]   Run JQ on the JSON logs of either forging nodes,
                            explorer+generator or just the generator.
                            Log entries are sorted by timestamp.

    blocks                'MsgBlock' messages seen by the explorer, incl. TxIds.

EOF
}

verbose= debug= trace=
no_deploy_producers=
no_deploy_explorer=
force_deploy=

cluster_txbench_trailing_empty_blocks=5

self=$(realpath "$0")

main() {
        local jq_select='cat'

        while test $# -ge 1
        do case "$1" in
           --fast-unsafe | --fu )
                   no_deploy_producers=t
                   no_deploy_explorer=t;;
           --deploy )             force_deploy=t;;
           --select )             jq_select="jq 'select ($2)'"; shift;;

           --cls )                echo -en "\ec">&2;;
           --quiet )              verbose=;;
           --verbose )            verbose=t;;
           --debug )              debug=t; verbose=t;;
           --trace )              debug=t; verbose=t; trace=t; set -x;;

           --goggles-ip )         goggles_fn=goggles_ip;;

           --help )               usage; exit 1;;
           --help-full | --help-all | --help-extra )
                                  usage; usage_extra; exit 1;;
           * ) break;; esac; shift; done

        export goggles_fn remote_jq_opts

        dprint "main ARGV[], post option parsing: ${*@Q}"

        local default_op='bench-profile'
        local op="${1:-${default_op}}"; shift || true

        case "${op}" in
                init-params | init | reinit-params | reinit ) true;;
                * ) clusterfile_init;; esac

        case "${op}" in
                init-params | init ) op_init_params "$@";;
                reinit-params | reinit )
                                      local node_count
                                      node_count=$(rcjq '
                                        (   .meta.node_names
                                         // .meta.nodeNames) # backward compat
                                        | length
                                        ')
                                      if test -z "$node_count"
                                      then fail "reinit:  cannot get node count from cluste file -- use init instead."; fi
                                      op_init_params "$node_count" "$@";;
                check-genesis-age | check-genesis | genesis-age | age )
                                      op_check_genesis_age "$@";;
                genesis )             op_genesis_byron "$@";;

                deploy-cluster | full-deploy | deploy )
                                      nixops_deploy "$@";;
                bench-start | start )
                                      op_bench_start "$@";;
                bench-fetch | fetch | f )
                                      op_bench_fetch "$@";;
                bench-analyse | analyse | a )
                                      export archive=$(realpath ./runs)
                                      analyse_tag "$@";;
                bench-package | package | pkg )
                                      export archive=$(realpath ./runs)
                                      package_tag "$@";;

                list-profiles | ps )
                                      rcjq 'del(.meta) | keys';;
                bench-profile | profile | p )
                                      test -z "${force_deploy}" ||
                                              nixops_deploy "$@"
                                      op_bench_profile "$@";;
                smoke-test | smoke | s )
                                      no_deploy_explorer=t
                                      cluster_txbench_trailing_empty_blocks=3
                                      op_bench_profile 'smoke-test';;

                bench-all | all )
                                      op_bench "$@";;

                list-runs | runs | ls )
                                      ls -1 runs/*/meta.json | cut -d/ -f2;;
                archive-runs | archive )
                                      mkdir -p  'runs-archive'
                                      mv runs/* 'runs-archive';;

                wait-for-empty-blocks | wait-empty | wait )
                                      op_wait_for_empty_blocks "$@";;
                stop )                op_stop "$@";;

                split-bench-log | split )
                                      op_split_benchmarking_log "$@";;

                nodes | n )           op_nodes       "$@";;
                explorer | e )        op_on 'explorer'    "$@";;

                jq-explorer | jqe )   op_jq 'explorer' "$@" | ${jq_select};;
                jq-generator | jqg )  op_jq_generator "$@" | ${jq_select};;
                jq-nodes | jqn )      op_jq_nodes    "$@" | ${jq_select};;

                pgrep )               op_pgrep "$@";;
                md5sum | md5 | hash ) op_hash "$@";;

                blocks )              op_blocks;;

                ## Query ./benchmarking-cluster-params.json, aka the "clusterfile".
                cjq )                 cjq "$@";;
                rcjq )                rcjq "$@";;
                cjqtest )             cjqtest "$@";;
                eval )                eval "${@@Q}";;
                * ) usage; exit 1;; esac
}

###
### Top-level operations
###

op_bench() {
        local all_profiles=($(cluster_sh profiles))
        local benchmark_schedule=("${all_profiles[@]}")

        echo "--( Benchmark across profiles:  ${benchmark_schedule[*]}"

        mkdir -p 'runs'

        if test -n "${no_deploy_producers}"
        then echo "--( Not deploying producers, --no-deploy-producers passed."
        else nixops_deploy 'default' "--include $(cluster_sh producers)" \
               "runs/$(date +%s).deploy-producers.log"; fi

        for p in ${benchmark_schedule[*]}
        do op_bench_profile "${p}"
        done
}

op_bench_profile() {
        local profspec="${1:-default}" prof deploylog
        deploylog='./last-explorer-deploy.log'
        prof=$(cluster_sh resolve-profile "$profspec")

        echo "--( Benchmarking profile:  ${prof:?Unknown profile $profspec, see ${clusterfile}}"
        if ! test -f "${deploylog}" -a -n "${no_deploy_explorer}"
        then nixops_deploy "${prof}" '--include explorer' "${deploylog}"; fi
        op_bench_start "${prof}" "${deploylog}"
        op_bench_fetch

        export archive=$(realpath ./runs)
        local tag
        tag=$(cluster_last_meta_tag)
        analyse_tag "${tag}"
        package_tag "${tag}"
}

op_bench_start() {
        local prof="$1" deploylog="$2" tag dir

        if ! cluster_sh has-profile "${prof}"
        then fail "Unknown profile '${prof}': check ${clusterfile}"; fi

        test -f "${deploylog}" ||
                fail "deployment required, but no log found in:  ${deploylog}"

        echo "--( Stopping generator.."
        nixops ssh explorer "systemctl stop tx-generator || true"

        echo "--( Stopping nodes & explorer.."
        op_stop

        echo "--( Cleaning explorer DB.."
        nixops ssh explorer -- sh -c "'PGPASSFILE=/var/lib/cexplorer/pgpass psql cexplorer cexplorer --command \"delete from tx_in *; delete from tx_out *; delete from tx *; delete from block; delete from slot_leader *; delete from epoch *; delete from meta *; delete from schema_version *;\"'"

        echo "--( Resetting node states: node DBs & logs.."
        nixops ssh-for-each --parallel "rm -rf /var/lib/cardano-node/db* /var/lib/cardano-node/logs/* /var/log/journal/*"

        echo "--( $(date), restarting nodes.."
        nixops ssh-for-each --parallel "systemctl start systemd-journald"
        sleep 3s
        nixops ssh-for-each --parallel "systemctl start cardano-node"
        nixops ssh explorer "systemctl start cardano-explorer-node cardano-db-sync 2>/dev/null"

        op_check_genesis_age

        tag=$(generate_run_id "${prof}")
        dir="./runs/${tag}"
        echo "--( creating new run:  ${tag}"
        op_register_new_run "${prof}" "${tag}" "${deploylog}"

        echo "--( $(date), starting generator.."
        nixops ssh explorer "systemctl start tx-generator"

        op_wait_for_nonempty_block 200

        time op_wait_for_empty_blocks \
               "$(jq ".[\"${prof}\"].run_params.finish_patience" <${clusterfile})" \
               fetch_systemd_unit_startup_logs

        echo "--( $(date), termination criteria satisfied, stopping cluster."
        op_stop
        echo "--( concluded run:  ${tag}"
}

fetch_systemd_unit_startup_logs() {
        local tag dir
        tag=$(cluster_last_meta_tag)
        dir="./runs/${tag}"

        pushd "${dir}" >/dev/null || return 1

        nixops ssh explorer \
          "journalctl --boot 0 -u tx-generator | head -n 100" \
          > 'logs/log-unit-startup-generator.log'
        nixops ssh explorer "journalctl --boot 0 -u cardano-node | head -n 100" \
          > 'logs/log-unit-startup-explorer.log'
        nixops ssh explorer "journalctl --boot 0 -u cardano-db-sync | head -n 100" \
          > 'logs/log-unit-startup-db-sync.log'

        for node in $(cluster_sh producers)
        do nixops ssh "${node}" "journalctl --boot 0 -u cardano-node | head -n 100" \
             > "logs/log-unit-startup-${node}.log"
        done
        popd >/dev/null
}

op_register_new_run() {
        local prof="$1" tag="$2" deploylog="$3"

        test -f "${deploylog}" ||
                fail "no deployment log found, but is required for registering a new benchmarking run."

        mkdir -p runs

        test -n "${tag}" || fail "cannot use an empty tag"

        local dir="./runs/${tag}"
        if test "$(realpath "${dir}")" = "$(realpath ./runs)" -o "${tag}" = '.'
        then fail "bad, bad tag"; fi

        rm -f                          ./runs-last
        ln -s                 "${dir}" ./runs-last
        rm -rf              ./"${dir}"/*
        mkdir -p              "${dir}/logs"
        mkdir -p              "${dir}/meta"

        cp "${clusterfile}"   "${dir}"
        cp 'nix/sources.json' "${dir}"/meta/sources.json
        cat                 > "${dir}"/meta/cluster.raw.json <<EOF
{$(nixops_query_cluster_state | sed ':b; N; s_\n_,_; b b' | sed 's_,_\n,_g')
}
EOF
        cp "${deploylog}"     "${dir}"/logs/deploy.log
        mv "${deploylog}"     runs/"${tag}".deploy.log

        local date=$(date "+%Y-%m-%d-%H.%M.%S") stamp=$(date +%s)
        touch                 "${dir}/${date}"

        local nixops_meta
        nixops_meta=$(grep DEPLOYMENT_METADATA= runs/"${tag}".deploy.log |
                        head -n1 | cut -d= -f2)

        local        metafile="${dir}"/meta.json
        ln -sf    "${metafile}" last-meta.json
        jq      > "${metafile}" "
{ meta: {
    timestamp:         ${stamp},
    date:              \"${date}\",
    node:              $(jq '.["cardano-node"].rev'         nix/sources.json),
    benchmarking:      $(jq '.["cardano-benchmarking"].rev' nix/sources.json),
    \"db-sync\":       $(jq '.["cardano-db-sync"].rev'      nix/sources.json),
    tag:               \"${tag}\",
    profile:           \"${prof}\",
    generator_params:  $(jq ."[\"${prof}\"]" "${clusterfile}" |
                         sed 's_^_      _'),
    ops:               \"$(git rev-parse HEAD)\",
    modified:          $(if git diff --quiet --exit-code
                       then echo false; else echo true; fi),
    manifest: [
      \"${date}\",
      \"${clusterfilename}\",
      \"meta.json\",

      \"meta/cluster.raw.json\",
      \"meta/sources.json\",

      \"logs/deploy.log\",
      \"logs/block-arrivals.gauge\",
      \"logs/db-analysis.log\",
      \"logs/db-analysis.tar.xz\",
      \"logs/log-explorer-generator.tar.xz\",
      \"logs/log-nodes.tar.xz\",

      \"tools/*.sql\",
      \"tools/*.sh\" ]
    , nixops_metafile: \"${nixops_meta}\"
    , nixops:          $(jq . "${nixops_meta}")
  }
, hostname:
  $(jq 'to_entries
   | map ({ key:   .key
          , value: (.value + { hostname: .key })
          })
   | from_entries' "${dir}"/meta/cluster.raw.json)
, local_ip:
  $(jq  'to_entries
   | map ({ key:   .value.local_ip
          , value: (.value + { hostname: .key })
          })
   | from_entries' "${dir}"/meta/cluster.raw.json)
, public_ip:
  $(jq  'to_entries
   | map ({ key:   .value.public_ip
          , value: (.value + { hostname: .key })
          })
   | from_entries' "${dir}"/meta/cluster.raw.json)
}" --null-input
}

op_wait_for_nonempty_block() {
        local patience="$1" date patience_until now r prev=0
        start=$(date +%s)
        patience_until=$((start + patience))

        echo -n "--( Waiting for a non-empty block on explorer (patience for ${patience}s).  Seen empty: 00"
        while now=$(date +%s); test "${now}" -lt ${patience_until}
        do r=$(nixops ssh explorer -- sh -c "'tac /var/lib/cardano-node/logs/node.json | grep -F MsgBlock | jq \"select(.data.msg.txids != [])\" | wc -l'")
           if test "$r" -ne 0
           then l=$(nixops ssh explorer -- sh -c \
                   "'tac /var/lib/cardano-node/logs/node.json | grep -F MsgBlock | jq \".data.msg.txids | select(. != []) | length\"'")
                echo ", got [$l], after $((now - start)) seconds"
                return 0; fi
           e=$(nixops ssh explorer -- sh -c \
                   "'tac /var/lib/cardano-node/logs/node.json | grep -F MsgBlock | jq --slurp \"map (.data.msg.txids | select(. == [])) | length\"'")
           echo -ne "\b\b"; printf "%02d" "$e"
           sleep 5; done
        echo " patience ran out."
        fail "\nNo non-empty blocks reached the explorer in ${patience} seconds -- is the cluster dead (genesis mismatch?)?"
}

op_wait_for_empty_blocks() {
        local slot_length=20
        local block_propagation_tolerance=1
        local full_patience="$1"
        local oneshot_action="${2:-true}"
        local patience=${full_patience}

        echo -n "--( Waiting for empty blocks (txcounts): "
        local last_blkid='absolut4ly_n=wher'
        local news=
        while test ${patience} -gt 0
        do while news=$(nixops ssh explorer -- sh -c "'set -euo pipefail; { echo \"{ data: { msg: { blkid: 0, txids: [] }}}\"; tac /var/lib/cardano-node/logs/node.json; } | grep -F MsgBlock | jq --compact-output \".data.msg | { blkid: .blkid, tx_count: (.txids | length) } \"'" |
                        sed -n '0,/'$last_blkid'/ p' |
                        head -n-1 |
                        jq --slurp 'reverse | ## undo order inversion..
                          { txcounts: map (.tx_count)
                          , blks_txs: map ("\(.tx_count):\(.blkid)")
                          , last_blkid: (.[-1] // { blkid: "'${last_blkid}'"}
                                        | .blkid)
                          }')
                 last_blkid=$(jq --raw-output .last_blkid <<<$news)
                 if test -n "${oneshot_action}"
                 then $oneshot_action; oneshot_action=; fi
                 echo -n " "
                 if test -z "${verbose}"
                 then jq -cj '.txcounts'
                 else echo -n "p${patience}"
                      jq -cj '.blks_txs | join(",") | "["+.+"]"'
                 fi <<<$news
                 ## A reasonable delay to see a new block.
                 sleep $((slot_length + block_propagation_tolerance))
                 jqtest '.txcounts
                        | length == 0
                          or (all (. == 0) | not)' <<<$news
           do if jqtest '.txcounts | length != 0' <<<$news
              then patience=${full_patience}
                   test -z "${verbose}" || echo -n "=${patience}"; fi; done
           patience=$((patience - 1))
           test -z "${verbose}" || echo -n "p${patience}"
        done | tee "runs-last/logs/block-arrivals.gauge"
        echo
}

op_bench_fetch() {
        local tag dir components
        tag=$(cluster_last_meta_tag)
        dir="./runs/${tag}"

        echo "--( Run directory:  ${dir}"
        pushd "${dir}" >/dev/null || return 1

        run_fetch_benchmarking 'tools'

        echo "--( Fetching the SQL extraction from explorer.."
        components=($(ls tools/*.sql | cut -d/ -f2))
        cat >'tools/db-analyser.sh' <<EOF
        set -e
        tag="\$1"

        files=()
        for query in ${components[*]}
        do files+=(\${query} \${query}.txt \${query}.csv)

           PGPASSFILE=/var/lib/cexplorer/pgpass psql cexplorer cexplorer \
             --file \${query} > \${query}.csv --csv
           PGPASSFILE=/var/lib/cexplorer/pgpass psql cexplorer cexplorer \
             --file \${query} > \${query}.txt
        done

        tar=${tag}.db-analysis.tar.xz
        tar cf \${tar} "\${files[@]}" --xz
        rm -f ${components[*]/%/.csv} ${components[*]/%/.txt}
EOF
        tar c 'tools/db-analyser.sh' "${components[@]/#/tools\/}" |
                nixops ssh explorer -- tar x --strip-components='1'
        nixops ssh explorer -- sh -c "ls; chmod +x 'db-analyser.sh';
                                      ./db-analyser.sh ${tag}" > 'logs/db-analysis.log'
        nixops scp --from explorer "${tag}.db-analysis.tar.xz" 'logs/db-analysis.tar.xz'

        local producers
        producers=($(cluster_sh producers))
        echo "--( Fetching logs from:  explorer ${producers[*]}"
        mkdir -p 'logs'
        cd       'logs'

        for mach in 'explorer' ${producers[*]}
        do nixops ssh "${mach}" -- \
             "cd /var/lib/cardano-node/logs &&
              cat node-*.json > log-\${HOSTNAME}.json &&
              rm  node-*.json node.json &&
              tar c --xz                            *.json" |
           tar x --xz; done

        echo "--( Packing logs.."
        local explorer_logs=(
                generator.json    log-unit-startup-generator.log
                log-explorer.json log-unit-startup-explorer.log
                                  log-unit-startup-db-sync.log
        )
        tar cf log-explorer-generator.tar.xz --xz -- ${explorer_logs[*]}
        rm -- ${explorer_logs[*]}

        ## The rest must be node logs..
        tar cf log-nodes.tar.xz    --xz -- *.json log-unit-startup-*.log
        rm -f                           -- *.json log-unit-startup-*.log

        popd >/dev/null

        echo "--( logs collected from run:  ${tag}"
}

# Keep this at the very end, so bash read the entire file before execution starts.
main "$@"
