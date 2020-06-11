# List of peers included in our relays topology config,
# evenly split across all IOHK FF relays.
# Pull-requests against this file will be merged and deployed once a day.
[
  {
    operator = "disassembler";
    addr = "prophet.samleathers.com";
    port = 3001;
  }
    {
    operator = "planetstake";
    addr = "stake-relay1.planetstake.com";
    port = 3001;
  }
  {
    operator = "planetstake";
    addr = "stake-relay2.planetstake.com";
    port = 3002;
  }
  {
    operator = "planetstake";
    addr = "stake-relay3.planetstake.com";
    port = 3003;
  }
  {
    operator = "clio";
    addr = "relays.ff.clio.one";
    port = 6000;
    valency = 1;
  }
  {
    operator = "SkyLightPool";
    addr = "relay1.oqulent.com";
    port = 3007;
    valency = 1;
  }
  {
    operator = "SkyLightPool";
    addr = "relay2.oqulent.com";
    port = 3008;
    valency = 1;
  }
  {
    operator = "homer1";
    addr = "95.216.188.94";
    port = 9000;
  }
]
