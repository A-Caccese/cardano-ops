# Cardano benchmarking infrastructure

### Contents

1.  *Overview*
2.  *Clusters*
3.  *The =bench= command*
4.  *Quick action: running a benchmark without much ado:*
5.  *Profiles and the benchmarking cluster parameters file*
6.  *Benchmark run results*

### Overview

The benchmarking infrastructure consists of the following components:

  - The `cardano-benchmarking` repository, which contains:
      - log analysis scripts, in the `scripts/` subdirectory
      - the `cardano-tx-generator`, that generates Tx load on arbitrary
        nodes,
      - a NixOS service definition for the generator, in
        `nix/nixos/tx-generator-service.nix`
  - The `cardano-ops` repository, with:
      - the general cluster deployment infrastructure,
      - a specific, benchmarking-oriented deployment type, defined in
        `globals-bench-txgen-simple.nix`,
      - the `bench` script, that automates benchmark runs.
  - A number of cluster deployments, on the development deployer, that
    have `cardano-ops` checkouts & benchmarking configuration set up in
    each of them, in the form of `benchmarking-cluster-params.json`
    files.

### Clusters

Benchmarking clusters are available on the development deployer, and
currently include:

  - remote-dev-cluster-3
  - remote-dev-cluster-6
  - remote-dev-cluster-9
  - remote-dev-cluster-12

### The `bench` command

Benchmarking clusters are controlled using the `bench` command, which is
equivalent to an alias of `./scripts/bench.sh` in the current
development checkout.

The command automates a significant part of the benchmarking workflow:

  - definition of multiple benchmarking profiles
  - generating genesis
  - deploying the cluster
  - running the benchmark profiles
  - collecting & doing basic analysis on the logs
  - packaging the profile run data

### Quick action: running a benchmark without much ado:

1.  Access the cluster deployment environment:
    
      - log into the development deployer
      - `cd $CLUSTER`
      - update the `cardano-ops` checkout to the desired version
      - enter the `nix-shell`

2.  Ensure the cluster params file (`benchmarking-cluster-params.json`)
    is up-to-date with the current `cardano-ops` checkout:
    
    ``` example
    bench reinit-params
    ```
    
    This step is only necessary when `cardano-ops` is updated in a major
    way, which is rarely the case.

3.  Deploy the full cluster:
    
    ``` example
    bench deploy
    ```
    
    This is only generally necessary in the following situations:
    
      - after genesis update (which is performed by `bench genesis`),
        and
      - after `cardano-node` version changes.

4.  At this point you are prepared to run a benchmark – either for a
    single profile:
    
    ``` example
    bench bench-profile [PROFILE]
    ```
    
    The profile name is optional, and defaults to `default`, which
    refers to a profile specified in the cluster params file (see the
    `.meta.default_profile` JSON key).
    
    Normally, the default profile is the first one listed.
    
    Or, alternatively, the benchmark could be run for all profiles
    specified in the cluster params file:
    
    ``` example
    bench bench-all
    ```

5.  Every benchmark cycle provides an archive at the root of the
    cluster's deployment checkout, f.e.:
    
    ``` example
    2020-05-18.dist3-50000tx-100b-1i-1o-100tps.tar.xz
    ```

### Profiles and the benchmarking cluster parameters file

Each benchmarking cluster obtains its profile definitions and other
metadata from a local file called `./benchmarking-cluster-params.json`.

This cluster parameterisation file is generated, and the generator
accepts a single parameter – cluster size:

``` example
bench init-params 3
```

This produces a JSON object, that defines benchmarking profiles (except
for its `meta` component, which carries things like node names and
genesis configuration).

Benchmarking profiles serve as named sets of parameters for benchmarking
runs, and can be listed with:

``` example
bench list-profiles                                   # ..or just 'bench ps'
```

As mentioned in the *Quick action* section, we can run benchmarks
per-profile:

``` example
bench bench-profile dist3-50000tx-100b-1i-1o-100tps   # defaults to 'default'
```

..or for all defined profiles:

``` example
bench bench-all
```

1.  Changing the set of available profiles
    
    It's not advised to edit the cluster parameters file directly –
    because doing so would force us to update this file manually,
    whenever the `bench` script changes – we should, instead, change the
    definition of its generator.
    
    Note that this is still currently a bit ad-hoc, but will improve,
    once the declarative definition for the profile specs is
    implemented.

### Benchmark run results

Each successful benchmark run produces the following results:

1.  A run output directory, such as:
    
    ``` example
    ./runs/1589819135.27a0a9dc.refinery-manager.pristine.node-66f0e6d4.tx50000.l100.i1.o1.tps100
    ```
    
    This directory (also called "tag", internally), contains:
    
    1.  `meta.json` – the run's metadata, a key piece in its processing,
    
    2.  a copy of `benchmarking-cluster-params.json`, taken at the
        benchmark execution time,
    
    3.  `meta/*` – some run metadata: cluster parameters fetched from
        its machines & the `niv` pins,
    
    4.  `logs/*` – various logs, both deployment, service startup and
        runtime, for all the nodes (including explorer) and the Tx
        generator. This also includes an extraction from the
        `cardano-db-sync` database.
    
    5.  `analysis/*` – some light extraction based on the available
        logs.
    
    6.  `tools/*` – the tools used to perform the above extraction,
        fetched from the `cardano-benchmarking` repo.

2.  An archive in the deployment checkout, that contains the exact
    *content* of that directory, but placed in a directory with a
    user-friendly name:
    
    ``` example
    ./YYYY-MM-DD.$PROFILE_NAME.tar.xz
    ```
