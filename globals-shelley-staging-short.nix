pkgs: {

  deploymentName = "staging-shelley-short";

  environmentName = "shelley_staging_short";

  topology = import ./topologies/staging-shelley-short.nix;

  ec2 = {
    credentials = {
      accessKeyIds = {
        IOHK = "dev-deployer";
        dns = "dev-deployer";
      };
    };
  };
}
