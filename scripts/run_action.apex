// Run the action from the CLI without the agent (quick smoke test):
//   sf apex run --file scripts/run_action.apex --target-org demo
AtRiskAccountsAction.Request req = new AtRiskAccountsAction.Request();
req.maxResults = 5;
req.onlyMyAccounts = false;
List<AtRiskAccountsAction.Response> res =
    AtRiskAccountsAction.run(new List<AtRiskAccountsAction.Request>{ req });
System.debug(LoggingLevel.ERROR, '\n' + res[0].summary);
