{ pkgs, lib, options, config, nodes, resources,  ... }:
with (import ../nix {});
let
  inherit (import sources.iohk-nix {}) cardanoLib;

  toCardanoEnvName = env: {
    # mapping of environnement name from globals.nix to the one defined in cardanoLib:
    stagingshelleyshort = "shelley_staging_short";
    stagingshelley      = "shelley_staging";
  }.${env} or env;

  nodePort = 3001;
  monitoringPorts = [ 9100 9102 9113 ];
  hostAddr = if options.networking.privateIPv4.isDefined then config.networking.privateIPv4 else "0.0.0.0";
  nodeId = config.services.cardano-node.nodeId;
  # TODO: this doesn't work, perhaps publicIPv4 is empty, I need a way to filter out self node
  otherNodes = builtins.filter (node: node.config.networking.publicIPv4 != options.networking.publicIPv4) (builtins.attrValues nodes);
  mkProducer = node: { addr = node.config.networking.publicIPv4; port = 3001; valency = 1; };
  producers = map mkProducer otherNodes;
  region = config.deployment.ec2.region;
  loggerConfig = import ./iohk-monitoring-config.nix;
in
{
  imports = [
    iohk-ops-lib.modules.common
    (sources.cardano-node + "/nix/nixos")
  ];

  deployment.ec2.securityGroups = [
    resources.ec2SecurityGroups."allow-all-${region}" # Temporarily allow all until we fix allow-monitoring-collection
    resources.ec2SecurityGroups."allow-cardano-node-${region}"
    resources.ec2SecurityGroups."allow-ssh-${region}"
    resources.ec2SecurityGroups."allow-monitoring-collection-${region}"
  ];

  networking.firewall = {
    allowedTCPPorts = [ nodePort ] ++ monitoringPorts;

    # TODO: securing this depends on CSLA-27
    # NOTE: this implicitly blocks DHCPCD, which uses port 68
    allowedUDPPortRanges = [ { from = 1024; to = 65000; } ];
  };

  services.cardano-node = {
    enable = true;
    pbftThreshold = "0.9";
    consensusProtocol = "real-pbft";
    inherit hostAddr;
    port = nodePort;
    topology = builtins.toFile "topology.yaml" (builtins.toJSON 
                 [ { nodeAddress = { addr = hostAddr; port = nodePort; };
                   inherit nodeId producers;
                 } ]);
    logger.configFile = builtins.toFile "log-config.json" (builtins.toJSON loggerConfig);
  };
}
